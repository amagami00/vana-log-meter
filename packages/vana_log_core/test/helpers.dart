import 'dart:convert';
import 'dart:typed_data';

import 'package:vana_log_core/src/cp932_table.dart';
import 'package:vana_log_core/vana_log_core.dart';

/// テスト用の 1 行。名前はすべて架空。
typedef Spec = ({int mode, int msg, int line, List<int> body});

/// 本文を CP932 のバイト列にする（テストでは ASCII と、表から引いた文字だけを使う）。
List<int> sjis(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
      continue;
    }
    out.addAll(_reverse[r] ?? (throw ArgumentError('not in table: $s')));
  }
  return out;
}

final Map<int, List<int>> _reverse = () {
  final m = <int, List<int>>{};
  cp932DoubleByte.forEach((lead, row) {
    for (var i = 0; i < row.length; i++) {
      final c = row.codeUnitAt(i);
      if (c != 0xFFFD) m.putIfAbsent(c, () => [lead, 0x40 + i]);
    }
  });
  return m;
}();

/// 1 行分のバイト列（21 フィールド + 本文 + 終端）。
List<int> lineBytes(Spec s, {bool terminate = true}) {
  String h(int v, int w) => v.toRadixString(16).padLeft(w, '0');
  final fields = [
    h(s.mode, 2),
    '00',
    '00',
    '01',
    h(s.msg, 8),
    h(s.line, 8),
    for (var i = 0; i < 14; i++) '00',
    '00',
  ];
  return [...ascii.encode('${fields.join(',')},'), ...s.body, if (terminate) 0];
}

/// ログファイル 1 つ分のバイト列（先頭 100 バイトの行オフセット表付き）。
Uint8List logFile(List<List<int>> lines) {
  final header = ByteData(headerSize);
  for (var i = 0; i < linesPerFile; i++) {
    header.setUint16(i * 2, 0xFFFF, Endian.little);
  }
  final data = <int>[];
  for (var i = 0; i < lines.length; i++) {
    header.setUint16(i * 2, data.length, Endian.little);
    data.addAll(lines[i]);
  }
  return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
}

/// 本文の文字列から LogLine を作る。
LogLine logLine(String text, {int mode = 0x14, int msg = 1, int line = 1}) {
  final r = parseLogFile(
    logFile([lineBytes((mode: mode, msg: msg, line: line, body: sjis(text)))]),
    window: 1,
    fileIndex: 0,
  );
  return r.lines.single;
}
