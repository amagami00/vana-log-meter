import 'dart:io';
import 'dart:typed_data';

import 'log_file.dart';

final _logFileName = RegExp(r'^([12])_(\d{1,2})\.log$');

/// ログファイル名（`1_0.log` など）からウィンドウ番号とファイル番号を取り出す。
/// 対象外の名前なら null。
({int window, int fileIndex})? parseLogFileName(String name) {
  final m = _logFileName.firstMatch(name);
  if (m == null) return null;
  final index = int.parse(m.group(2)!);
  if (index >= filesPerWindow) return null;
  return (window: int.parse(m.group(1)!), fileIndex: index);
}

/// 読み込んだ行をウィンドウごとに行番号で重複なく保持する。
///
/// ゲームは 20 ファイルを順に上書きするので、同じファイルを何度読み直しても
/// 新しい行だけを [ingest] が返す。上書きでファイルから消えた行は捨てる
/// （もう読まれないので重複の判定に要らない）。保持する行は最大でファイル 20 個分。
class LogStore {
  final Map<int, Map<int, LogLine>> _windows = {};

  /// ファイルごとの、そのファイルから取り込んだ行番号。上書きで消えた行を捨てるのに使う。
  final Map<(int, int), Set<int>> _files = {};
  int incomplete = 0;
  int malformed = 0;

  /// 保持している行の数（全ウィンドウ）。
  int get size => _windows.values.fold(0, (a, m) => a + m.length);

  /// ファイル 1 つ分のバイト列を取り込み、初めて見た行を行番号順に返す。
  List<LogLine> ingest(Uint8List bytes, {required int window, required int fileIndex}) {
    final result = parseLogFile(bytes, window: window, fileIndex: fileIndex);
    incomplete += result.incomplete;
    malformed += result.malformed;
    final seen = _windows.putIfAbsent(window, () => {});
    final present = <int>{};
    final added = <LogLine>[];
    var replaced = false;
    for (final line in result.lines) {
      present.add(line.lineNo);
      final old = seen[line.lineNo];
      if (old != null) {
        // ゲームは起動のたびに行番号を 0 から数え直す。前のセッションの行が残るファイルに
        // 同じ行番号で別の内容が書かれたら、新しい行として扱う。
        if (old.text == line.text && old.messageId == line.messageId) continue;
        replaced = true;
      }
      seen[line.lineNo] = line;
      added.add(line);
    }
    // このファイルから取り込んだのに、いまは無い行（上書きで消えた行）を捨てる。
    // 上書きの証拠は「前に無かった行番号がある」か「同じ行番号の内容が変わった」こと。
    // 空や途中で切れた読み込みでは捨てない（捨てると次に全体を読んだとき、同じ行を
    // 新しい行として返してしまう）。別のファイルが持つ同じ行番号の行は残す。
    final owned = _files[(window, fileIndex)] ?? const <int>{};
    final overwritten = replaced || (owned.isNotEmpty && present.any((n) => !owned.contains(n)));
    if (overwritten) {
      for (final n in owned.difference(present)) {
        if (seen[n]?.fileIndex == fileIndex) seen.remove(n);
      }
    }
    _files[(window, fileIndex)] = {
      if (!overwritten) ...owned,
      for (final n in present)
        if (seen[n]?.fileIndex == fileIndex) n,
    };
    added.sort((a, b) => a.lineNo.compareTo(b.lineNo));
    return added;
  }

  /// ディレクトリ内のログファイルをすべて取り込み、初めて見た行を返す。
  List<LogLine> ingestDirectory(Directory dir) {
    final added = <LogLine>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final id = parseLogFileName(entity.uri.pathSegments.last);
      if (id == null) continue;
      final Uint8List bytes;
      try {
        bytes = entity.readAsBytesSync();
      } on FileSystemException {
        // ゲームが書き込み中でロックしている場合がある。次の読み直しで拾う。
        continue;
      }
      added.addAll(ingest(bytes, window: id.window, fileIndex: id.fileIndex));
    }
    added.sort((a, b) {
      final w = a.window.compareTo(b.window);
      return w != 0 ? w : a.lineNo.compareTo(b.lineNo);
    });
    return added;
  }

  /// 指定ウィンドウの保持している行を行番号順に返す。
  List<LogLine> linesOf(int window) {
    final lines = (_windows[window] ?? const {}).values.toList()
      ..sort((a, b) => a.lineNo.compareTo(b.lineNo));
    return lines;
  }

  Iterable<int> get windows => _windows.keys;
}
