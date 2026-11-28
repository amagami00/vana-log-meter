import 'roster.dart';

/// 画面に出すプレイヤー名をジョブ表記（「戦/侍 #1」）か連番（「PC #1」）に置き換える。
///
/// 安全側に倒し、敵と判定できなかった名前はすべて置き換える（殴らない味方は
/// 味方の名簿に入らないことがあるため）。番号は初めて見た順に付ける。
class NameMasker {
  NameMasker({Map<String, String> jobs = const {}}) : jobs = Map.of(jobs);

  /// 名前 → ジョブ表記（「戦/侍」など）。空なら連番。
  final Map<String, String> jobs;

  final Map<String, String> _labels = {};
  final Map<String, int> _counters = {};

  /// [names]（初めて見た順）のうち、[roster] で敵でない名前を登録する。
  void learnNames(Iterable<String> names, Roster roster) {
    for (final n in names) {
      if (n.isNotEmpty && !roster.isEnemy(n)) _label(n);
    }
  }

  /// 置き換える名前（登録済みのもの）。
  Iterable<String> get names => _labels.keys;

  /// 表示名。置き換えの対象でなければそのまま返す。
  String display(String name) => _labels[name] ?? name;

  String _label(String name) => _labels.putIfAbsent(name, () {
    _re = null;
    final job = jobs[name]?.trim();
    final key = (job == null || job.isEmpty) ? 'PC' : job;
    final n = _counters[key] = (_counters[key] ?? 0) + 1;
    return '$key #$n';
  });

  /// 本文中の名前を置き換える。長い名前を先に、英字の途中では置き換えない。
  String maskText(String text) {
    if (_labels.isEmpty) return text;
    final re = _re ??= () {
      final sorted = _labels.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      return RegExp('(?<![A-Za-z])(${sorted.map(RegExp.escape).join('|')})(?![A-Za-z])');
    }();
    return text.replaceAllMapped(re, (m) => _labels[m[1]]!);
  }

  RegExp? _re;
}
