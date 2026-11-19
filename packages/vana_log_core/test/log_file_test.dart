import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

void main() {
  test('行を分け、フィールドと本文を取り出す', () {
    final bytes = logFile([
      lineBytes((mode: 0x14, msg: 0x10, line: 0x2A, body: sjis('Aliceの攻撃→Goblinに、12ダメージ。'))),
      lineBytes((mode: 0x20, msg: 0x11, line: 0x2B, body: sjis('abc'))),
    ]);
    final r = parseLogFile(bytes, window: 2, fileIndex: 3);
    expect(r.incomplete, 0);
    expect(r.malformed, 0);
    expect(r.lines, hasLength(2));
    final l = r.lines.first;
    expect(l.window, 2);
    expect(l.fileIndex, 3);
    expect(l.mode, 0x14);
    expect(l.messageId, 0x10);
    expect(l.lineNo, 0x2A);
    expect(l.isWrapped, isFalse);
    expect(l.text, 'Aliceの攻撃→Goblinに、12ダメージ。');
  });

  test('終端のない最後の行は書き込み途中として数える', () {
    final bytes = logFile([
      lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('ok'))),
      lineBytes((mode: 0x14, msg: 2, line: 2, body: sjis('half')), terminate: false),
    ]);
    final r = parseLogFile(bytes, window: 1, fileIndex: 0);
    expect(r.lines, hasLength(1));
    expect(r.incomplete, 1);
  });

  test('フィールドが 16 進でない行は形式不正として数える', () {
    final bytes = logFile([
      [...'zz,'.codeUnits, ...lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('x')))],
    ]);
    final r = parseLogFile(bytes, window: 1, fileIndex: 0);
    expect(r.lines, isEmpty);
    expect(r.malformed, 1);
  });

  test('ヘッダーに満たないファイルは空', () {
    final r = parseLogFile(logFile([]).sublist(0, 10), window: 1, fileIndex: 0);
    expect(r.lines, isEmpty);
  });

  test('制御コードを除き、定型句の括弧を置き換える', () {
    expect(decodeLogText([0x1E, 0x01, 0x41, 0x1F, 0x05, 0x42, 0x7F, 0x31]), 'AB');
    expect(decodeLogText([0xEF, 0x27, 0x41, 0xEF, 0x28]), '{A}');
  });

  test('2 バイト文字の 2 バイト目にある 0x7F・0x1F を制御コードと取り違えない', () {
    // 0x82 0x9F = 'ぁ'。直後の 0x1F 0x01 だけが制御コード。
    expect(decodeLogText([0x82, 0x9F, 0x1F, 0x01, 0x41]), 'ぁA');
  });

  test('ファイル名からウィンドウと番号を取り出す', () {
    expect(parseLogFileName('1_0.log'), (window: 1, fileIndex: 0));
    expect(parseLogFileName('2_19.log'), (window: 2, fileIndex: 19));
    expect(parseLogFileName('2_20.log'), isNull);
    expect(parseLogFileName('3_0.log'), isNull);
  });

  test('LogStore は同じ行番号を重複させず、行番号順に並べる', () {
    final store = LogStore();
    final a = logFile([
      lineBytes((mode: 0x14, msg: 1, line: 51, body: sjis('b'))),
      lineBytes((mode: 0x14, msg: 1, line: 50, body: sjis('a'))),
    ]);
    expect(store.ingest(a, window: 1, fileIndex: 1), hasLength(2));
    expect(store.ingest(a, window: 1, fileIndex: 1), isEmpty);
    expect(store.linesOf(1).map((l) => l.text), ['a', 'b']);
  });

  test('LogStore は上書きでファイルから消えた行を捨て、他のファイルの行は残す', () {
    final store = LogStore();
    List<int> l(int n) => lineBytes((mode: 0x14, msg: n, line: n, body: sjis('t$n')));
    store.ingest(logFile([l(1), l(2)]), window: 1, fileIndex: 0);
    store.ingest(logFile([l(3)]), window: 1, fileIndex: 1);
    expect(store.size, 3);
    // 1_0.log が新しい行で上書きされた。
    expect(store.ingest(logFile([l(4)]), window: 1, fileIndex: 0).map((x) => x.lineNo), [4]);
    expect(store.linesOf(1).map((x) => x.lineNo), [3, 4]);
    expect(store.ingest(logFile([l(4)]), window: 1, fileIndex: 0), isEmpty);
    expect(store.ingest(logFile([l(3)]), window: 1, fileIndex: 1), isEmpty);
  });

  test('LogStore は読み込みが途中で切れても（空・短い）、行を捨てて読み直さない', () {
    final store = LogStore();
    List<int> l(int n) => lineBytes((mode: 0x14, msg: n, line: n, body: sjis('t$n')));
    final full = logFile([l(1), l(2)]);
    expect(store.ingest(full, window: 1, fileIndex: 0), hasLength(2));
    expect(store.ingest(Uint8List(0), window: 1, fileIndex: 0), isEmpty);
    expect(store.ingest(logFile([l(1)]), window: 1, fileIndex: 0), isEmpty);
    expect(store.ingest(full, window: 1, fileIndex: 0), isEmpty);
  });
}
