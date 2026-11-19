import 'log_file.dart';

/// 戦闘ログ 1 行から読み取った 1 つの事実（1 対象への 1 ヒットなど）。
class CombatEvent {
  CombatEvent({
    required this.line,
    required this.seq,
    required this.hitNo,
    required this.kind,
    required this.actor,
    required this.target,
    required this.actionType,
    required this.stat,
    this.actionName,
    this.scType,
    this.damage,
    this.heal,
    this.isHit = false,
    this.isCrit = false,
    this.isMiss = false,
    this.actorInferred = false,
    this.observedAt,
  });

  /// 元になったログの行。
  final LogLine line;

  /// 行動の番号（同じ行動の行は同じ値）。ログのメッセージ番号を使う。
  final int seq;

  /// 同じ行動の中での対象ごとのヒット番号（1 から）。
  final int hitNo;

  /// `main`（行動そのもの）/ `add`（追加ダメージ・技連携）。
  final String kind;

  final String actor;
  final String target;

  /// `melee` / `ws` / `ja` / `spell` / `tp_move` / `defeat`。
  final String actionType;

  /// `melee` / `crit` / `miss` / `ws` / `ja` / `spell` / `mb` / `add` / `sc` /
  /// `counter` / `heal` / `defeat`。
  final String stat;

  /// 技・魔法・アビリティの名前（日本語）。通常攻撃は null。
  final String? actionName;

  /// 技連携の属性（湾曲・闇など）。`stat=sc` の行だけ。
  final String? scType;

  final int? damage;
  final int? heal;
  final bool isHit;
  final bool isCrit;
  final bool isMiss;

  /// 行動者がログに書かれておらず、直前の行から推定したなら true
  /// （追加ダメージ・技連携）。
  final bool actorInferred;

  /// 行を初めて読んだ時刻。戦闘の行には時刻がないため、監視中の検知時刻で代用する。
  /// 保存済みのファイルをまとめて読んだ場合は null。
  DateTime? observedAt;
}

/// 本文の解釈結果の分類（読解率の計測用）。
enum LineCategory {
  /// 戦闘の事実として取り出した。
  event,

  /// 戦闘に関わる行だと判定できたが、集計する数値はない（詠唱開始・構え・状態変化など）。
  context,

  /// 戦闘の行らしいが、読めなかった（直前の行が欠けている・未知の形式）。
  unparsed,

  /// 戦闘と関係のない行（チャット・システムメッセージなど）。
  other,
}

class _Context {
  _Context(this.actor, this.actionType, this.stat, {this.name, this.crit = false});
  final String actor;
  final String actionType;
  final String stat;
  final String? name;
  final bool crit;
  int hits = 0;
}

final _meleeHit = RegExp(r'^(.+?)の攻撃→(.+)に、(\d+)ダメージ。$');
final _meleeMiss = RegExp(r'^(.+?)の攻撃→(.+)に、ミス。$');
final _meleeCrit = RegExp(r'^(.+?)の攻撃。クリティカル！$');
final _counter = RegExp(r'^(.+?)の反撃効果→(.+)に、(\d+)ダメージ。$');
final _execute = RegExp(r'^(.+?)は、(.+)を実行。$');
final _spellFire = RegExp(r'^(.+?)の(.+)が発動。$');
final _castStart = RegExp(r'^(.+?)は、(.+?)に(.+)を唱えた。$');
final _ready = RegExp(r'^(.+?)は、(.+)の構え。$');
final _defeat = RegExp(r'^(.+?)は、(.+)を倒した。$');
final _directHeal = RegExp(r'^(.+?)の(.+)→(.+)のHPが、(\d+)回復。$');
final _directOther = RegExp(r'^(.+?)の(.+)→(.+)の(MP|TP)が、(\d+)回復。$');
final _arrowDamage = RegExp(r'^→(マジックバースト！)?(.+)に、(\d+)ダメージ。$');
final _arrowMiss = RegExp(r'^→(.+)に、ミス。$');
final _arrowHeal = RegExp(r'^→(.+)のHPが、(\d+)回復。$');
final _addDamage = RegExp(r'^追加ダメージ→(.+)に、(\d+)ダメージ。$');
final _skillchain = RegExp(r'^技連携・(.+?)→(.+)に、(\d+)ダメージ。$');
final _wearOff = RegExp(r'^(.+?)は、(.+)(の効果がきれた|状態から回復した)。$');
final _notCombat = RegExp(r'^(装備セット\d+を実行しました。|ハッピーパワー「)');
final _combatHint = RegExp(r'ダメージ|ミス|回復|倒した|唱えた|実行|構え|発動|効果|状態');

/// ログの行を順に受け取り、戦闘の事実に変換する。ウィンドウごとに 1 つ使う。
class CombatParser {
  final Map<int, _Context> _contexts = {};
  final Set<String> _readied = {};

  /// 対象ごとの直近の通常攻撃の行動者（追加ダメージの行動者の推定に使う）。
  final Map<String, String> _lastMeleeActor = {};

  /// 対象ごとの直近の WS の行動者（技連携の行動者の推定に使う）。
  final Map<String, String> _lastWsActor = {};

  /// 直前に [add] で渡した行（範囲攻撃の 2 体目以降を、直前の行の文脈につなぐのに使う）。
  LogLine? _prevLine;

  final Map<LineCategory, int> counts = {for (final c in LineCategory.values) c: 0};

  /// 読めなかった行（調査用。最大 [_unparsedKeep] 件）。
  final List<LogLine> unparsed = [];
  static const _unparsedKeep = 200;

  /// 1 行を解釈し、取り出した事実を返す（なければ空）。
  /// 直前の [add] で渡した行の分類。
  LineCategory? lastCategory;

  List<CombatEvent> add(LogLine line, {DateTime? observedAt}) {
    final (category, events) = _classify(line);
    lastCategory = category;
    _prevLine = line;
    counts[category] = counts[category]! + 1;
    if (category == LineCategory.unparsed && unparsed.length < _unparsedKeep) {
      unparsed.add(line);
    }
    for (final e in events) {
      e.observedAt = observedAt;
    }
    return events;
  }

  (LineCategory, List<CombatEvent>) _classify(LogLine line) {
    final t = line.text;
    RegExpMatch? m;

    if ((m = _meleeHit.firstMatch(t)) != null) {
      final ctx = _newContext(line, m!.group(1)!, 'melee', 'melee');
      return _hit(line, ctx, m.group(2)!, int.parse(m.group(3)!));
    }
    if ((m = _meleeMiss.firstMatch(t)) != null) {
      final ctx = _newContext(line, m!.group(1)!, 'melee', 'melee');
      return _miss(line, ctx, m.group(2)!);
    }
    if ((m = _meleeCrit.firstMatch(t)) != null) {
      _newContext(line, m!.group(1)!, 'melee', 'crit', crit: true);
      return (LineCategory.context, const []);
    }
    if ((m = _counter.firstMatch(t)) != null) {
      final ctx = _newContext(line, m!.group(1)!, 'melee', 'counter');
      return _hit(line, ctx, m.group(2)!, int.parse(m.group(3)!));
    }
    if ((m = _execute.firstMatch(t)) != null) {
      final actor = m!.group(1)!;
      final name = m.group(2)!;
      final isWs = _readied.remove('$actor\u0000$name');
      _newContext(line, actor, isWs ? 'ws' : 'ja', isWs ? 'ws' : 'ja', name: name);
      return (LineCategory.context, const []);
    }
    if ((m = _ready.firstMatch(t)) != null) {
      _readied.add('${m!.group(1)}\u0000${m.group(2)}');
      return (LineCategory.context, const []);
    }
    if ((m = _castStart.firstMatch(t)) != null) {
      return (LineCategory.context, const []);
    }
    if ((m = _defeat.firstMatch(t)) != null) {
      return (
        LineCategory.event,
        [
          CombatEvent(
            line: line,
            seq: line.messageId,
            hitNo: 1,
            kind: 'main',
            actor: m!.group(1)!,
            target: m.group(2)!,
            actionType: 'defeat',
            stat: 'defeat',
          ),
        ],
      );
    }
    if ((m = _directHeal.firstMatch(t)) != null) {
      final ctx = _newContext(line, m!.group(1)!, 'ja', 'heal', name: m.group(2));
      return _heal(line, ctx, m.group(3)!, int.parse(m.group(4)!));
    }
    if (_directOther.hasMatch(t)) {
      return (LineCategory.context, const []);
    }
    if ((m = _spellFire.firstMatch(t)) != null) {
      _newContext(line, m!.group(1)!, 'spell', 'spell', name: m.group(2));
      return (LineCategory.context, const []);
    }

    if (t.startsWith('→')) {
      final ctx = _contexts[line.messageId] ?? _continued(line);
      if (ctx == null) {
        // 対象ごとにメッセージ番号が分かれる効果の行（「→X は、ランパートの効果。」）は
        // 数値を持たないので文脈として扱う。数値を持つ行は直前の行が欠けている。
        if (_arrowDamage.hasMatch(t) || _arrowMiss.hasMatch(t) || _arrowHeal.hasMatch(t)) {
          return (LineCategory.unparsed, const []);
        }
        return (_combatHint.hasMatch(t) ? LineCategory.context : LineCategory.other, const []);
      }
      if ((m = _arrowDamage.firstMatch(t)) != null) {
        final mb = m!.group(1) != null;
        return _hit(line, ctx, m.group(2)!, int.parse(m.group(3)!), magicBurst: mb);
      }
      if ((m = _arrowMiss.firstMatch(t)) != null) {
        return _miss(line, ctx, m!.group(1)!);
      }
      if ((m = _arrowHeal.firstMatch(t)) != null) {
        return _heal(line, ctx, m!.group(1)!, int.parse(m.group(2)!));
      }
      // 状態変化・効果など。集計する数値はない。
      return (LineCategory.context, const []);
    }

    if ((m = _addDamage.firstMatch(t)) != null) {
      final target = m!.group(1)!;
      return _inferred(
        line,
        target,
        int.parse(m.group(2)!),
        actor: _lastMeleeActor[target],
        stat: 'add',
        actionType: 'melee',
      );
    }
    if ((m = _skillchain.firstMatch(t)) != null) {
      final target = m!.group(2)!;
      return _inferred(
        line,
        target,
        int.parse(m.group(3)!),
        actor: _lastWsActor[target],
        stat: 'sc',
        actionType: 'ws',
        scType: m.group(1),
      );
    }

    if (_wearOff.hasMatch(t)) return (LineCategory.context, const []);
    if (_notCombat.hasMatch(t) || _looksLikeChat(t) || !_combatHint.hasMatch(t)) {
      return (LineCategory.other, const []);
    }
    return (LineCategory.unparsed, const []);
  }

  /// 範囲攻撃の 2 体目以降は、対象ごとにメッセージ番号が 1 つずつ増え、矢印の行だけが続く。
  /// 直前の行と行番号・メッセージ番号が連続し、モードが同じなら、その文脈を引き継ぐ。
  _Context? _continued(LogLine line) {
    final prev = _prevLine;
    if (prev == null ||
        prev.lineNo + 1 != line.lineNo ||
        prev.messageId + 1 != line.messageId ||
        prev.mode != line.mode) {
      return null;
    }
    final ctx = _contexts[prev.messageId];
    if (ctx != null) _contexts[line.messageId] = ctx;
    return ctx;
  }

  _Context _newContext(
    LogLine line,
    String actor,
    String actionType,
    String stat, {
    String? name,
    bool crit = false,
  }) {
    final ctx = _Context(actor, actionType, stat, name: name, crit: crit);
    _contexts[line.messageId] = ctx;
    if (_contexts.length > 256) {
      _contexts.remove(_contexts.keys.first);
    }
    return ctx;
  }

  (LineCategory, List<CombatEvent>) _hit(
    LogLine line,
    _Context ctx,
    String target,
    int damage, {
    bool magicBurst = false,
  }) {
    ctx.hits++;
    final stat = magicBurst ? 'mb' : ctx.stat;
    if (ctx.actionType == 'melee') _lastMeleeActor[target] = ctx.actor;
    if (ctx.actionType == 'ws') _lastWsActor[target] = ctx.actor;
    return (
      LineCategory.event,
      [
        CombatEvent(
          line: line,
          seq: line.messageId,
          hitNo: ctx.hits,
          kind: 'main',
          actor: ctx.actor,
          target: target,
          actionType: ctx.actionType,
          actionName: ctx.name,
          stat: stat,
          damage: damage,
          isHit: true,
          isCrit: ctx.crit,
        ),
      ],
    );
  }

  (LineCategory, List<CombatEvent>) _miss(LogLine line, _Context ctx, String target) {
    ctx.hits++;
    return (
      LineCategory.event,
      [
        CombatEvent(
          line: line,
          seq: line.messageId,
          hitNo: ctx.hits,
          kind: 'main',
          actor: ctx.actor,
          target: target,
          actionType: ctx.actionType,
          actionName: ctx.name,
          stat: 'miss',
          isMiss: true,
        ),
      ],
    );
  }

  (LineCategory, List<CombatEvent>) _heal(LogLine line, _Context ctx, String target, int amount) {
    ctx.hits++;
    return (
      LineCategory.event,
      [
        CombatEvent(
          line: line,
          seq: line.messageId,
          hitNo: ctx.hits,
          kind: 'main',
          actor: ctx.actor,
          target: target,
          actionType: ctx.actionType,
          actionName: ctx.name,
          stat: 'heal',
          heal: amount,
          isHit: true,
        ),
      ],
    );
  }

  (LineCategory, List<CombatEvent>) _inferred(
    LogLine line,
    String target,
    int damage, {
    required String? actor,
    required String stat,
    required String actionType,
    String? scType,
  }) {
    return (
      LineCategory.event,
      [
        CombatEvent(
          line: line,
          seq: line.messageId,
          hitNo: 1,
          kind: 'add',
          actor: actor ?? '',
          target: target,
          actionType: actionType,
          stat: stat,
          scType: scType,
          damage: damage,
          isHit: true,
          actorInferred: true,
        ),
      ],
    );
  }

  static final _chatPrefix = RegExp(r'^\[\d{1,2}:\d{2}(:\d{2})?\]');
  bool _looksLikeChat(String t) => _chatPrefix.hasMatch(t);
}
