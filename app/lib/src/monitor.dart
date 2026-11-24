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

  /// ウィンドウ 1 と 2 を重複なくまとめた集計。
  LogSession? _session;

  /// いま追記している CSV。
  CsvRecorder? _recorder;

  String? _dir;
  Timer? _timer;
  Timer? _debounce;
  StreamSubscription<WatchEvent>? _watch;
  bool _polling = false;
  String? error;

  /// いまの集計。
  LogSession? get session => _session;
  bool get running => _timer != null;

  /// 記録先の CSV を作る。記録しない設定なら null を返す。新しい事実か戦闘の行が来るたびに、
  /// 記録先がまだなければ呼ぶ。[startedAt] はファイル名に使う日時（区切った時刻）。
  CsvRecorder? Function(LogSession session, DateTime startedAt)? recorderFactory;

  /// いまの区切りを始めた日時（開始・停止・「ここから集計」・区切りの時刻）。
  DateTime _startedAt = DateTime.now();

  /// いま追記している CSV。まだ書く事実がないか、記録しない設定なら null。
  CsvRecorder? get recorder => _recorder;

  /// 閉じたが、まだ書けていない行が残っている CSV。書けるまで書き直す。
  final List<CsvRecorder> _draining = [];
  Timer? _drainTimer;

  /// 閉じた CSV のうち、まだ書けていない行の数。
  int get unsaved => _draining.fold(0, (a, r) => a + r.pending);

  /// いまの CSV を閉じる。次に事実が来たら新しいファイルに書く。
  /// 開始・停止・「ここから集計」・記録の設定を変えたときに呼ぶ。
  /// 書けていない行は捨てず、書けるまで書き直す（停止中も）。
  void cut() {
    _close();
    notifyListeners();
  }

  void _close() {
    _startedAt = DateTime.now();
    final r = _recorder;
    if (r != null && r.pending > 0) r.add(const []);
    if (r != null && r.pending > 0) _draining.add(r);
    _recorder = null;
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
  void start(String dir, {bool includePast = true}) {
    stop();
    error = null;
    _dir = dir;
    _session = LogSession(
      directory: Directory(dir),
      window: bothWindows,
      skipExisting: !includePast,
    );
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

  /// 集計を捨てて、この後に出た行だけを数え直す。
  void reset() {
    final dir = _dir;
    if (dir == null || _session == null) return;
    final wasRunning = running;
    start(dir, includePast: false);
    if (!wasRunning) stop();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), poll);
  }

  /// ディレクトリを読み直す。前回の読み込みが終わっていなければ何もしない。
  void poll() {
    final dir = _dir;
    final s = _session;
    if (dir == null || s == null || _polling) return;
    _polling = true;
    try {
      final added = s.poll();
      final lines = s.lastCombatLines;
      final fresh = added.isNotEmpty || lines.isNotEmpty;
      if (fresh && _recorder == null) _recorder = recorderFactory?.call(s, _startedAt);
      final r = _recorder;
      if (r != null && (fresh || r.pending > 0)) {
        final hadError = r.error != null;
        r.add(added, lines: lines);
        if (hadError != (r.error != null)) notifyListeners();
      }
      if (!Directory(dir).existsSync()) {
        error = 'フォルダが見つかりません: $dir';
        notifyListeners();
      } else if (fresh || error != null) {
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
