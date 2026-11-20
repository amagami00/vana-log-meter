import 'combat.dart';
import 'roster.dart';

/// WS 1 種類分の集計。
class WsSummary {
  WsSummary(this.name);

  final String name;

  /// 命中した回数（最初の対象に当たった回数）。
  int count = 0;
  int misses = 0;
  int damage = 0;
  int max = 0;

  double? get average => count == 0 ? null : damage / count;
  double? get accuracy => count + misses == 0 ? null : count / (count + misses);

  void _addFrom(WsSummary o) {
    count += o.count;
    misses += o.misses;
    damage += o.damage;
    if (o.max > max) max = o.max;
  }
}

/// 味方 1 人分の集計（与ダメージは味方→敵の行動だけ、回復は敵でない行動者の分を数える）。
class ActorSummary {
  ActorSummary(this.name);

  final String name;
  int damage = 0;

  int meleeHits = 0;
  int meleeMisses = 0;
  int meleeCrits = 0;
  int meleeDamage = 0;
  int meleeMax = 0;

  int rangedHits = 0;
  int rangedMisses = 0;
  int rangedCrits = 0;
  int rangedDamage = 0;
  int rangedMax = 0;

  /// 命中した WS の回数（最初の対象に当たった回数）。
  int wsCount = 0;

  /// 最初の対象に外れた WS の回数。
  int wsMisses = 0;
  int wsDamage = 0;
  int wsMax = 0;

  /// WS の種類ごとの集計（キーは WS の名前）。
  final Map<String, WsSummary> wsByName = {};

  /// 精霊魔法などのダメージ（マジックバーストを除く）。
  int spellDamage = 0;

  /// マジックバーストした回数（対象ごとに 1 回）・合計・最大。
  int mbCount = 0;
  int mbDamage = 0;
  int mbMax = 0;

  int addDamage = 0;
  int scDamage = 0;
  int heal = 0;

  /// 通常攻撃の命中率（0〜1）。試行がなければ null。
  double? get accuracy {
    final n = meleeHits + meleeMisses;
    return n == 0 ? null : meleeHits / n;
  }

  /// 命中した通常攻撃のうちクリティカルの割合（0〜1）。
  double? get critRate => meleeHits == 0 ? null : meleeCrits / meleeHits;

  double? get wsAverage => wsCount == 0 ? null : wsDamage / wsCount;

  /// WS の命中率（最初の対象に当たった割合、0〜1）。
  double? get wsAccuracy => wsCount + wsMisses == 0 ? null : wsCount / (wsCount + wsMisses);

  double? get meleeAverage => meleeHits == 0 ? null : meleeDamage / meleeHits;

  double? get rangedAccuracy {
    final n = rangedHits + rangedMisses;
    return n == 0 ? null : rangedHits / n;
  }

  double? get rangedCritRate => rangedHits == 0 ? null : rangedCrits / rangedHits;
  double? get rangedAverage => rangedHits == 0 ? null : rangedDamage / rangedHits;

  /// 内訳に分けられない与ダメージ（構えを読めなかった WS・ダメージを与えるアビリティなど）。
  int get otherDamage =>
      damage -
      meleeDamage -
      rangedDamage -
      wsDamage -
      spellDamage -
      mbDamage -
      addDamage -
      scDamage;

  /// 時刻の分かる事実（開始後に読んだ行）の与ダメージ。
  int timedDamage = 0;

  /// 戦闘時間 1 秒あたりの与ダメージ。時刻の分かる事実がなければ null。
  double? dps;

  WsSummary _ws(String? name) {
    final n = name ?? '';
    return wsByName.putIfAbsent(n, () => WsSummary(n));
  }

  void _addFrom(ActorSummary o) {
    damage += o.damage;
    meleeHits += o.meleeHits;
    meleeMisses += o.meleeMisses;
    meleeCrits += o.meleeCrits;
    meleeDamage += o.meleeDamage;
    if (o.meleeMax > meleeMax) meleeMax = o.meleeMax;
    rangedHits += o.rangedHits;
    rangedMisses += o.rangedMisses;
    rangedCrits += o.rangedCrits;
    rangedDamage += o.rangedDamage;
    if (o.rangedMax > rangedMax) rangedMax = o.rangedMax;
    wsCount += o.wsCount;
    wsMisses += o.wsMisses;
    wsDamage += o.wsDamage;
    if (o.wsMax > wsMax) wsMax = o.wsMax;
    for (final w in o.wsByName.values) {
      wsByName.putIfAbsent(w.name, () => WsSummary(w.name))._addFrom(w);
    }
    spellDamage += o.spellDamage;
    mbCount += o.mbCount;
    mbDamage += o.mbDamage;
    if (o.mbMax > mbMax) mbMax = o.mbMax;
    addDamage += o.addDamage;
    scDamage += o.scDamage;
    heal += o.heal;
    timedDamage += o.timedDamage;
  }
}

/// 戦闘時間。時刻の分かる敵との事実だけを使い、[maxGap] より長い空白（戦闘の合間）は数えない。
/// 時刻は 1 秒ごとの読み直しで付くため、ひと続きの戦闘ごとに 1 秒を足す。
Duration combatTime(
  Iterable<CombatEvent> events,
  Roster roster, {
  Duration maxGap = const Duration(seconds: 10),
}) {
  final times = [
    for (final e in events)
      if (e.observedAt != null && roster.enemyOf(e) != null) e.observedAt!,
  ]..sort();
  if (times.isEmpty) return Duration.zero;
  var total = const Duration(seconds: 1);
  for (var i = 1; i < times.length; i++) {
    final gap = times[i].difference(times[i - 1]);
    total += gap <= maxGap ? gap : const Duration(seconds: 1);
  }
  return total;
}

/// 事実を受け取るたびに集計を積み上げる（事実そのものは保持しない）。
///
/// 敵味方の判定は、事実を受け取った時点の [Roster] で行う。後から判定が変わっても
/// 集計し直さない（長時間の記録でメモリを使い続けないため）。
class SummaryAccumulator {
  SummaryAccumulator({this.maxGap = const Duration(seconds: 10)});

  /// これより長い空白は戦闘の合間として戦闘時間に入れない。
  final Duration maxGap;

  final _Scope _all = _Scope();
  final Map<String, _Scope> _byEnemy = {};
  final Map<String, int> _enemyDamage = {};
  final Map<String, int> _enemyLast = {};
  int _count = 0;

  /// 受け取った事実の数。
  int get count => _count;

  /// [events] を集計に加える。[roster] は事実を加えた後のものを渡す。
  void add(Iterable<CombatEvent> events, Roster roster) {
    for (final e in events) {
      addJudged(e, side: roster.sideOf(e), enemy: roster.enemyOf(e), isEnemy: roster.isEnemy);
    }
  }

  /// 敵味方を判定済みの事実を 1 つ加える（記録した CSV を読み戻すときに使う）。
  /// [side] と [enemy] は [Roster.sideOf] と [Roster.enemyOf] の値。
  /// [isEnemy] は回復の行動者が敵かどうかの判定に使う。
  void addJudged(
    CombatEvent e, {
    required String side,
    required String? enemy,
    required bool Function(String name) isEnemy,
  }) {
    _count++;
    if (enemy != null) {
      final t = e.observedAt;
      if (t != null) _all.tick(t, maxGap);
      if (enemy.isNotEmpty) {
        _enemyLast[enemy] = _count;
        if (side == 'offense') _enemyDamage[enemy] = (_enemyDamage[enemy] ?? 0) + (e.damage ?? 0);
        final scope = _byEnemy.putIfAbsent(enemy, _Scope.new);
        if (t != null) scope.tick(t, maxGap);
        scope.add(e, side, isEnemy);
      }
    }
    _all.add(e, side, isEnemy);
  }

  /// 味方ごとの集計（与ダメージの多い順）。
  ///
  /// [enemies] を渡すと、その敵（複数可）との事実だけを合算する。戦闘時間は同時に戦った
  /// 時間を重ねて数えない。回復はどの敵にも属さないため、[enemies] を渡すと数えない。
  /// [names] を渡すと、その味方だけを返す。
  List<ActorSummary> summaries({Iterable<String>? enemies, Iterable<String>? names}) {
    final scopes = _scopes(enemies);
    final seconds = _Scope.timeOf(scopes, maxGap).inMilliseconds / 1000;
    final wanted = names?.toSet();
    final byName = <String, ActorSummary>{};
    for (final scope in scopes) {
      for (final s in scope.byName.values) {
        if (wanted != null && !wanted.contains(s.name)) continue;
        byName.putIfAbsent(s.name, () => ActorSummary(s.name))._addFrom(s);
      }
    }
    final list = [
      for (final s in byName.values)
        s..dps = seconds > 0 && s.timedDamage > 0 ? s.timedDamage / seconds : null,
    ];
    return list..sort((a, b) => b.damage.compareTo(a.damage));
  }

  List<_Scope> _scopes(Iterable<String>? enemies) =>
      enemies == null ? [_all] : [for (final n in enemies.toSet()) ?_byEnemy[n]];

  /// 戦った敵の一覧。最後に戦った敵が先頭。[damage] は味方から受けたダメージの合計。
  List<({String name, int damage})> enemies() {
    final names = _enemyLast.keys.toList()
      ..sort((a, b) => _enemyLast[b]!.compareTo(_enemyLast[a]!));
    return [for (final n in names) (name: n, damage: _enemyDamage[n] ?? 0)];
  }

  /// 戦闘時間（[combatTime] と同じ数え方）。[enemies] を渡すとその敵（複数可）と戦った時間。
  Duration timeOf({Iterable<String>? enemies}) => _Scope.timeOf(_scopes(enemies), maxGap);
}

class _Scope {
  final Map<String, ActorSummary> byName = {};

  /// ひと続きの戦闘（空白が maxGap 以下で続いた時刻の範囲）。戦闘時間を、複数の敵を
  /// 合わせても重ねずに数えるために持つ。戦闘の回数分しか増えない。
  final List<(DateTime, DateTime)> spans = [];

  void tick(DateTime t, Duration maxGap) {
    if (spans.isEmpty || t.difference(spans.last.$2) > maxGap) {
      spans.add((t, t));
    } else if (t.isAfter(spans.last.$2)) {
      spans.last = (spans.last.$1, t);
    }
  }

  /// [scopes] の戦闘を重ねて、ひと続きの戦闘ごとに長さ + 1 秒を足す。
  static Duration timeOf(List<_Scope> scopes, Duration maxGap) {
    final all = [for (final s in scopes) ...s.spans]..sort((a, b) => a.$1.compareTo(b.$1));
    var total = Duration.zero;
    (DateTime, DateTime)? cur;
    for (final s in all) {
      if (cur != null && s.$1.difference(cur.$2) <= maxGap) {
        if (s.$2.isAfter(cur.$2)) cur = (cur.$1, s.$2);
        continue;
      }
      if (cur != null) total += cur.$2.difference(cur.$1) + const Duration(seconds: 1);
      cur = s;
    }
    if (cur != null) total += cur.$2.difference(cur.$1) + const Duration(seconds: 1);
    return total;
  }

  void add(CombatEvent e, String side, bool Function(String name) isEnemy) {
    if (e.actor.isEmpty) return;
    ActorSummary of(String n) => byName.putIfAbsent(n, () => ActorSummary(n));
    if (e.stat == 'heal') {
      // 殴らない回復役は味方の名簿に入らないため、敵でなければ味方とみなす。
      if (!isEnemy(e.actor)) of(e.actor).heal += e.heal ?? 0;
      return;
    }
    if (side != 'offense') return;
    final s = of(e.actor);
    final d = e.damage ?? 0;
    s.damage += d;
    if (e.observedAt != null) s.timedDamage += d;
    switch (e.stat) {
      case 'melee' || 'crit' || 'counter':
        s.meleeHits++;
        s.meleeDamage += d;
        if (d > s.meleeMax) s.meleeMax = d;
        if (e.isCrit) s.meleeCrits++;
      case 'miss' when e.actionType == 'melee':
        s.meleeMisses++;
      case 'ranged':
        s.rangedHits++;
        s.rangedDamage += d;
        if (d > s.rangedMax) s.rangedMax = d;
        if (e.isCrit) s.rangedCrits++;
      case 'miss' when e.actionType == 'ranged':
        s.rangedMisses++;
      case 'miss' when e.actionType == 'ws' && e.hitNo == 1:
        s.wsMisses++;
        s._ws(e.actionName).misses++;
      case 'ws' when e.hitNo == 1:
        s.wsCount++;
        s.wsDamage += d;
        if (d > s.wsMax) s.wsMax = d;
        final w = s._ws(e.actionName);
        w.count++;
        w.damage += d;
        if (d > w.max) w.max = d;
      case 'ws':
        s.wsDamage += d;
        s._ws(e.actionName).damage += d;
      case 'spell':
        s.spellDamage += d;
      case 'mb':
        s.mbCount++;
        s.mbDamage += d;
        if (d > s.mbMax) s.mbMax = d;
      case 'add':
        s.addDamage += d;
      case 'sc':
        s.scDamage += d;
    }
  }
}

/// 味方ごとに与ダメージなどを集計し、与ダメージの多い順に返す。
List<ActorSummary> summarize(Iterable<CombatEvent> events, Roster roster) =>
    (SummaryAccumulator()..add(events, roster)).summaries();

/// 戦った敵の一覧。最後に戦った敵が先頭。[damage] は味方から受けたダメージの合計。
List<({String name, int damage})> enemiesByRecent(Iterable<CombatEvent> events, Roster roster) =>
    (SummaryAccumulator()..add(events, roster)).enemies();

/// 集計表の見出し（画面の表と同じ並び）。
const summaryColumns = [
  '名前',
  '与ダメージ',
  '割合',
  'DPS',
  '通常攻撃',
  '命中率',
  'クリ率',
  'WS 回数',
  'WS 平均',
  'WS 最大',
  '魔法',
  'MB',
  'MB 回数',
  'MB 最大',
  '追加',
  '技連携',
  '回復',
];

/// 集計表をタブ区切りの文字列にする（表計算ソフトにそのまま貼れる形）。
/// 数値は桁区切りなし、割合は「12.3%」。値がなければ空欄。
String summaryToTsv(List<ActorSummary> summaries, {String Function(String)? display}) {
  final total = summaries.fold<int>(0, (a, s) => a + s.damage);
  String pct(double? v) => v == null ? '' : '${(v * 100).toStringAsFixed(1)}%';
  String clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]'), ' ');
  final b = StringBuffer()..writeln(summaryColumns.join('\t'));
  for (final s in summaries) {
    final cells = [
      clean(display?.call(s.name) ?? s.name),
      '${s.damage}',
      total == 0 ? '' : pct(s.damage / total),
      s.dps?.toStringAsFixed(1) ?? '',
      '${s.meleeDamage}',
      pct(s.accuracy),
      pct(s.critRate),
      '${s.wsCount}',
      s.wsAverage == null ? '' : '${s.wsAverage!.round()}',
      '${s.wsMax}',
      '${s.spellDamage}',
      '${s.mbDamage}',
      '${s.mbCount}',
      '${s.mbMax}',
      '${s.addDamage}',
      '${s.scDamage}',
      '${s.heal}',
    ];
    b.writeln(cells.join('\t'));
  }
  return b.toString();
}
