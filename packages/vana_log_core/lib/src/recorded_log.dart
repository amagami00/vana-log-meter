import 'package:csv/csv.dart';

import 'combat.dart';
import 'log_file.dart';
import 'roster.dart';
import 'summary.dart';

/// 読み戻しに必要な列。
const _requiredColumns = [
  'session',
  'seq',
  'hit_no',
  'kind',
  'time',
  'elapsed',
  'side',
  'action_type',
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

final _maskedLabel = RegExp(r' #\d+$');

/// `NameMasker` が付けた表記（「戦/侍 #1」「PC #1」）なら true。
/// ゲームのキャラクター名には空白が入らないため、本物の名前とは重ならない。
bool isMaskedLabel(String name) => _maskedLabel.hasMatch(name);

/// 記録した CSV（`CsvRecorder` の出力）を読み戻し、監視中と同じ形で集計する。
///
/// 敵味方は記録した時点の判定（`side`・`enemy` 列）をそのまま使う。読み戻した後の名簿で
/// 判定し直すと、監視中に画面で見た数字とずれるため。複数のファイルを [addCsv] すると合算する
/// （同じ行が両方のファイルにあれば二重に数える）。
class RecordedLog {
  final SummaryAccumulator summary = SummaryAccumulator();

  /// 記録から分かる敵味方（`side` 列から組み立てる）。
  final Roster roster = Roster();

  /// 事実に出てきた名前（行動者・対象）。初めて見た順。
  final Set<String> names = {};

  /// 戦闘の行（同じ行から出た事実は 1 行にまとめる）。読んだ順。
  final List<({LogLine line, DateTime? observedAt})> combatLines = [];

  /// 読んだファイルの名前。
  final List<String> sources = [];

  int get eventCount => summary.count;

  static final _csv = Csv(autoDetect: false);

  /// CSV の中身を読んで集計に加える。このアプリの CSV でなければ [FormatException] を投げ、
  /// 集計は変えない。
  void addCsv(String content, {required String source}) {
    final table = _csv.decode(content);
    if (table.isEmpty) throw const FormatException('CSV が空です');
    final header = [for (final c in table.first) '$c'.trim()];
    final index = {for (var i = 0; i < header.length; i++) header[i]: i};
    final missing = _requiredColumns.where((c) => !index.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      throw FormatException('vana-log-meter の CSV ではありません（${missing.join('・')} の列がありません）');
    }

    final rows = <_Row>[];
    for (var r = 1; r < table.length; r++) {
      final cells = table[r];
      String? cell(String c) {
        final i = index[c]!;
        final v = i < cells.length ? '${cells[i]}' : '';
        return v.isEmpty ? null : v;
      }

      try {
        rows.add(_Row.parse(cell));
      } on FormatException catch (e) {
        throw FormatException('${r + 1} 行目を読めません: ${e.message}');
      }
    }

    // `elapsed`（ミリ秒）で時刻を復元する。`time` は秒未満を切り捨てているので、起点の推定にだけ使う。
    // 起点は記録ファイル（session 列）ごとに、`time − elapsed` の最大値（真の起点に最も近い値）にする。
    final origins = <String, DateTime>{};
    for (final row in rows) {
      final t = row.time;
      final el = row.elapsed;
      if (t == null || el == null) continue;
      final o = t.subtract(el);
      final cur = origins[row.session];
      if (cur == null || o.isAfter(cur)) origins[row.session] = o;
    }

    for (final row in rows) {
      final o = origins[row.session];
      row.event.observedAt = o == null || row.elapsed == null ? null : o.add(row.elapsed!);
    }
    // 監視中と同じく、1 回の読み込み（同じ session・elapsed の行）ごとに名簿を更新してから集計する。
    String? lastKey;
    for (var i = 0; i < rows.length;) {
      var j = i + 1;
      while (j < rows.length &&
          rows[j].session == rows[i].session &&
          rows[j].elapsed == rows[i].elapsed) {
        j++;
      }
      final batch = rows.sublist(i, j);
      batch.forEach(_learnSide);
      for (final row in batch) {
        final e = row.event;
        summary.addJudged(e, side: row.side, enemy: row.enemy, isEnemy: roster.isEnemy);
        if (e.actor.isNotEmpty) names.add(e.actor);
        if (e.target.isNotEmpty) names.add(e.target);
        final key = '${row.session}/${e.line.window}/${e.line.lineNo}';
        if (key != lastKey) combatLines.add((line: e.line, observedAt: e.observedAt));
        lastKey = key;
      }
      i = j;
    }
    sources.add(source);
  }

  void _learnSide(_Row row) {
    final e = row.event;
    switch (row.side) {
      case 'offense':
        if (e.actor.isNotEmpty) roster.allies.add(e.actor);
        roster.enemies.add(e.target);
      case 'defense':
        if (e.actor.isNotEmpty) roster.enemies.add(e.actor);
        roster.allies.add(e.target);
      case 'support':
        roster.allies
          ..add(e.actor)
          ..add(e.target);
    }
    roster.enemies.removeAll(roster.allies);
  }
}

class _Row {
  _Row(this.session, this.side, this.enemy, this.time, this.elapsed, this.event);

  final String session;
  final String side;
  final String? enemy;
  final DateTime? time;
  final Duration? elapsed;
  final CombatEvent event;

  static _Row parse(String? Function(String column) cell) {
    String req(String c) => cell(c) ?? (throw FormatException('$c が空です'));
    int intOf(String c) => int.tryParse(req(c)) ?? (throw FormatException('$c が数値ではありません'));
    int? optInt(String c) {
      final v = cell(c);
      if (v == null) return null;
      return int.tryParse(v) ?? (throw FormatException('$c が数値ではありません'));
    }

    bool flag(String c) => cell(c) == '1';
    final mode = req('chat_mode');
    if (int.tryParse(mode, radix: 16) == null) {
      throw const FormatException('chat_mode が 16 進ではありません');
    }
    final seq = intOf('seq');
    final lineNo = intOf('log_line');
    String h(int v) => v.toRadixString(16).padLeft(8, '0');
    final line = LogLine(
      window: intOf('log_window'),
      fileIndex: 0,
      // ログの行頭 21 フィールドのうち、CSV に残る値（種別・メッセージ番号・行番号）だけを埋める。
      fields: [mode, '00', '00', '00', h(seq), h(lineNo), for (var i = 0; i < 15; i++) '00'],
      text: cell('text') ?? '',
    );
    final elapsed = cell('elapsed');
    final ms = elapsed == null ? null : double.tryParse(elapsed);
    if (elapsed != null && ms == null) throw const FormatException('elapsed が数値ではありません');
    final time = cell('time');
    final parsedTime = time == null ? null : DateTime.tryParse(time.replaceFirst(' ', 'T'));
    if (time != null && parsedTime == null) throw const FormatException('time を読めません');
    return _Row(
      req('session'),
      cell('side') ?? 'other',
      cell('enemy'),
      parsedTime,
      ms == null ? null : Duration(milliseconds: (ms * 1000).round()),
      CombatEvent(
        line: line,
        seq: seq,
        hitNo: intOf('hit_no'),
        kind: req('kind'),
        actor: cell('actor_name') ?? '',
        target: cell('target_name') ?? '',
        actionType: req('action_type'),
        stat: req('stat'),
        actionName: cell('action_ja'),
        scType: cell('sc_type_ja'),
        damage: optInt('damage'),
        heal: optInt('heal'),
        isHit: flag('is_hit'),
        isCrit: flag('is_crit'),
        isMiss: flag('is_miss'),
        actorInferred: flag('actor_inferred'),
      ),
    );
  }
}
