import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

List<CombatEvent> feed(List<(String, int, int)> lines) {
  final p = CombatParser();
  var n = 0;
  return [
    for (final (text, mode, msg) in lines) ...p.add(logLine(text, mode: mode, msg: msg, line: ++n)),
  ];
}

void main() {
  final events = feed([
    ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 1),
    ('Aliceの攻撃→Goblinに、ミス。', 0x14, 2),
    ('Aliceの攻撃。クリティカル！', 0x14, 3),
    ('→Goblinに、200ダメージ。', 0x14, 3),
    ('追加ダメージ→Goblinに、30ダメージ。', 0x14, 4),
    ('Aliceは、Fooの構え。', 0x14, 5),
    ('Aliceは、Fooを実行。', 0x14, 6),
    ('→Goblinに、1000ダメージ。', 0x14, 6),
    ('技連携・光→Goblinに、500ダメージ。', 0x14, 7),
    ('Bobの攻撃→Goblinに、50ダメージ。', 0x19, 8),
    ('CarolのBaz→AliceのHPが、300回復。', 0x19, 9),
    ('Goblinの攻撃→Aliceに、40ダメージ。', 0x20, 10),
  ]);
  final roster = Roster()..addAll(events);

  test('味方ごとの集計', () {
    final s = summarize(events, roster);
    expect(s.map((x) => x.name), ['Alice', 'Bob', 'Carol']);
    final a = s.first;
    expect(a.damage, 100 + 200 + 30 + 1000 + 500);
    expect(a.meleeHits, 2);
    expect(a.meleeMisses, 1);
    expect(a.meleeCrits, 1);
    expect(a.accuracy, closeTo(2 / 3, 1e-9));
    expect(a.wsCount, 1);
    expect(a.wsMax, 1000);
    expect(a.addDamage, 30);
    expect(a.scDamage, 500);
    expect(s.last.heal, 300);
  });

  test('遠隔・WS のミスと WS 別の集計。敵で絞っても同じ値になる', () {
    final ev = feed([
      ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 1),
      ('Aliceの攻撃→Goblinに、140ダメージ。', 0x14, 2),
      ('Aliceの遠隔攻撃→Goblinに、250ダメージ。', 0x14, 3),
      ('Aliceの遠隔攻撃→Goblinに、ミス。', 0x14, 4),
      ('Aliceは、Fooの構え。', 0x14, 5),
      ('Aliceは、Fooを実行。', 0x14, 6),
      ('→Goblinに、1000ダメージ。', 0x14, 6),
      ('Aliceは、Fooの構え。', 0x14, 7),
      ('Aliceは、Fooを実行。', 0x14, 8),
      ('→Goblinに、ミス。', 0x14, 8),
      ('Aliceは、Barの構え。', 0x14, 9),
      ('Aliceは、Barを実行。', 0x14, 10),
      ('→Goblinに、2000ダメージ。', 0x14, 10),
    ]);
    final a = SummaryAccumulator()..add(ev, Roster()..addAll(ev));
    for (final x in [
      a.summaries().single,
      a.summaries(enemies: ['Goblin']).single,
    ]) {
      expect(x.meleeMax, 140);
      expect(x.meleeAverage, 120);
      expect((x.rangedHits, x.rangedMisses, x.rangedDamage, x.rangedMax), (1, 1, 250, 250));
      expect(x.rangedAccuracy, 0.5);
      expect(x.accuracy, 1);
      expect((x.wsCount, x.wsMisses, x.wsDamage), (2, 1, 3000));
      expect(x.wsAccuracy, closeTo(2 / 3, 1e-9));
      final foo = x.wsByName['Foo']!;
      expect((foo.count, foo.misses, foo.damage, foo.max), (1, 1, 1000, 1000));
      expect(foo.accuracy, 0.5);
      expect(x.wsByName['Bar']!.average, 2000);
      expect(x.otherDamage, 0);
    }
  });

  test('敵で絞り込む', () {
    final ev = feed([
      ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 1),
      ('Aliceの攻撃→Orcに、70ダメージ。', 0x14, 2),
      ('Bobの攻撃→Goblinに、50ダメージ。', 0x19, 3),
      ('Orcの攻撃→Bobに、30ダメージ。', 0x20, 4),
    ]);
    final r = Roster()..addAll(ev);
    expect(ev.map(r.enemyOf), ['Goblin', 'Orc', 'Goblin', 'Orc']);
    expect(enemiesByRecent(ev, r), [(name: 'Orc', damage: 70), (name: 'Goblin', damage: 150)]);
    final s = summarize(ev.where((e) => r.enemyOf(e) == 'Goblin'), r);
    expect({for (final x in s) x.name: x.damage}, {'Alice': 100, 'Bob': 50});
  });

  test('複数の敵と複数の味方で絞り込む。戦闘時間は同時に戦った分を重ねない', () {
    final ev = feed([
      ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 1),
      ('Aliceの攻撃→Orcに、70ダメージ。', 0x14, 2),
      ('Bobの攻撃→Goblinに、50ダメージ。', 0x19, 3),
      ('Bobの攻撃→Koboldに、20ダメージ。', 0x19, 4),
      ('Carolの攻撃→Orcに、10ダメージ。', 0x19, 5),
      ('Aliceの攻撃。クリティカル！', 0x14, 6),
      ('→Koboldに、999ダメージ。', 0x14, 6),
    ]);
    final t0 = DateTime(2026, 11, 19, 12);
    // Goblin と Orc は 0〜4 秒に入り混じって戦い、Kobold は 60 秒後に別の戦闘。
    for (final (i, sec) in [(0, 0), (1, 2), (2, 4), (3, 60), (4, 3)]) {
      ev[i].observedAt = t0.add(Duration(seconds: sec));
    }
    final a = SummaryAccumulator()..add(ev, Roster()..addAll(ev));
    final s = a.summaries(enemies: ['Goblin', 'Orc']);
    expect({for (final x in s) x.name: x.damage}, {'Alice': 170, 'Bob': 50, 'Carol': 10});
    expect(a.timeOf(enemies: ['Goblin', 'Orc']), const Duration(seconds: 5));
    expect(a.timeOf(enemies: ['Goblin']), const Duration(seconds: 5));
    expect(a.timeOf(enemies: ['Goblin', 'Kobold']), const Duration(seconds: 6));
    expect(s.first.dps, 170 / 5);
    expect(a.summaries(enemies: ['Goblin', 'Orc'], names: ['Bob', 'Carol']).map((x) => x.name), [
      'Bob',
      'Carol',
    ]);
    expect(a.summaries(enemies: ['Nobody']), isEmpty);
    expect(a.summaries(names: ['Alice']).single.damage, a.summaries().first.damage);
  });

  test('魔法とマジックバーストを分けて数える', () {
    final ev = feed([
      ('Bobの攻撃→Goblinに、50ダメージ。', 0x19, 1),
      ('BobのBarが発動。', 0x19, 2),
      ('→Goblinに、300ダメージ。', 0x19, 2),
      ('BobのBarが発動。', 0x19, 3),
      ('→マジックバースト！Goblinに、800ダメージ。', 0x19, 3),
      ('BobのBarが発動。', 0x19, 4),
      ('→マジックバースト！Goblinに、900ダメージ。', 0x19, 4),
    ]);
    final b = summarize(ev, Roster()..addAll(ev)).single;
    expect(b.spellDamage, 300);
    expect(b.mbCount, 2);
    expect(b.mbDamage, 1700);
    expect(b.mbMax, 900);
    expect(b.damage, 50 + 300 + 1700);
  });

  test('DPS は時刻の分かる事実だけで、長い空白を除いた戦闘時間で割る', () {
    final ev = feed([
      ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 1),
      ('Aliceの攻撃→Goblinに、300ダメージ。', 0x14, 2),
      ('Aliceの攻撃→Goblinに、200ダメージ。', 0x14, 3),
      ('Aliceの攻撃→Orcに、400ダメージ。', 0x14, 4),
    ]);
    final t0 = DateTime(2026, 11, 19, 12);
    ev[1].observedAt = t0;
    ev[2].observedAt = t0.add(const Duration(seconds: 4));
    ev[3].observedAt = t0.add(const Duration(seconds: 64)); // 60 秒の空白は数えない
    final r = Roster()..addAll(ev);
    expect(combatTime(ev, r), const Duration(seconds: 6));
    final a = summarize(ev, r).single;
    expect(a.damage, 1000);
    expect(a.timedDamage, 900);
    expect(a.dps, 150);
    expect(summarize(ev.take(1), r).single.dps, isNull);
  });

  test('ジョブ表記と連番で置き換え、敵の名前は残す', () {
    final m = NameMasker(jobs: {'Bob': '暗/侍'})..learn(events, roster);
    expect(m.display('Alice'), 'PC #1');
    expect(m.display('Bob'), '暗/侍 #1');
    expect(m.display('Carol'), 'PC #2');
    expect(m.display('Goblin'), 'Goblin');
  });

  test('書き出す行に元の名前が残らない', () {
    final m = NameMasker()..learn(events, roster);
    final rows = m.maskRows(toRows(events, session: 's', roster: roster));
    final out = toCsv(rows);
    for (final n in ['Alice', 'Bob', 'Carol']) {
      expect(out.contains(n), isFalse, reason: n);
    }
    expect(out, contains('Goblin'));
  });

  test('本文の置き換えは英字の途中を変えない', () {
    final m = NameMasker()..learn(feed([('Alの攻撃→Goblinに、1ダメージ。', 0x14, 1)]), roster);
    expect(m.maskText('Alの攻撃→Alexに'), 'PC #1の攻撃→Alexに');
  });

  test('集計表をタブ区切りにする', () {
    final tsv = summaryToTsv(summarize(events, roster), display: (n) => n == 'Alice' ? 'PC #1' : n);
    final rows = tsv.trimRight().split('\n').map((r) => r.split('\t')).toList();
    expect(rows.first, summaryColumns);
    expect(rows.length, 4);
    expect(rows[1].length, summaryColumns.length);
    expect(rows[1].take(3), ['PC #1', '1830', '97.3%']);
    expect(rows[1][3], ''); // 時刻がないので DPS は空欄
    expect(rows[1][5], '66.7%');
    expect(tsv, isNot(contains('Alice')));
  });
}
