import 'dart:collection';
import 'dart:io';

import 'combat.dart';
import 'log_file.dart';
import 'log_store.dart';
import 'roster.dart';
import 'summary.dart';
import 'window_merger.dart';

/// 1 つのログディレクトリ・1 つのウィンドウを読み続け、戦闘の事実を集計する。
/// [window] に [bothWindows] を渡すと、ウィンドウ 1 と 2 を重複なくまとめて読む。
///
/// 事実そのものは保持しない（[poll] の戻り値で受け取り、必要ならファイルに書く）。
/// 保持するのは集計値・名前・直近の戦闘の行 [maxCombatLines] 行・ログファイル 20 個分の行だけで、
/// 長時間記録してもメモリはほぼ増えない。
///
/// [poll] を何度呼んでも、初めて見た行だけを処理する。書き込み途中の行は
/// 次の [poll] で完成してから 1 回だけ処理される。
class LogSession {
  LogSession({
    required this.directory,
    this.window = 1,
    this.skipExisting = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       startedAt = (clock ?? DateTime.now)();

  /// 記録を始めた時刻（このセッションを作った時刻）。書き出しの `elapsed` の 0 秒。
  final DateTime startedAt;

  final Directory directory;

  /// 読むウィンドウ（1 / 2）。[bothWindows] なら両方。
  final int window;

  /// 開始前から残っていた行（1 回目の [poll] で読む行）を集計に入れない。
  /// 文脈（構えた WS など）と敵味方の推定には使う。
  final bool skipExisting;
  final DateTime Function() _clock;

  final LogStore store = LogStore();
  final CombatParser parser = CombatParser();
  final Roster roster = Roster();
  final SummaryAccumulator summary = SummaryAccumulator();
  final WindowMerger _merger = WindowMerger();

  /// 事実に出てきた名前（行動者・対象）。初めて見た順。名前の置き換えに使う。
  final Set<String> names = {};

  /// 画面に出す戦闘の行の上限。
  static const maxCombatLines = 2000;

  /// 直近の戦闘の行（チャットなど戦闘以外の行は除く）。行番号の順、最大 [maxCombatLines] 行。
  /// [observedAt] は [CombatEvent.observedAt] と同じ。
  final ListQueue<({LogLine line, DateTime? observedAt})> combatLines = ListQueue();

  /// 直前の [poll] で読んだ戦闘の行（行番号の順）。[combatLines] と違い、毎回入れ替える。
  /// skipExisting の 1 回目は空。
  List<({LogLine line, DateTime? observedAt})> lastCombatLines = const [];

  int _polls = 0;

  /// 最後に新しい行を読んだ時刻。
  DateTime? lastUpdated;

  /// 集計した事実の数。
  int get eventCount => summary.count;

  /// ディレクトリを読み直し、新しく取り出した事実を返す。
  ///
  /// 1 回目に読んだ行（開始前から残っていた行）は時刻が分からないため、
  /// [CombatEvent.observedAt] を null にする。2 回目以降は検知した時刻を入れる。
  List<CombatEvent> poll() {
    final first = _polls++ == 0;
    final observedAt = first ? null : _clock();
    lastCombatLines = const [];
    if (!directory.existsSync()) return const [];
    // ingestDirectory はウィンドウ→行番号の順に並べて返す。ファイルをまたいでも順序が保たれる。
    final all = store.ingestDirectory(directory);
    final lines = window == bothWindows
        ? _merger.merge(all)
        : all.where((l) => l.window == window).toList();
    if (first && skipExisting) {
      for (final line in lines) {
        roster.addAll(parser.add(line));
      }
      return const [];
    }
    final added = <CombatEvent>[];
    final combat = <({LogLine line, DateTime? observedAt})>[];
    for (final line in lines) {
      added.addAll(parser.add(line, observedAt: observedAt));
      if (parser.lastCategory != LineCategory.other) {
        final entry = (line: line, observedAt: observedAt);
        combat.add(entry);
        combatLines.add(entry);
        if (combatLines.length > maxCombatLines) combatLines.removeFirst();
      }
    }
    lastCombatLines = combat;
    if (added.isNotEmpty || lines.isNotEmpty) lastUpdated = _clock();
    // 名簿を先に更新してから集計する（同じ読み込みの中で敵味方が分かった分を反映する）。
    roster.addAll(added);
    summary.add(added, roster);
    for (final e in added) {
      if (e.actor.isNotEmpty) names.add(e.actor);
      if (e.target.isNotEmpty) names.add(e.target);
    }
    return added;
  }

  /// 戦闘の行のうち読めた割合（0〜100）。戦闘の行がなければ null。
  double? get readability {
    final c = parser.counts;
    final total = c[LineCategory.event]! + c[LineCategory.context]! + c[LineCategory.unparsed]!;
    if (total == 0) return null;
    return 100 * (total - c[LineCategory.unparsed]!) / total;
  }

  int get unparsedCount => parser.counts[LineCategory.unparsed]!;
}
