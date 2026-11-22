import 'dart:io';

import 'combat.dart';
import 'log_file.dart';
import 'masker.dart';
import 'roster.dart';
import 'session.dart';
import 'window_merger.dart';

/// 出力する列。名前と意味は battlelog の CSV に合わせ、
/// ネイティブログから取れる列だけを出す。末尾の `log_*` などはこのアプリ独自の列。
const exportColumns = [
  'session',
  'seq',
  'hit_no',
  'kind',
  'time',
  'elapsed',
  'side',
  'action_type',
  'ally',
  'enemy',
  'action_ja',
  'stat',
  'sc_type_ja',
  'damage',
  'heal',
  'is_hit',
  'is_crit',
  'is_miss',
  'actor_name',
  'target_name',
  'actor_inferred',
  'log_window',
  'log_line',
  'chat_mode',
  'text',
];

/// 戦闘の事実を、出力用の 1 行（列名→値）に変換する。
/// 該当しない値は null（CSV では空欄）にし、0 と区別する。
/// `elapsed` は [startedAt]（記録を始めた時刻）からの秒数。省略時は最初に時刻の付いた事実を 0 にする。
List<Map<String, Object?>> toRows(
  List<CombatEvent> events, {
  required String session,
  Roster? roster,
  DateTime? startedAt,
}) {
  final r = roster ?? (Roster()..addAll(events));
  var start = startedAt;
  if (start == null) {
    for (final e in events) {
      final t = e.observedAt;
      if (t != null && (start == null || t.isBefore(start))) start = t;
    }
  }
  return [for (final e in events) _row(e, r, session, start)];
}

Map<String, Object?> _row(CombatEvent e, Roster r, String session, DateTime? start) {
  final side = r.sideOf(e);
  final (ally, enemy) = switch (side) {
    'offense' => (e.actor, e.target),
    'defense' => (e.target, e.actor),
    'support' => (e.actor, null),
    _ => (null, null),
  };
  final t = e.observedAt;
  return {
    'session': session,
    'seq': e.seq,
    'hit_no': e.hitNo,
    'kind': e.kind,
    'time': t == null ? null : _formatTime(t),
    'elapsed': t == null || start == null
        ? null
        : (t.difference(start).inMilliseconds / 1000).toStringAsFixed(3),
    'side': side,
    'action_type': r.actionTypeOf(e),
    'ally': _blankToNull(ally),
    'enemy': _blankToNull(enemy),
    'action_ja': e.actionName,
    'stat': e.stat,
    'sc_type_ja': e.scType,
    'damage': e.damage,
    'heal': e.heal,
    'is_hit': e.isHit ? 1 : 0,
    'is_crit': e.isCrit ? 1 : 0,
    'is_miss': e.isMiss ? 1 : 0,
    'actor_name': _blankToNull(e.actor),
    'target_name': e.target,
    'actor_inferred': e.actorInferred ? 1 : 0,
    'log_window': e.line.window,
    'log_line': e.line.lineNo,
    'chat_mode': e.line.fields[0],
    'text': e.line.text,
  };
}

String? _blankToNull(String? s) => s == null || s.isEmpty ? null : s;

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// CSV の見出し行（BOM 付き）。BOM は Excel で文字化けさせないために付ける。
String csvHeader() => '\uFEFF${exportColumns.join(',')}\r\n';

/// CSV のデータ行（CRLF 区切り、見出しなし）。
String csvRows(List<Map<String, Object?>> rows) {
  final sb = StringBuffer();
  for (final row in rows) {
    sb
      ..write(exportColumns.map((c) => _csvCell(row[c])).join(','))
      ..write('\r\n');
  }
  return sb.toString();
}

/// CSV（UTF-8、BOM 付き、CRLF）。
String toCsv(List<Map<String, Object?>> rows) => csvHeader() + csvRows(rows);

String _csvCell(Object? v) {
  if (v == null) return '';
  final s = v.toString();
  if (s.contains(RegExp(r'[",\r\n]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// 生ログの列。`time` は検知した時刻（開始前から残っていた行は空欄）。
/// `log_window`・`log_line` は CSV の同名の列と同じ値で、この 2 列で CSV の行と突き合わせられる。
/// `msg` はメッセージの番号（10 進）。`f0`〜`f20` はログの行の 16 進フィールドをそのまま
/// （`f4` が `msg`、`f5` が `log_line` の 16 進）。
final rawLogColumns = List<String>.unmodifiable([
  'time',
  'log_window',
  'log_line',
  'msg',
  for (var i = 0; i < 21; i++) 'f$i',
  'text',
]);

/// 生ログの見出し行（BOM 付き、タブ区切り）。
String rawLogHeader() => '\uFEFF${rawLogColumns.join('\t')}\r\n';

/// 生ログのデータ行（タブ区切り、CRLF）。本文のタブと改行は空白に置き換える。
String rawLogRows(List<({LogLine line, DateTime? observedAt})> lines) {
  final sb = StringBuffer();
  for (final (:line, :observedAt) in lines) {
    sb
      ..write(
        [
          observedAt == null ? '' : _formatTime(observedAt),
          line.window,
          line.lineNo,
          line.messageId,
          ...line.fields,
          line.text.replaceAll(RegExp(r'[\t\r\n]'), ' '),
        ].join('\t'),
      )
      ..write('\r\n');
  }
  return sb.toString();
}

/// 監視中に取り出した事実を、読み込みのたびに CSV ファイルへ追記する。
///
/// 戦闘の行そのもの（1+2 をまとめて読むときは重複を除いた行）も、同じ名前の
/// `.lines.tsv`（[rawLogColumns]）へ追記する。こちらは [masker] に関係なく名前を置き換えない。
///
/// ファイルは最初に書く行が来たときに作る（`vana-log-YYYYMMDD-HHMMSS-w<ウィンドウ>.csv`。
/// 1 と 2 をまとめて読むときは `w12`）。
/// 書けなかった行（Excel で開いていてロックされているなど）は手元に残し、次の [add] で書き直す。
/// [masker] を渡すと、名前を置き換えてから書く。番号は初めて見た順に付け、書いた後は変えない。
class CsvRecorder {
  CsvRecorder({required this.directory, required this.session, this.masker, DateTime? now})
    : stamp = _stamp(now ?? DateTime.now());

  final Directory directory;
  final LogSession session;
  final NameMasker? masker;

  /// `session` 列の値とファイル名に使う日時。
  final String stamp;

  String get _base =>
      '${directory.path}${Platform.pathSeparator}vana-log-$stamp-w${session.window == bothWindows ? '12' : session.window}';

  late final File file = File('$_base.csv');

  /// 戦闘の行そのものを書くファイル。
  late final File linesFile = File('$_base.lines.tsv');

  final List<Map<String, Object?>> _pending = [];
  final List<({LogLine line, DateTime? observedAt})> _pendingLines = [];
  bool _created = false;
  bool _linesCreated = false;

  /// CSV に書いた行数。
  int written = 0;

  /// 生ログに書いた行数。
  int linesWritten = 0;

  /// まだ書けていない行数（CSV と生ログの合計）。
  int get pending => _pending.length + _pendingLines.length;

  /// 直近の書き込みの失敗。成功すると null に戻る。
  Object? error;

  /// [events] を行にして CSV に、[lines] を生ログに追記する。前回書けなかった行も一緒に書く。
  void add(
    List<CombatEvent> events, {
    List<({LogLine line, DateTime? observedAt})> lines = const [],
  }) {
    _pendingLines.addAll(lines);
    if (events.isNotEmpty) {
      var rows = toRows(
        events,
        session: stamp,
        roster: session.roster,
        startedAt: session.startedAt,
      );
      final m = masker;
      if (m != null) {
        m.forgetEnemies(session.roster);
        m.learn(events, session.roster);
        rows = m.maskRows(rows);
      }
      _pending.addAll(rows);
    }
    if (_pending.isEmpty && _pendingLines.isEmpty) return;
    Object? failed;
    if (_pending.isNotEmpty) {
      try {
        if (!_created) {
          directory.createSync(recursive: true);
          file.writeAsStringSync(csvHeader(), flush: true);
          _created = true;
        }
        file.writeAsStringSync(csvRows(_pending), mode: FileMode.append, flush: true);
        written += _pending.length;
        _pending.clear();
      } on FileSystemException catch (e) {
        failed = e;
      }
    }
    if (_pendingLines.isNotEmpty) {
      try {
        if (!_linesCreated) {
          directory.createSync(recursive: true);
          linesFile.writeAsStringSync(rawLogHeader(), flush: true);
          _linesCreated = true;
        }
        linesFile.writeAsStringSync(rawLogRows(_pendingLines), mode: FileMode.append, flush: true);
        linesWritten += _pendingLines.length;
        _pendingLines.clear();
      } on FileSystemException catch (e) {
        failed ??= e;
      }
    }
    error = failed;
  }

  static String _stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
}
