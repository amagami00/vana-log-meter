import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

/// 監視中の流れ（読み込みごとに名簿→集計→CSV 行）を再現し、集計と CSV を返す。
/// 1 回目の読み込みは時刻なし、2 回目以降は [times] の時刻を付ける。
({SummaryAccumulator live, String csv, NameMasker? masker}) record(
  List<List<(String, int, int)>> batches,
  List<DateTime?> times, {
  bool mask = false,
}) {
  final p = CombatParser();
  final roster = Roster();
  final live = SummaryAccumulator();
  final masker = mask ? NameMasker(jobs: {'Alice': '戦/侍'}) : null;
  final startedAt = DateTime(2026, 11, 20, 12);
  final rows = <Map<String, Object?>>[];
  var n = 0;
  for (final (i, batch) in batches.indexed) {
    final added = [
      for (final (text, mode, msg) in batch)
        ...p.add(
          logLine(text, mode: mode, msg: msg, line: ++n),
          observedAt: times[i],
        ),
    ];
    roster.addAll(added);
    live.add(added, roster);
    var r = toRows(added, session: 's1', roster: roster, startedAt: startedAt);
    if (masker != null) {
      masker
        ..forgetEnemies(roster)
        ..learn(added, roster);
      r = masker.maskRows(r);
    }
    rows.addAll(r);
  }
  return (live: live, csv: toCsv(rows), masker: masker);
}

List<String> describe(List<ActorSummary> list, [String Function(String)? display]) => [
  for (final s in list)
    [
      (display ?? (n) => n)(s.name),
      s.damage,
      s.meleeHits,
      s.meleeMisses,
      s.meleeCrits,
      s.wsCount,
      s.wsMax,
      s.addDamage,
      s.scDamage,
      s.heal,
      s.dps?.toStringAsFixed(3),
    ].join('|'),
];

void main() {
  final t0 = DateTime(2026, 11, 20, 12, 0, 5, 250);
  final batches = [
    [
      ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 1),
      // Bob はまだ味方と分からないので、この WS は集計に入らない（記録時の判定）。
      ('Bobは、Fooを実行。', 0x19, 2),
      ('→Goblinに、500ダメージ。', 0x19, 2),
    ],
    [
      ('Bobの攻撃→Goblinに、50ダメージ。', 0x19, 3),
      ('Aliceの攻撃→Goblinに、ミス。', 0x14, 4),
      ('CarolのBaz→AliceのHPが、300回復。', 0x19, 5),
    ],
    [
      ('Aliceの攻撃。クリティカル！', 0x14, 6),
      ('→Orcに、200ダメージ。', 0x14, 6),
      ('Orcの攻撃→Aliceに、40ダメージ。', 0x20, 7),
    ],
  ];
  final times = [null, t0, t0.add(const Duration(milliseconds: 3500))];

  test('書き出した CSV を読み戻すと、監視中と同じ集計になる', () {
    final rec = record(batches, times);
    final log = RecordedLog()..addCsv(rec.csv, source: 'a.csv');
    expect(describe(log.summary.summaries()), describe(rec.live.summaries()));
    expect(log.summary.enemies(), rec.live.enemies());
    expect(
      describe(log.summary.summaries(enemies: ['Goblin'])),
      describe(rec.live.summaries(enemies: ['Goblin'])),
    );
    expect(log.summary.timeOf(), rec.live.timeOf());
    expect(log.summary.timeOf(), const Duration(milliseconds: 4500));
    expect(log.eventCount, rec.live.count);
    // 記録時に判定できなかった Bob の WS は数えない。
    expect(log.summary.summaries().firstWhere((s) => s.name == 'Bob').damage, 50);
    expect(log.sources, ['a.csv']);
  });

  test('名簿は読み込みごとに更新する（後から敵と分かった名前の、それ以前の回復も監視中と同じ）', () {
    final rec = record(
      [
        [('GoblinのBaz→GoblinのHPが、300回復。', 0x19, 1)],
        [('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 2)],
      ],
      [t0, t0.add(const Duration(seconds: 1))],
    );
    final log = RecordedLog()..addCsv(rec.csv, source: 'a.csv');
    expect(rec.live.summaries().firstWhere((s) => s.name == 'Goblin').heal, 300);
    expect(describe(log.summary.summaries()), describe(rec.live.summaries()));
  });

  test('戦闘の行は同じ行の事実を 1 行にまとめ、時刻なしの行は null', () {
    final log = RecordedLog()..addCsv(record(batches, times).csv, source: 'a.csv');
    expect(log.combatLines.map((l) => l.line.text), [
      'Aliceの攻撃→Goblinに、100ダメージ。',
      '→Goblinに、500ダメージ。',
      'Bobの攻撃→Goblinに、50ダメージ。',
      'Aliceの攻撃→Goblinに、ミス。',
      'CarolのBaz→AliceのHPが、300回復。',
      '→Orcに、200ダメージ。',
      'Orcの攻撃→Aliceに、40ダメージ。',
    ]);
    expect(log.combatLines.first.observedAt, isNull);
    // 時刻の間隔は elapsed（ミリ秒）で戻る。絶対時刻は time 列が秒単位のため 1 秒未満ずれうる。
    final first = log.combatLines.elementAt(2).observedAt!;
    final last = log.combatLines.last.observedAt!;
    expect(last.difference(first), const Duration(milliseconds: 3500));
    expect(t0.difference(first).inMilliseconds.abs(), lessThan(1000));
    expect(log.combatLines.first.line.mode, 0x14);
    expect(log.combatLines.first.line.lineNo, 1);
  });

  test('名前を隠した CSV も同じ集計になり、表記はそのまま読む', () {
    final rec = record(batches, times, mask: true);
    final log = RecordedLog()..addCsv(rec.csv, source: 'a.csv');
    expect(describe(log.summary.summaries()), describe(rec.live.summaries(), rec.masker!.display));
    expect(log.names, containsAll(['戦/侍 #1', 'PC #1', 'Goblin']));
    expect(log.names.where(isMaskedLabel), containsAll(['戦/侍 #1', 'PC #1']));
    expect(isMaskedLabel('Goblin'), isFalse);
  });

  test('引用符・カンマ・改行を含む本文と、BOM なし・LF 改行を読む', () {
    final rows = toRows([...CombatParser().add(logLine('Aliceの攻撃→Goblinに、1ダメージ。'))], session: 's2');
    final csv = toCsv([
      {...rows.single, 'text': 'a,"b"\r\nc'},
    ]);
    final log = RecordedLog()..addCsv(csv.substring(1).replaceAll('\r\n', '\n'), source: 'b.csv');
    expect(log.combatLines.single.line.text, 'a,"b"\nc');
    expect(log.summary.summaries().single.damage, 1);
  });

  test('複数のファイルを合算する', () {
    final csv = record(batches, times).csv;
    final log = RecordedLog()
      ..addCsv(csv, source: 'a.csv')
      ..addCsv(csv.replaceAll('s1,', 's2,'), source: 'b.csv');
    final one = RecordedLog()..addCsv(csv, source: 'a.csv');
    expect(log.eventCount, one.eventCount * 2);
    expect(log.summary.summaries().first.damage, one.summary.summaries().first.damage * 2);
  });

  test('このアプリの CSV でなければ読まず、集計も変えない', () {
    final log = RecordedLog();
    expect(
      () => log.addCsv('a,b\r\n1,2\r\n', source: 'x.csv'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('session'))),
    );
    final broken = record(batches, times).csv.replaceFirst(RegExp(r'\r\ns1,1,'), '\r\ns1,x,');
    expect(() => log.addCsv(broken, source: 'y.csv'), throwsFormatException);
    expect(() => log.addCsv('', source: 'z.csv'), throwsFormatException);
    expect(() => log.addCsv('${csvHeader()}"abc', source: 'q.csv'), throwsFormatException);
    expect(log.eventCount, 0);
    expect(log.sources, isEmpty);
  });
}
