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
