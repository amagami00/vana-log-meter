import 'dart:io';

import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

/// 架空の名前だけを使う。
List<int> l(int line, String text, {int msg = 0, int mode = 0x14, bool done = true}) => lineBytes((
  mode: mode,
  msg: msg == 0 ? line : msg,
  line: line,
  body: sjis(text),
), terminate: done);

void main() {
  late Directory dir;
  late LogSession s;
  var now = DateTime(2026, 11, 19, 12);

  void write(String name, List<List<int>> lines) =>
      File('${dir.path}/$name').writeAsBytesSync(logFile(lines));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vana_log_session_');
    s = LogSession(directory: dir, clock: () => now);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('skipExisting なら開始前の行は数えず、構えた WS の文脈は引き継ぐ', () {
    final t = LogSession(directory: dir, skipExisting: true, clock: () => now);
    write('1_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'), l(2, 'Aliceは、Fooの構え。')]);
    expect(t.poll(), isEmpty);
    expect(t.combatLines, isEmpty);
    write('1_0.log', [
      l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'),
      l(2, 'Aliceは、Fooの構え。'),
      l(3, 'Aliceは、Fooを実行。'),
      l(4, '→Goblinに、500ダメージ。', msg: 3),
    ]);
    final added = t.poll();
    expect(added.map((e) => (e.stat, e.damage)), [('ws', 500)]);
    expect(t.eventCount, 1);
    expect(t.roster.isAlly('Alice'), isTrue);
  });

  test('開始時の既存行は時刻が null、その後の行は検知時刻', () {
    write('1_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
    expect(s.poll().single.observedAt, isNull);
    write('1_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'), l(2, 'Aliceの攻撃→Goblinに、11ダメージ。')]);
    now = now.add(const Duration(seconds: 3));
    final added = s.poll();
    expect(added.single.damage, 11);
    expect(added.single.observedAt, now);
    expect(s.poll(), isEmpty);
    expect(s.eventCount, 2);
  });

  test('クリティカルの見出し行と矢印行が別の読み込みに分かれても 1 件', () {
    write('1_0.log', [l(1, 'Aliceの攻撃。クリティカル！', msg: 9)]);
    expect(s.poll(), isEmpty);
    write('1_0.log', [l(1, 'Aliceの攻撃。クリティカル！', msg: 9), l(2, '→Goblinに、99ダメージ。', msg: 9)]);
    final e = s.poll().single;
    expect(e.isCrit, isTrue);
    expect(e.actor, 'Alice');
  });

  test('書き込み途中の行は、完成した読み込みで 1 回だけ出る', () {
    write('1_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。', done: false)]);
    expect(s.poll(), isEmpty);
    write('1_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
    expect(s.poll(), hasLength(1));
    expect(s.poll(), isEmpty);
  });

  test('ファイルをまたぐ新規行を行番号順に処理する', () {
    // 1_1.log（行 50〜）が 1_0.log より前に列挙されても、見出し→矢印の順に処理される。
    write('1_1.log', [l(50, '→Goblinに、70ダメージ。', msg: 7)]);
    write('1_0.log', [l(49, 'Aliceの攻撃。クリティカル！', msg: 7)]);
    expect(s.poll().single.damage, 70);
  });

  test('対象外のウィンドウとファイルは読まない', () {
    write('2_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。')]);
    File('${dir.path}/memo.txt').writeAsStringSync('x');
    expect(s.poll(), isEmpty);
  });

  test('ゲームの再起動で行番号が戻り、同じ行番号に別の内容が書かれたら新しい行として読む', () {
    // 前のセッションの行が残るファイルを、次のセッションが同じ行番号で上書きする。
    write('1_7.log', [l(350, 'Aliceの攻撃→Goblinに、10ダメージ。'), l(351, 'Aliceの攻撃→Goblinに、11ダメージ。')]);
    expect(s.poll(), hasLength(2));
    write('1_7.log', [l(350, 'Bobの攻撃→Orcに、20ダメージ。')]);
    expect(s.poll().map((e) => (e.actor, e.damage)), [('Bob', 20)]);
    expect(s.poll(), isEmpty);
    expect(s.store.linesOf(1).map((x) => x.text), ['Bobの攻撃→Orcに、20ダメージ。']);
    write('1_7.log', [l(350, 'Bobの攻撃→Orcに、20ダメージ。'), l(351, 'Bobの攻撃→Orcに、21ダメージ。')]);
    expect(s.poll().map((e) => e.damage), [21]);
  });

  test('前回の起動で書かれ、まだ上書きされていないファイルは読まない', () {
    // 今回の起動は行 0 から 1_0.log に書いた。1_8.log は前日の起動の残り。
    write('1_8.log', [l(400, 'Bobの攻撃→Orcに、99ダメージ。', msg: 300)]);
    File('${dir.path}/1_8.log')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
    write('1_0.log', [l(0, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
    expect(s.poll().map((e) => e.damage), [10]);
    // 今回の起動が 1_8.log を上書きしたら読む。
    write('1_8.log', [l(400, 'Aliceの攻撃→Goblinに、40ダメージ。', msg: 900)]);
    expect(s.poll().map((e) => e.damage), [40]);
  });

  test('ウィンドウ 1+2 でも、前回の起動の残りは読まない', () {
    final m = LogSession(directory: dir, window: bothWindows, clock: () => now);
    write('2_7.log', [l(350, 'Bobの攻撃→Orcに、99ダメージ。', msg: 300)]);
    File('${dir.path}/2_7.log')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
    write('1_0.log', [l(0, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
    write('2_0.log', [l(0, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
    expect(m.poll().map((e) => e.damage), [10]);
  });

  // Windows では、書き込み直後のファイルの更新時刻が前回の上書き時のまま見えることがある。
  void writeWithOldTime(String name, List<List<int>> lines) {
    write(name, lines);
    File('${dir.path}/$name')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
  }

  test('監視中に書かれたファイルは、更新時刻が古く見えても読む', () {
    write('1_0.log', [l(0, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
    expect(s.poll().map((e) => e.damage), [10]);
    writeWithOldTime('1_1.log', [l(50, 'Aliceの攻撃→Goblinに、20ダメージ。', msg: 60)]);
    expect(s.poll().map((e) => e.damage), [20]);
  });

  test('ウィンドウ 1+2 でも、監視中に書かれたファイルは更新時刻が古く見えても読む', () {
    final m = LogSession(directory: dir, window: bothWindows, clock: () => now);
    write('1_0.log', [l(0, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
    write('2_0.log', [l(0, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
    expect(m.poll().map((e) => e.damage), [10]);
    writeWithOldTime('1_1.log', [l(50, 'Aliceの攻撃→Goblinに、20ダメージ。', msg: 60)]);
    expect(m.poll().map((e) => e.damage), [20]);
    writeWithOldTime('2_1.log', [
      l(50, 'Aliceの攻撃→Goblinに、20ダメージ。', msg: 60),
      l(51, 'Aliceの攻撃→Goblinに、30ダメージ。', msg: 61),
    ]);
    expect(m.poll().map((e) => e.damage), [30]);
  });

  test('ディレクトリがなくても例外を投げない', () {
    final gone = LogSession(directory: Directory('${dir.path}/none'));
    expect(gone.poll(), isEmpty);
  });

  test('戦闘の行だけを読んだ順に残す', () {
    write('1_0.log', [
      l(1, 'Aliceの攻撃→Goblinに、10ダメージ。'),
      l(2, 'こんにちは', mode: 0x05),
      l(3, 'Aliceの攻撃→Goblinに、11ダメージ。'),
    ]);
    s.poll();
    expect(s.combatLines.map((x) => x.line.lineNo), [1, 3]);
    expect(s.combatLines.first.observedAt, isNull);
  });

  group('ウィンドウ 1 と 2 をまとめて読む', () {
    late LogSession m;
    setUp(() => m = LogSession(directory: dir, window: bothWindows, clock: () => now));

    test('両方に出た同じメッセージは 1 回だけ数える（行番号はウィンドウごとに違う）', () {
      write('1_0.log', [
        l(101, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1),
        l(102, 'Aliceは、Fooを実行。', msg: 2),
        l(103, '→Goblinに、500ダメージ。', msg: 2),
      ]);
      write('2_0.log', [
        l(51, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1),
        l(52, 'Aliceは、Fooを実行。', msg: 2),
        l(53, '→Goblinに、500ダメージ。', msg: 2),
      ]);
      expect(m.poll().map((e) => e.damage), [10, 500]);
      expect(m.combatLines.map((x) => x.line.window), [1, 1, 1]);
    });

    test('片方にしか出ないメッセージも、メッセージの番号の順に並べて数える', () {
      write('1_0.log', [
        l(1, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1),
        l(2, 'Aliceの攻撃→Goblinに、30ダメージ。', msg: 3),
      ]);
      write('2_0.log', [l(1, 'Bobの攻撃→Goblinに、20ダメージ。', msg: 2)]);
      expect(m.poll().map((e) => e.damage), [10, 20, 30]);
    });

    test('同じメッセージ内で同じ本文が続いても、それぞれ数える', () {
      final lines = [
        l(1, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1),
        l(2, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1),
      ];
      write('1_0.log', lines);
      write('2_0.log', lines);
      expect(m.poll(), hasLength(2));
    });

    test('後から書き出されたウィンドウからは、まだ数えていない行だけを足す', () {
      write('1_0.log', [l(1, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1)]);
      expect(m.poll(), hasLength(1));
      write('2_0.log', [
        l(1, 'Aliceの攻撃→Goblinに、10ダメージ。', msg: 1),
        l(2, 'Bobの攻撃→Goblinに、20ダメージ。', msg: 2),
      ]);
      expect(m.poll().map((e) => e.actor), ['Bob']);
      expect(m.eventCount, 2);
    });

    test('CSV のファイル名は w12', () {
      final out = Directory('${dir.path}/out')..createSync();
      final r = CsvRecorder(directory: out, session: m, now: DateTime(2026, 11, 20, 9));
      expect(r.file.path, endsWith('vana-log-20261120-090000-w12-集計.csv'));
    });
  });
}
