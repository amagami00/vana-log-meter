import 'combat.dart';
import 'roster.dart';

/// プレイヤー名をジョブ表記（「戦/侍 #1」）か連番（「PC #1」）に置き換える。
///
/// 安全側に倒し、敵と判定できなかった名前はすべて置き換える（殴らない味方は
/// 味方の名簿に入らないことがあるため）。番号は初めて見た順に付ける。
class NameMasker {
  NameMasker({Map<String, String> jobs = const {}}) : jobs = Map.of(jobs);

  /// 名前 → ジョブ表記（「戦/侍」など）。空なら連番。
  final Map<String, String> jobs;

  final Map<String, String> _labels = {};
  final Map<String, int> _counters = {};

  /// [roster] で敵でない名前を、[events] の登場順に登録する。
  void learn(Iterable<CombatEvent> events, Roster roster) {
    for (final e in events) {
      for (final n in [e.actor, e.target]) {
        if (n.isNotEmpty && !roster.isEnemy(n)) _label(n);
      }
    }
  }

  /// [names]（初めて見た順）のうち、[roster] で敵でない名前を登録する。
  void learnNames(Iterable<String> names, Roster roster) {
    for (final n in names) {
      if (n.isNotEmpty && !roster.isEnemy(n)) _label(n);
    }
  }

  /// 登録した名前のうち、後から [roster] で敵と分かったものを外す（以後は名前のまま出す）。
  /// 他の名前の番号は変えない。
  void forgetEnemies(Roster roster) {
    final before = _labels.length;
    _labels.removeWhere((n, _) => roster.isEnemy(n));
    if (_labels.length != before) _re = null;
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

  /// [toRows] の出力の名前を置き換えた新しい行を返す。
  List<Map<String, Object?>> maskRows(List<Map<String, Object?>> rows) => [
    for (final r in rows)
      {
        ...r,
        for (final c in const ['ally', 'enemy', 'actor_name', 'target_name'])
          if (r[c] is String) c: display(r[c]! as String),
        if (r['text'] is String) 'text': maskText(r['text']! as String),
      },
  ];
}
