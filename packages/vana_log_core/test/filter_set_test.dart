import 'dart:io';

import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

void main() {
  test('1 ファイルに 1 つのセットを読む', () {
    final sets = parseFilterSets(
      '{"name": " ソーティ ボス ", "enemies": ["Ghatjot", " Aita ", ""]}',
      source: 'sortie.json',
    );
    expect(sets, hasLength(1));
    expect(sets.single.name, 'ソーティ ボス');
    expect(sets.single.enemies, ['Ghatjot', 'Aita']);
    expect(sets.single.source, 'sortie.json');
  });

  test('配列なら複数のセットを読む', () {
    final sets = parseFilterSets(
      '[{"name": "A", "enemies": ["x"]}, {"name": "B", "enemies": ["y", "z"]}]',
      source: 'a.json',
    );
    expect([for (final s in sets) s.name], ['A', 'B']);
  });

  test('先頭の BOM を読み飛ばす', () {
    final sets = parseFilterSets('\uFEFF{"name": "A", "enemies": ["x"]}', source: 'a.json');
    expect(sets.single.enemies, ['x']);
  });

  test('書式が合わなければ FormatException', () {
    for (final text in [
      '{',
      '"A"',
      '{"enemies": ["x"]}',
      '{"name": "A"}',
      '{"name": "A", "enemies": [1]}',
      '{"name": "A", "enemies": []}',
    ]) {
      expect(() => parseFilterSets(text, source: 'a.json'), throwsFormatException, reason: text);
    }
  });

  test('フォルダの json をファイル名順に読み、壊れたファイルは理由を残す', () {
    final dir = Directory.systemTemp.createTempSync('vana_filter_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/b.json').writeAsStringSync('{"name": "B", "enemies": ["y"]}');
    File('${dir.path}/a.JSON').writeAsStringSync('{"name": "A", "enemies": ["x"]}');
    File('${dir.path}/c.json').writeAsStringSync('{');
    File('${dir.path}/memo.txt').writeAsStringSync('無視する');
    final r = loadFilterSets(dir);
    expect([for (final s in r.sets) s.name], ['A', 'B']);
    expect(r.errors.single.file, 'c.json');
  });

  test('サンプルのソーティのセットを読める', () {
    final f = File('../../filters/sortie.json');
    final set = parseFilterSets(f.readAsStringSync(), source: 'sortie.json').single;
    expect(set.enemies, hasLength(9));
    expect(set.enemies, containsAll(['Ghatjot', 'Aita', 'Aminon']));
  });
}
