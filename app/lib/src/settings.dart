import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 画面の設定。端末内（shared_preferences）にだけ保存する。
class Settings {
  Settings(this._prefs);

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String? get inputDir => _prefs.getString('inputDir');
  set inputDir(String? v) => _set('inputDir', v);

  String? get outputDir => _prefs.getString('outputDir');
  set outputDir(String? v) => _set('outputDir', v);

  /// 開始したとき、フォルダに残っている過去のログも集計に入れる。
  bool get includePast => _prefs.getBool('includePast') ?? true;
  set includePast(bool v) => _prefs.setBool('includePast', v);

  bool get anonymize => _prefs.getBool('anonymize') ?? false;
  set anonymize(bool v) => _prefs.setBool('anonymize', v);

  /// 監視中に取り出した事実を、出力先の CSV に追記する。
  bool get exportCsv => _prefs.getBool('exportCsv') ?? true;
  set exportCsv(bool v) => _prefs.setBool('exportCsv', v);

  /// 名前 → ジョブ表記（「戦/侍」など）。
  Map<String, String> get jobs {
    final s = _prefs.getString('jobs');
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    } on Object {
      return {};
    }
  }

  set jobs(Map<String, String> v) => _prefs.setString(
    'jobs',
    jsonEncode({
      for (final e in v.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    }),
  );

  void _set(String key, String? v) => v == null ? _prefs.remove(key) : _prefs.setString(key, v);
}
