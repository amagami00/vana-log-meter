import 'dart:typed_data';

import 'cp932.dart';

/// ログファイルの先頭にある行オフセット表の大きさ（uint16 LE × 50）。
const int headerSize = 100;

/// 1 ファイルあたりの最大行数。
const int linesPerFile = 50;

/// 1 つのウィンドウで順に上書きされるファイルの数（`1_0.log`〜`1_19.log`）。
const int filesPerWindow = 20;

const int _fieldCount = 21;
const int _unusedOffset = 0xFFFF;

/// ログファイルの 1 行。
class LogLine {
  LogLine({
    required this.window,
    required this.fileIndex,
    required this.fields,
    required this.text,
  });

  /// ログウィンドウの番号（ファイル名の先頭 `1_` / `2_`）。
  final int window;

  /// ファイル名の番号（0〜19）。
  final int fileIndex;

  /// 本文の前にある 16 進のフィールド 21 個（加工しない）。
  final List<String> fields;

  /// 制御コードを除いた本文。
  final String text;

  /// メッセージ種別（chat mode）。
  int get mode => int.parse(fields[0], radix: 16);

  /// 文字色。
  int get color => int.parse(fields[3], radix: 16);

  /// メッセージの番号。複数行に分かれた 1 つのメッセージ（「X の攻撃。クリティカル！」と
  /// 「→Y に、N ダメージ。」など）は同じ値になる。
  int get messageId => int.parse(fields[4], radix: 16);

  /// ウィンドウ内の行番号（連番）。並び順と重複の判定に使う。
  int get lineNo => int.parse(fields[5], radix: 16);

  /// 長いチャットが折り返された 2 行目以降なら true。
  bool get isWrapped => fields[20] != '00';

  @override
  String toString() => 'LogLine(w$window #$lineNo mode=${fields[0]} msg=${fields[4]} "$text")';
}

/// [parseLogFile] の結果。
class LogFileParseResult {
  LogFileParseResult(this.lines, {required this.incomplete, required this.malformed});

  final List<LogLine> lines;

  /// 終端の `\x00` がまだない行の数（ゲームが書き込んでいる途中）。
  final int incomplete;

  /// フィールドが足りないなど、形式が崩れていて読めなかった行の数。
  final int malformed;
}

/// ログファイル 1 つ分のバイト列を行に分ける。例外は投げない。
LogFileParseResult parseLogFile(Uint8List bytes, {required int window, required int fileIndex}) {
  if (bytes.length < headerSize) {
    return LogFileParseResult(const [], incomplete: 0, malformed: 0);
  }
  final header = ByteData.sublistView(bytes, 0, headerSize);
  final offsets = <int>[];
  for (var i = 0; i < linesPerFile; i++) {
    final o = header.getUint16(i * 2, Endian.little);
    if (o == _unusedOffset) break;
    offsets.add(o);
  }

  final dataLength = bytes.length - headerSize;
  final lines = <LogLine>[];
  var incomplete = 0;
  var malformed = 0;
  for (var i = 0; i < offsets.length; i++) {
    final start = offsets[i];
    var end = i + 1 < offsets.length ? offsets[i + 1] : dataLength;
    if (end > dataLength) end = dataLength;
    if (start >= end) {
      incomplete++;
      continue;
    }
    final raw = Uint8List.sublistView(bytes, headerSize + start, headerSize + end);
    final line = _parseLine(raw, window: window, fileIndex: fileIndex);
    switch (line) {
      case _Incomplete():
        incomplete++;
      case _Malformed():
        malformed++;
      case _Parsed(:final line):
        lines.add(line);
    }
  }
  return LogFileParseResult(lines, incomplete: incomplete, malformed: malformed);
}

sealed class _LineResult {}

class _Incomplete extends _LineResult {}

class _Malformed extends _LineResult {}

class _Parsed extends _LineResult {
  _Parsed(this.line);
  final LogLine line;
}

final _hex = RegExp(r'^[0-9a-fA-F]+$');

_LineResult _parseLine(Uint8List raw, {required int window, required int fileIndex}) {
  final fields = <String>[];
  var pos = 0;
  while (fields.length < _fieldCount) {
    final comma = raw.indexOf(0x2C, pos);
    if (comma < 0) {
      // 本文に届く前に途切れている。終端があれば崩れた行、なければ書き込み途中。
      return raw.contains(0x00) ? _Malformed() : _Incomplete();
    }
    final f = String.fromCharCodes(raw, pos, comma);
    if (!_hex.hasMatch(f)) return _Malformed();
    fields.add(f);
    pos = comma + 1;
  }
  final terminator = raw.indexOf(0x00, pos);
  if (terminator < 0) return _Incomplete();
  final text = decodeLogText(Uint8List.sublistView(raw, pos, terminator));
  return _Parsed(LogLine(window: window, fileIndex: fileIndex, fields: fields, text: text));
}

/// 本文のバイト列から FFXI の制御コードを除き、文字列にする。
///
/// - `\x1e?` / `\x1f?`: 文字色の指定。取り除く。
/// - `\x7f?`: 制御コード。取り除く。
/// - `\xef\x27` / `\xef\x28`: 定型句の括弧。`{` / `}` に置き換える。
///
/// `\xef` は CP932 の先行バイトと重なるため、変換の前にバイト列のまま処理する。
/// 2 バイト文字の 2 バイト目を制御コードと取り違えないよう、先頭から順に読む。
String decodeLogText(List<int> bytes) {
  final out = <int>[];
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1E || b == 0x1F || b == 0x7F) {
      i += 2;
    } else if (b == 0xEF && i + 1 < bytes.length && bytes[i + 1] == 0x27) {
      out.add(0x7B); // {
      i += 2;
    } else if (b == 0xEF && i + 1 < bytes.length && bytes[i + 1] == 0x28) {
      out.add(0x7D); // }
      i += 2;
    } else if (isCp932LeadByte(b) && i + 1 < bytes.length) {
      out
        ..add(b)
        ..add(bytes[i + 1]);
      i += 2;
    } else {
      out.add(b);
      i++;
    }
  }
  return decodeCp932(out);
}
