import 'dart:convert';
import 'dart:io';

/// 敵の絞り込みに使う名前のまとまり（「ソーティのボス」など）。
class FilterSet {
  const FilterSet({required this.name, required this.enemies, required this.source});

  /// 画面に出す名前。
  final String name;

  /// 敵の名前。ログの表記と完全に一致したものだけを選ぶ。
  final List<String> enemies;

  /// 読んだファイルの名前。
  final String source;
}

/// フォルダの `*.json` を読んだ結果。[errors] は読めなかったファイルとその理由。
typedef FilterSetLoad = ({List<FilterSet> sets, List<({String file, String message})> errors});

/// JSON の文字列からセットを読む。1 ファイルに 1 つ（オブジェクト）か、複数（配列）を書ける。
///
/// ```json
/// {"name": "ソーティ ボス", "enemies": ["Ghatjot", "Leshonn"]}
/// ```
///
/// 書式が合わなければ [FormatException]。
List<FilterSet> parseFilterSets(String text, {required String source}) {
  // メモ帳は UTF-8 の先頭に BOM を付ける。
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    throw FormatException('JSON として読めません（${e.message}）');
  }
  final items = json is List ? json : [json];
  return [
    for (final (i, item) in items.indexed) _parseOne(item, source, items.length > 1 ? i : null),
  ];
}

FilterSet _parseOne(Object? item, String source, int? index) {
  final where = index == null ? '' : '${index + 1} 件目: ';
  if (item is! Map) throw FormatException('$where{"name": …, "enemies": […]} の形で書いてください');
  final name = item['name'];
  if (name is! String || name.trim().isEmpty) throw FormatException('${where}name がありません');
  final enemies = item['enemies'];
  if (enemies is! List || enemies.any((e) => e is! String)) {
    throw FormatException('${where}enemies は名前（文字列）の配列で書いてください');
  }
  final names = [
    for (final e in enemies.cast<String>())
      if (e.trim().isNotEmpty) e.trim(),
  ];
  if (names.isEmpty) throw FormatException('${where}enemies が空です');
  return FilterSet(name: name.trim(), enemies: names, source: source);
}

/// [dir] 直下の `*.json` をファイル名順に読む。壊れたファイルは [FilterSetLoad.errors] に入れ、残りは読む。
FilterSetLoad loadFilterSets(Directory dir) {
  final sets = <FilterSet>[];
  final errors = <({String file, String message})>[];
  final List<File> files;
  try {
    files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
  } on FileSystemException catch (e) {
    return (sets: sets, errors: [(file: dir.path, message: 'フォルダを読めません（${e.message}）')]);
  }
  for (final f in files) {
    final file = f.uri.pathSegments.last;
    try {
      sets.addAll(parseFilterSets(f.readAsStringSync(), source: file));
    } on FormatException catch (e) {
      errors.add((file: file, message: e.message));
    } on FileSystemException catch (e) {
      errors.add((file: file, message: '読めません（${e.message}）'));
    }
  }
  return (sets: sets, errors: errors);
}
