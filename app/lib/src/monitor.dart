import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vana_log_core/vana_log_core.dart';
import 'package:watcher/watcher.dart';

/// ログのディレクトリを監視し、新しい行を [LogSession] に流し込む。
///
/// 取り込みは [poll] の 1 本だけ。定期的な読み直しを正とし、ファイルの変更通知は
/// 「すぐ読み直す」合図にだけ使う（Windows ではゲームが書き込んでも通知や
/// 更新日時が遅れることがあるため）。
class LogMonitor extends ChangeNotifier {
  LogMonitor({this.interval = const Duration(seconds: 1)});

  final Duration interval;

  /// ウィンドウごとの集計。監視中に一度選んだウィンドウは、表示を切り替えても読み続ける。
  final Map<int, LogSession> _sessions = {};

  /// ウィンドウごとのいま追記している CSV。
  final Map<int, CsvRecorder> _recorders = {};

  String? _dir;
  int _window = 1;
  bool _includePast = true;
  Timer? _timer;
  Timer? _debounce;
  StreamSubscription<WatchEvent>? _watch;
  bool _polling = false;
  String? error;

  /// 表示しているウィンドウの集計。
  LogSession? get session => _sessions[_window];

  /// 表示しているウィンドウ。
  int get window => _window;
  bool get running => _timer != null;

  /// 記録先の CSV を作る。記録しない設定なら null を返す。新しい事実か戦闘の行が来るたびに、
  /// 記録先がまだなければ呼ぶ。
  CsvRecorder? Function(LogSession session)? recorderFactory;

  /// 表示しているウィンドウのいま追記している CSV。まだ書く事実がないか、記録しない設定なら null。
  CsvRecorder? get recorder => _recorders[_window];

  /// 閉じたが、まだ書けていない行が残っている CSV。書けるまで書き直す。
  final List<CsvRecorder> _draining = [];
  Timer? _drainTimer;

  /// 閉じた CSV のうち、まだ書けていない行の数。
  int get unsaved => _draining.fold(0, (a, r) => a + r.pending);

  /// いまの CSV を（すべてのウィンドウで）閉じる。次に事実が来たら新しいファイルに書く。
  /// 開始・停止・「ここから集計」・記録の設定を変えたときに呼ぶ。
  /// 書けていない行は捨てず、書けるまで書き直す（停止中も）。
  void cut() {
    _close();
    notifyListeners();
  }

  void _close() {
    for (final r in _recorders.values) {
      if (r.pending > 0) r.add(const []);
      if (r.pending > 0) _draining.add(r);
    }
    _recorders.clear();
    if (_draining.isNotEmpty) _drainTimer ??= Timer.periodic(interval, (_) => _drain());
  }

  void _drain() {
    final before = unsaved;
    for (final r in _draining) {
      r.add(const []);
    }
    _draining.removeWhere((r) => r.pending == 0);
    if (_draining.isEmpty) {
      _drainTimer?.cancel();
      _drainTimer = null;
    }
    if (unsaved != before) notifyListeners();
  }

  /// [dir] の監視を始める。それまでの集計は捨てる。
  /// [includePast] が false なら、いま残っている行は集計に入れず、この後に出た行だけを数える。
  void start(String dir, int window, {bool includePast = true}) =>
      _start(dir, window, {window}, includePast: includePast);

  void _start(String dir, int window, Set<int> windows, {required bool includePast}) {
    stop();
    _sessions.clear();
    error = null;
    _dir = dir;
    _window = window;
    _includePast = includePast;
    for (final w in windows) {
      _open(w);
    }
    poll();
    _timer = Timer.periodic(interval, (_) => poll());
    try {
      _watch = DirectoryWatcher(dir).events.listen(
        (_) => _schedule(),
        // 通知が使えなくても定期読み直しで拾えるので、監視は止めない。
        onError: (Object _) {},
        cancelOnError: false,
      );
    } on Object {
      _watch = null;
    }
    notifyListeners();
  }

  void stop() {
    _close();
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    _debounce = null;
    _watch?.cancel();
    _watch = null;
    notifyListeners();
  }

  void _open(int window) => _sessions[window] = LogSession(
    directory: Directory(_dir!),
    window: window,
    skipExisting: !_includePast,
  );

  /// 表示するウィンドウを変える。それまで見ていたウィンドウの集計と CSV は閉じずに続ける
  /// （読み直しや書き直しをしない）。監視中に初めて選んだウィンドウは、ここから読み始める。
  void select(int window) {
    if (window == _window) return;
    _window = window;
    if (running && !_sessions.containsKey(window)) {
      _open(window);
      poll();
    }
    notifyListeners();
  }

  /// 集計を捨てて、この後に出た行だけを数え直す。読んでいたウィンドウはすべて数え直す。
  void reset() {
    final dir = _dir;
    if (dir == null || _sessions.isEmpty) return;
    final wasRunning = running;
    _start(dir, _window, {..._sessions.keys}, includePast: false);
    if (!wasRunning) stop();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), poll);
  }

  /// ディレクトリを読み直す。前回の読み込みが終わっていなければ何もしない。
  void poll() {
    final dir = _dir;
    if (dir == null || _sessions.isEmpty || _polling) return;
    _polling = true;
    try {
      var any = false;
      for (final MapEntry(key: w, value: s) in _sessions.entries) {
        final added = s.poll();
        final lines = s.lastCombatLines;
        final fresh = added.isNotEmpty || lines.isNotEmpty;
        any |= fresh;
        if (fresh && !_recorders.containsKey(w)) {
          final r = recorderFactory?.call(s);
          if (r != null) _recorders[w] = r;
        }
        final r = _recorders[w];
        if (r != null && (fresh || r.pending > 0)) {
          final hadError = r.error != null;
          r.add(added, lines: lines);
          if (hadError != (r.error != null)) notifyListeners();
        }
      }
      if (!Directory(dir).existsSync()) {
        error = 'フォルダが見つかりません: $dir';
        notifyListeners();
      } else if (any || error != null) {
        error = null;
        notifyListeners();
      }
    } on Object catch (e) {
      error = '読み込みに失敗しました: $e';
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    stop();
    _drainTimer?.cancel();
    super.dispose();
  }
}
