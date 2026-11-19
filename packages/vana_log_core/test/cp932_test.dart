import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

void main() {
  test('ASCII・半角カナ・全角', () {
    expect(decodeCp932([0x41, 0xB1, 0x82, 0xA0]), 'Aｱあ');
  });

  test('NEC 特殊文字・NEC 選定 IBM 拡張・IBM 拡張', () {
    expect(decodeCp932([0x87, 0x40]), '①');
    expect(decodeCp932([0x87, 0x57]), 'Ⅳ');
    expect(decodeCp932([0x87, 0x8A]), '㈱');
    expect(decodeCp932([0xED, 0x40]), '纊');
    expect(decodeCp932([0xFA, 0x40]), 'ⅰ');
  });

  test('末尾で途切れた 2 バイト文字は U+FFFD にし、例外を投げない', () {
    expect(decodeCp932([0x41, 0x82]), 'A�');
  });

  test('不正な 2 バイト目は先行バイトだけを捨てて読み直す', () {
    expect(decodeCp932([0x82, 0x20, 0x41]), '� A');
  });

  test('先行バイトになれないバイトは U+FFFD', () {
    expect(decodeCp932([0x80, 0xA0, 0xFD]), '���');
  });
}
