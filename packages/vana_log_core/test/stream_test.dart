import 'dart:io';

import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

/// 架空の名前だけを使う。
List<int> l(int line, String text, {int mode = 0x14}) =>
    lineBytes((mode: mode, msg: line, line: line, body: sjis(text)));

void main() {
  late Directory dir;
  late Directory out;
  var now = DateTime(2026, 11, 19, 12);

  void write(int file, List<List<int>> lines) =>
      File('${dir.path}/1_$file.log').writeAsBytesSync(logFile(lines));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vana_log_stream_');
    out = Directory('${dir.path}/out');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('読み込みのたびに追記し、見出しは 1 回だけ。名前を隠すと味方の名前が残らない', () {
    final s = LogSession(directory: dir, clock: () => now);
    final r = CsvRecorder(directory: out, session: s, masker: NameMasker(), now: now);
    write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
    r.add(s.poll());
    write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'), l(2, 'Bobの攻撃→Goblinに、20ダメージ。', mode: 0x19)]);
    now = now.add(const Duration(seconds: 2));
    r.add(s.poll());
    r.add(s.poll()); // 新しい行がなければ何も書かない
    final lines = r.file.readAsStringSync().split('\r\n')..removeLast();
    expect(lines, hasLength(3));
    expect(r.file.readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF]);
    expect(lines.where((x) => x.contains('session,')), hasLength(1));
    expect(r.written, 2);
    final text = r.file.readAsStringSync();
    expect(text, isNot(contains('Alice')));
    expect(text, isNot(contains('Bob')));
    expect(text, contains('PC #1'));
    expect(text, contains('Goblin'));
  });

  test('書けなかった行は残し、次に書けたときにまとめて書く', () {
    final s = LogSession(directory: dir, clock: () => now);
    // 出力先の場所にファイルがあり、フォルダを作れない。
    File(out.path).writeAsStringSync('x');
    final r = CsvRecorder(directory: out, session: s, now: now);
    write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
    r.add(s.poll());
    expect(r.error, isNotNull);
    expect(r.pending, 1);
    File(out.path).deleteSync();
    r.add(const []);
    expect(r.error, isNull);
    expect(r.pending, 0);
    expect(r.written, 1);
    expect(r.file.readAsStringSync(), contains('10'));
  });

  test('集計表の与ダメージは、書き出した offense 行のダメージの合計と一致する', () {
    final s = LogSession(directory: dir, clock: () => now);
    final r = CsvRecorder(directory: out, session: s, now: now);
    write(0, [
      l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'),
      l(2, 'Goblinの攻撃→Aliceに、5ダメージ。', mode: 0x20),
      l(3, 'Bobの攻撃→Orcに、7ダメージ。', mode: 0x19),
    ]);
    r.add(s.poll());
    write(1, [l(50, 'Aliceの攻撃→Orcに、30ダメージ。')]);
    now = now.add(const Duration(seconds: 1));
    r.add(s.poll());
    final rows = r.file.readAsStringSync().split('\r\n').skip(1).where((x) => x.isNotEmpty);
    final cols = exportColumns;
    var sum = 0;
    for (final row in rows) {
      final c = row.split(',');
      if (c[cols.indexOf('side')] == 'offense') sum += int.parse(c[cols.indexOf('damage')]);
    }
    final total = s.summary.summaries().fold<int>(0, (a, x) => a + x.damage);
    expect(total, sum);
    expect(total, 47);
    expect(s.summary.summaries(enemies: ['Orc']).map((x) => (x.name, x.damage)), [
      ('Alice', 30),
      ('Bob', 7),
    ]);
    expect(s.summary.enemies().first.name, 'Orc');
  });

  test('名前を隠すとき、後から敵と分かった名前はその後の行で名前のまま出す', () {
    final s = LogSession(directory: dir, clock: () => now);
    final r = CsvRecorder(directory: out, session: s, masker: NameMasker(), now: now);
    // 魔法だけでは Orc が敵か分からず、隠す側に倒す。
    List<int> m(int line, String text) =>
        lineBytes((mode: 0x19, msg: 2, line: line, body: sjis(text)));
    final first = [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'), m(2, 'BobのBarが発動。'), m(3, '→Orcに、50ダメージ。')];
    write(0, first);
    r.add(s.poll());
    expect(r.file.readAsStringSync(), isNot(contains('Orc')));
    write(0, [...first, l(4, 'Aliceの攻撃→Orcに、20ダメージ。')]);
    r.add(s.poll());
    final last = r.file.readAsStringSync().trim().split('\r\n').last;
    expect(last, contains('Orc'));
    expect(last, isNot(contains('Alice')));
  });

  group('戦闘の行そのものを書く', () {
    List<List<String>> rawRows(CsvRecorder r) => [
      for (final x in r.linesFile.readAsStringSync().split('\r\n').skip(1))
        if (x.isNotEmpty) x.split('\t'),
    ];
    final textAt = rawLogColumns.indexOf('text');

    test('1+2 は重複を除いて戦闘の行だけを書き、名前を隠す設定でも名前のまま', () {
      now = DateTime(2026, 11, 19, 12);
      final s = LogSession(directory: dir, window: bothWindows, clock: () => now);
      final r = CsvRecorder(directory: out, session: s, masker: NameMasker(), now: now);
      List<int> m(int line, int msg, String text, {int mode = 0x14}) =>
          lineBytes((mode: mode, msg: msg, line: line, body: sjis(text)));
      File('${dir.path}/1_0.log').writeAsBytesSync(
        logFile([m(1, 1, 'Aliceの攻撃→Goblinに、10ダメージ。'), m(2, 2, 'こんにちは', mode: 0x05)]),
      );
      File('${dir.path}/2_0.log').writeAsBytesSync(
        logFile([m(7, 1, 'Aliceの攻撃→Goblinに、10ダメージ。'), m(8, 3, 'Bobの攻撃→Goblinに、20ダメージ。')]),
      );
      r.add(s.poll(), lines: s.lastCombatLines);
      now = now.add(const Duration(seconds: 1));
      r.add(s.poll(), lines: s.lastCombatLines); // 新しい行がなければ何も書かない
      expect(r.linesFile.path, endsWith('vanalog-20261119-120000-raw.tsv'));
      expect(r.linesFile.readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF]);
      final rows = rawRows(r);
      expect(rows.map((c) => c[textAt]), ['Aliceの攻撃→Goblinに、10ダメージ。', 'Bobの攻撃→Goblinに、20ダメージ。']);
      expect(rows.map((c) => c.length).toSet(), {rawLogColumns.length});
      int col(String name) => rawLogColumns.indexOf(name);
      expect(rows.map((c) => (c[col('log_window')], c[col('log_line')], c[col('msg')])), [
        ('1', '1', '1'),
        ('2', '8', '3'),
      ]);
      // CSV の log_window・log_line と同じ値で突き合わせられる。
      final csv = r.file.readAsStringSync().split('\r\n').skip(1).where((x) => x.isNotEmpty);
      final w = exportColumns.indexOf('log_window'), ln = exportColumns.indexOf('log_line');
      expect(csv.map((x) => (x.split(',')[w], x.split(',')[ln])), [('1', '1'), ('2', '8')]);
      expect(rows.first.first, isEmpty, reason: '開始前から残っていた行は時刻が空欄');
      expect(r.linesWritten, 2);
      expect(r.file.readAsStringSync(), isNot(contains('Alice')));
    });

    test('監視中に読んだ行は検知時刻を付けて追記する', () {
      final s = LogSession(directory: dir, clock: () => now);
      final r = CsvRecorder(directory: out, session: s, now: now);
      write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
      r.add(s.poll(), lines: s.lastCombatLines);
      write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'), l(2, 'Aliceの攻撃→Goblinに、11ダメージ。')]);
      now = DateTime(2026, 11, 19, 12, 0, 5, 42);
      r.add(s.poll(), lines: s.lastCombatLines);
      final rows = rawRows(r);
      expect(rows, hasLength(2));
      expect(rows.last.first, '2026-11-19 12:00:05.042');
      expect(
        r.linesFile.readAsStringSync().split('\r\n').where((x) => x.contains('\ttext')),
        hasLength(1),
      );
    });

    test('skipExisting の 1 回目は書かない', () {
      final s = LogSession(directory: dir, skipExisting: true, clock: () => now);
      write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
      s.poll();
      expect(s.lastCombatLines, isEmpty);
    });

    test('書けなかった行は残し、次に書けたときにまとめて書く', () {
      final s = LogSession(directory: dir, clock: () => now);
      File(out.path).writeAsStringSync('x');
      final r = CsvRecorder(directory: out, session: s, now: now);
      write(0, [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
      r.add(s.poll(), lines: s.lastCombatLines);
      expect(r.error, isNotNull);
      expect(r.pending, 2); // CSV 1 行 + 生ログ 1 行
      File(out.path).deleteSync();
      r.add(const []);
      expect(r.error, isNull);
      expect(r.pending, 0);
      expect(r.linesWritten, 1);
    });
  });

  test('長時間の記録でも保持する行は上限を超えない', () {
    final s = LogSession(directory: dir, clock: () => now);
    const files = 400; // 2 万行（ファイルの一巡 20 回分）
    var line = 0;
    var events = 0;
    for (var f = 0; f < files; f++) {
      write(f % filesPerWindow, [
        for (var i = 0; i < linesPerFile; i++) l(++line, 'Aliceの攻撃→Goblinに、${line % 997}ダメージ。'),
      ]);
      now = now.add(const Duration(milliseconds: 500));
      events += s.poll().length;
      expect(s.store.size, lessThanOrEqualTo(filesPerWindow * linesPerFile));
      expect(s.combatLines.length, lessThanOrEqualTo(LogSession.maxCombatLines));
    }
    expect(line, 20000);
    expect(events, line);
    expect(s.eventCount, line);
    expect(s.names, {'Alice', 'Goblin'});
    expect(s.summary.summaries().single.meleeHits, line);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
