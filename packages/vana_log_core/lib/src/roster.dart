import 'combat.dart';

/// メッセージ種別のうち、自分の行動に使われるもの（文字色で分かれている）。
const _selfModes = {0x14, 0x15};

/// 味方の通常攻撃・ミスに使われるメッセージ種別。
const _allyMeleeModes = {0x14, 0x15, 0x19, 0x1A, _outsideMode};

/// パーティの外（同盟の別のパーティなど）の行動に使われるメッセージ種別。
/// 近くにいるだけの他人の行動も含みうるが、味方として数える。
const _outsideMode = 0xA3;

/// 敵の行動に使われるメッセージ種別（0x1C / 0x1D は自分が受けた攻撃の命中・ミス）。
const _enemyModes = {0x1B, 0x1C, 0x1D, 0x20, 0x69};

/// 戦闘の事実から、名前ごとに味方か敵かを推定する。
///
/// ログには行動者の種別がないため、メッセージ種別（文字色）から判定する。
/// 同じ名前の敵は区別できない。
class Roster {
  final Set<String> allies = {};
  final Set<String> enemies = {};
  final Set<String> self = {};

  void addAll(Iterable<CombatEvent> events) {
    for (final e in events) {
      if (e.actor.isEmpty) continue;
      final mode = e.line.mode;
      final offensive = e.damage != null || e.isMiss;
      final attack = e.actionType == 'melee' || e.actionType == 'ranged';
      if (attack && _allyMeleeModes.contains(mode) && !e.actorInferred) {
        allies.add(e.actor);
        if (_selfModes.contains(mode)) self.add(e.actor);
        enemies.add(e.target);
      } else if (_selfModes.contains(mode) && offensive && !e.actorInferred) {
        // 殴らずに魔法や WS だけで戦う自分も、味方と分かるようにする。
        allies.add(e.actor);
        self.add(e.actor);
        enemies.add(e.target);
      } else if (mode == _outsideMode && offensive && !e.actorInferred) {
        // 殴らずに魔法だけで戦う、パーティの外の味方。範囲攻撃のつなぎ違いで敵が
        // 味方に入らないよう、敵と分かっている名前は味方にしない。
        if (!enemies.contains(e.actor)) allies.add(e.actor);
        if (!allies.contains(e.target)) enemies.add(e.target);
      } else if (_enemyModes.contains(mode)) {
        enemies.add(e.actor);
        allies.add(e.target);
      }
    }
    // 両方に入った名前は味方を優先する。
    enemies.removeAll(allies);
  }

  bool isAlly(String name) => allies.contains(name);
  bool isEnemy(String name) => enemies.contains(name) && !allies.contains(name);

  /// `offense`（味方→敵）/ `defense`（敵→味方）/ `support`（味方→味方）/ `other`。
  String sideOf(CombatEvent e) {
    final actorAlly = e.actor.isNotEmpty && isAlly(e.actor);
    final actorEnemy = e.actor.isNotEmpty && isEnemy(e.actor);
    final targetAlly = isAlly(e.target);
    final targetEnemy = isEnemy(e.target);
    if (e.actor.isEmpty) {
      // 行動者を推定できなかった追加ダメージ・技連携は対象で決める。
      if (targetEnemy) return 'offense';
      if (targetAlly) return 'defense';
      return 'other';
    }
    if (actorAlly && targetEnemy) return 'offense';
    if (actorEnemy && targetAlly) return 'defense';
    if (actorAlly && targetAlly) return 'support';
    return 'other';
  }

  /// その事実で相手になっている敵の名前。味方どうしの行動などでは null。
  String? enemyOf(CombatEvent e) => switch (sideOf(e)) {
    'offense' => e.target,
    'defense' => e.actor.isEmpty ? null : e.actor,
    _ => null,
  };

  /// 敵の WS は battlelog に合わせて `tp_move` にする。
  String actionTypeOf(CombatEvent e) =>
      e.actionType == 'ws' && isEnemy(e.actor) ? 'tp_move' : e.actionType;
}
