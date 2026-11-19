import 'cp932_table.dart';

const int _replacement = 0xFFFD;

/// CP932（Windows の Shift_JIS）のバイト列を文字列に変換する。
///
/// 例外は投げない。変換できないバイトと、末尾で途中まで書かれた 2 バイト文字は
/// U+FFFD に置き換える（ゲームが書き込んでいる途中のファイルを読むため）。
String decodeCp932(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      out.writeCharCode(b);
      i++;
    } else if (b >= 0xA1 && b <= 0xDF) {
      // 半角カナ。
      out.writeCharCode(0xFF61 + (b - 0xA1));
      i++;
    } else if (isCp932LeadByte(b)) {
      if (i + 1 >= bytes.length) {
        out.writeCharCode(_replacement);
        i++;
        continue;
      }
      final t = bytes[i + 1];
      if (t < cp932TrailFirst || t > cp932TrailLast || t == 0x7F) {
        // 2 バイト目として不正。先行バイトだけを捨て、次のバイトから読み直す。
        out.writeCharCode(_replacement);
        i++;
        continue;
      }
      out.write(cp932DoubleByte[b]![t - cp932TrailFirst]);
      i += 2;
    } else {
      out.writeCharCode(_replacement);
      i++;
    }
  }
  return out.toString();
}

/// CP932 の 2 バイト文字の先行バイトかどうか。
bool isCp932LeadByte(int b) => (b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xFC);
