import 'dart:collection';

import 'log_file.dart';

/// [LogSession.window] に渡すと、ウィンドウ 1 と 2 をまとめて読む。
const bothWindows = 0;

/// ウィンドウ 1 と 2 の行を 1 本にまとめる。
///
/// メッセージの番号（[LogLine.messageId]）はウィンドウをまたいだ通し番号で、
/// 同じメッセージは両方のウィンドウで同じ番号・同じ本文になる。そこで
/// 「番号・本文・そのメッセージ内で同じ本文が何回目か」が同じ行は 1 回だけ通す。
/// 片方のウィンドウにしか出ない行（ウィンドウごとに出す種類を分けている場合）はそのまま通す。
///
/// 並びは、それぞれのウィンドウの行番号順を保ったまま、メッセージの番号の順に合わせる。
/// 別々の読み込みで届いた行は、届いた順になる。
class WindowMerger {
  /// 覚えておく行の数。ログファイル 20 個 × 50 行 × 2 ウィンドウより多くとる。
  static const capacity = 4000;

  final LinkedHashSet<(int, String, int)> _seen = LinkedHashSet();
  final LinkedHashMap<(int, int, String), int> _counts = LinkedHashMap();

  /// [lines]（ウィンドウ→行番号の順）から、まだ通していない行を並べて返す。
  List<LogLine> merge(List<LogLine> lines) {
    final a = [
      for (final l in lines)
        if (l.window == 1) l,
    ];
    final b = [
      for (final l in lines)
        if (l.window == 2) l,
    ];
    final out = <LogLine>[];
    var i = 0, j = 0;
    while (i < a.length || j < b.length) {
      final takeA = j >= b.length || (i < a.length && a[i].messageId <= b[j].messageId);
      final line = takeA ? a[i++] : b[j++];
      final k = (line.window, line.messageId, line.text);
      final n = _counts[k] ?? 0;
      _counts.remove(k);
      _counts[k] = n + 1;
      if (_seen.add((line.messageId, line.text, n))) out.add(line);
    }
    while (_seen.length > capacity) {
      _seen.remove(_seen.first);
    }
    while (_counts.length > capacity) {
      _counts.remove(_counts.keys.first);
    }
    return out;
  }
}
