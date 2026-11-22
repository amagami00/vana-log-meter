import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'actor_detail.dart';
import 'jobs_dialog.dart';
import 'monitor.dart';
import 'multi_select.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, required this.monitor});

  final Settings settings;
  final LogMonitor monitor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Settings get _s => widget.settings;
  LogMonitor get _m => widget.monitor;

  @override
  void initState() {
    super.initState();
    _m.addListener(_changed);
    _m.recorderFactory = _newRecorder;
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    _m.recorderFactory = null;
    super.dispose();
  }

  void _changed() => setState(() {});

  /// 集計を絞り込む敵と味方。空ならすべて。
  Set<String> _enemies = {};
  Set<String> _people = {};

  /// 詳細を開いている味方（実名）。null なら閉じている。
  String? _selected;

  /// 開いた CSV の集計。null なら監視の集計を出す。
  RecordedLog? _loaded;

  /// 開いている CSV の集計か、表示しているウィンドウの監視の集計。どちらもなければ null。
  _View? get _view {
    final l = _loaded;
    if (l != null) {
      return (
        summary: l.summary,
        roster: l.roster,
        // 名前を隠して書いた CSV の表記（「戦/侍 #1」など）は、名前として扱わない。
        names: l.names.where((n) => !isMaskedLabel(n)),
        lines: l.combatLines,
      );
    }
    final s = _m.session;
    if (s == null) return null;
    return (summary: s.summary, roster: s.roster, names: s.names, lines: s.combatLines);
  }

  /// 記録した CSV を開いて集計を出す。監視中は開けない。
  /// 複数のファイルは合算しない（開始のたびに残っている行を書き直すため、合算すると二重に数える）。
  Future<void> _openCsv() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
      initialDirectory: _s.outputDir,
      confirmButtonText: '開く',
    );
    if (file == null || _m.running) return;
    try {
      final log = await compute(_loadCsv, file.path);
      if (!mounted || _m.running) return;
      setState(() => _loaded = log);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開けません（${e.message}）')));
    }
  }

  void _closeCsv() => setState(() => _loaded = null);

  Future<void> _pickInput() async {
    final dir = await getDirectoryPath(initialDirectory: _s.inputDir, confirmButtonText: '選択');
    if (dir == null) return;
    setState(() => _s.inputDir = dir);
    if (_m.running) _m.start(dir, _s.window, includePast: _s.includePast);
  }

  Future<void> _pickOutput() async {
    final dir = await getDirectoryPath(initialDirectory: _s.outputDir, confirmButtonText: '選択');
    if (dir == null) return;
    setState(() => _s.outputDir = dir);
    _m.cut();
  }

  void _toggle() {
    final dir = _s.inputDir;
    if (_m.running) {
      _m.stop();
    } else if (dir != null) {
      _loaded = null;
      _m.start(dir, _s.window, includePast: _s.includePast);
    }
  }

  /// ログのフォルダの問題。問題がなければ null。[missing] はフォルダ自体が無いか。
  ({String message, bool missing})? _folderProblem() {
    final dir = _s.inputDir;
    if (dir == null) return null;
    final folder = Directory(dir);
    if (!folder.existsSync()) {
      return (message: 'フォルダが見つかりません。選び直してください', missing: true);
    }
    final List<FileSystemEntity> entries;
    try {
      entries = folder.listSync();
    } on FileSystemException catch (e) {
      return (message: 'フォルダを読めません: ${e.message}', missing: false);
    }
    final windows = {
      for (final e in entries)
        if (e is File) parseLogFileName(e.uri.pathSegments.last)?.window,
    };
    if (windows.contains(_s.window) || (_s.window == bothWindows && windows.isNotEmpty)) {
      return null;
    }
    if (windows.isNotEmpty) {
      return (message: 'ウィンドウ ${_s.window} のログ（${_s.window}_*.log）がありません', missing: false);
    }
    bool hasLogs(Directory d) {
      try {
        return d.listSync().any(
          (e) => e is File && parseLogFileName(e.uri.pathSegments.last) != null,
        );
      } on FileSystemException {
        return false;
      }
    }

    final nested = entries.whereType<Directory>().any(hasLogs);
    return (
      message: nested
          ? 'このフォルダにログ（1_*.log / 2_*.log）がありません。中のフォルダを選んでください'
          : 'このフォルダにログ（1_*.log / 2_*.log）がありません',
      missing: false,
    );
  }

  /// 新しい記録先の CSV。出力先が未選択か、記録しない設定なら null。
  CsvRecorder? _newRecorder(LogSession session, DateTime startedAt) {
    final out = _s.outputDir;
    if (!_s.exportCsv || out == null) return null;
    return CsvRecorder(
      directory: Directory(out),
      session: session,
      now: startedAt,
      // 画面と同じ番号になるよう、それまでに見た名前を先に登録する。
      masker: _s.anonymize
          ? (NameMasker(jobs: _s.jobs)..learnNames(session.names, session.roster))
          : null,
    );
  }

  /// 画面の名前の置き換え。名前を隠さないなら null。
  NameMasker? _masker() {
    final view = _view;
    if (!_s.anonymize || view == null) return null;
    return NameMasker(jobs: _s.jobs)..learnNames(view.names, view.roster);
  }

  Future<void> _copySummary(List<ActorSummary> summaries, NameMasker? masker) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: summaryToTsv(summaries, display: masker?.display)));
    messenger.showSnackBar(const SnackBar(content: Text('集計をコピーしました（表計算ソフトに貼れます）')));
  }

  Future<void> _editJobs() async {
    final view = _view;
    // 入力するのは味方（PC）だけ。敵や判定できない名前は出さない。
    final names = view == null ? <String>[] : view.names.where(view.roster.isAlly).toList();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => JobsDialog(names: names, jobs: _s.jobs),
    );
    if (result != null) {
      setState(() => _s.jobs = result);
      // 書いた行の表記は変えられないので、ここからは新しいファイルにする。
      if (_s.anonymize) _m.cut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final masker = _masker();
    final enemies = view?.summary.enemies() ?? <({String name, int damage})>[];
    final chosenEnemies = _enemies.intersection({for (final e in enemies) e.name});
    final scoped =
        view?.summary.summaries(enemies: chosenEnemies.isEmpty ? null : chosenEnemies) ??
        <ActorSummary>[];
    final chosenPeople = _people.intersection({for (final s in scoped) s.name});
    // 割合は表示している人の合計に対して出す（コピーも同じ）。
    final summaries = chosenPeople.isEmpty
        ? scoped
        : [
            for (final s in scoped)
              if (chosenPeople.contains(s.name)) s,
          ];
    final display = masker?.display ?? (String n) => n;
    // 絞り込みで表から消えた人の詳細は閉じる。
    final selected = summaries.where((s) => s.name == _selected).firstOrNull;
    final total = summaries.fold<int>(0, (a, s) => a + s.damage);
    final folderProblem = _folderProblem();
    final emptyMessage = _loaded != null
        ? 'この CSV に集計できる戦闘はありません'
        : view == null
        ? 'ログのフォルダを選んで開始してください'
        : 'まだ戦闘の記録がありません';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('vana-log-meter')),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DirRow(label: 'ログのフォルダ', path: _s.inputDir, onPick: _pickInput),
                  if (folderProblem != null)
                    Text(
                      folderProblem.message,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: bothWindows, label: Text('ウィンドウ 1+2')),
                          ButtonSegment(value: 1, label: Text('ウィンドウ 1')),
                          ButtonSegment(value: 2, label: Text('ウィンドウ 2')),
                        ],
                        selected: {_s.window},
                        onSelectionChanged: (v) {
                          setState(() => _s.window = v.first);
                          // 表示だけを切り替える。読んだ行を読み直したり、CSV を区切ったりしない。
                          _m.select(_s.window);
                        },
                      ),
                      FilledButton.icon(
                        // 監視中は止められるようにする。フォルダが無いときは開始させない。
                        onPressed:
                            _m.running ||
                                (_s.inputDir != null && !(folderProblem?.missing ?? false))
                            ? _toggle
                            : null,
                        icon: Icon(_m.running ? Icons.stop : Icons.play_arrow),
                        label: Text(_m.running ? '停止' : '開始'),
                      ),
                      Tooltip(
                        message: 'いまの集計を捨て、この後に出た行だけを数え直す',
                        child: OutlinedButton.icon(
                          onPressed: _m.session == null || _loaded != null ? null : _m.reset,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('ここから集計'),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: _s.includePast,
                            onChanged: (v) => setState(() => _s.includePast = v),
                          ),
                          const Text('開始時に過去のログも読む'),
                        ],
                      ),
                      Tooltip(
                        message: '記録した CSV を開いて集計を見る。停止中だけ使える',
                        child: OutlinedButton.icon(
                          onPressed: _m.running ? null : _openCsv,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('CSV を開く…'),
                        ),
                      ),
                      if (_loaded != null)
                        TextButton.icon(
                          onPressed: _closeCsv,
                          icon: const Icon(Icons.close),
                          label: const Text('CSV を閉じる'),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  _DirRow(
                    label: '出力先',
                    hint: 'CSV を記録するフォルダを選んでください',
                    path: _s.outputDir,
                    onPick: _pickOutput,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: _s.exportCsv,
                            onChanged: (v) {
                              setState(() => _s.exportCsv = v);
                              _m.cut();
                            },
                          ),
                          const Text('CSV に記録する'),
                        ],
                      ),
                      Tooltip(
                        message: 'いまの CSV を閉じ、この後の行は新しいファイルに書く',
                        child: OutlinedButton.icon(
                          onPressed: _m.recorder == null ? null : _m.cut,
                          icon: const Icon(Icons.content_cut),
                          label: const Text('ファイルを区切る'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: _s.anonymize,
                            onChanged: (v) {
                              setState(() => _s.anonymize = v);
                              _m.cut();
                            },
                          ),
                          const Text('名前を隠す'),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: _editJobs,
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('ジョブ表記'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _RecordStatus(monitor: _m, settings: _s),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: '集計'),
                Tab(text: 'ログ'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            const Text('敵'),
                            const SizedBox(width: 12),
                            MultiSelectMenu(
                              allLabel: 'すべての敵',
                              unit: '体',
                              options: [
                                for (final e in enemies)
                                  (
                                    value: e.name,
                                    label: '${e.name}（${_SummaryTable._n(e.damage)}）',
                                  ),
                              ],
                              short: (n) => n,
                              searchable: true,
                              selected: chosenEnemies,
                              onChanged: (v) => setState(() => _enemies = v),
                            ),
                            const SizedBox(width: 16),
                            const Text('人'),
                            const SizedBox(width: 12),
                            MultiSelectMenu(
                              allLabel: 'すべての人',
                              unit: '人',
                              options: [
                                for (final s in scoped) (value: s.name, label: display(s.name)),
                              ],
                              selected: chosenPeople,
                              onChanged: (v) => setState(() => _people = v),
                            ),
                            if (chosenEnemies.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  '回復はどの敵にも属さないため、絞り込み中は数えない',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                            const Spacer(),
                            TextButton.icon(
                              onPressed: summaries.isEmpty
                                  ? null
                                  : () => _copySummary(summaries, masker),
                              icon: const Icon(Icons.copy),
                              label: const Text('集計をコピー'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: summaries.isEmpty
                            ? Center(child: Text(emptyMessage))
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _SummaryTable(
                                      summaries: summaries,
                                      display: display,
                                      selected: selected?.name,
                                      onSelect: (n) =>
                                          setState(() => _selected = n == _selected ? null : n),
                                    ),
                                  ),
                                  if (selected != null) ...[
                                    const VerticalDivider(width: 1),
                                    SizedBox(
                                      width: 340,
                                      child: ActorDetailPanel(
                                        summary: selected,
                                        name: display(selected.name),
                                        total: total,
                                        time: view!.summary.timeOf(
                                          enemies: chosenEnemies.isEmpty ? null : chosenEnemies,
                                        ),
                                        onClose: () => setState(() => _selected = null),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                  _LogView(lines: view?.lines ?? const [], empty: emptyMessage, masker: masker),
                ],
              ),
            ),
            _StatusBar(monitor: _m, loaded: _loaded),
          ],
        ),
      ),
    );
  }
}

/// [path] の CSV を読んで集計する（別の isolate で動かす）。読めなければ [FormatException] を投げる。
RecordedLog _loadCsv(String path) {
  final log = RecordedLog();
  try {
    log.addCsv(File(path).readAsStringSync(), source: File(path).uri.pathSegments.last);
  } on FileSystemException catch (e) {
    throw FormatException(e.message);
  }
  return log;
}

/// 画面に出す集計の元（監視中のウィンドウか、開いた CSV）。
typedef _View = ({
  SummaryAccumulator summary,
  Roster roster,
  Iterable<String> names,
  Iterable<({LogLine line, DateTime? observedAt})> lines,
});

class _DirRow extends StatelessWidget {
  const _DirRow({required this.label, this.hint = '未選択', required this.path, required this.onPick});

  final String label;
  final String hint;
  final String? path;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: theme.textTheme.labelLarge)),
        Expanded(
          child: Text(
            path ?? hint,
            overflow: TextOverflow.ellipsis,
            style: path == null
                ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)
                : theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onPick, child: const Text('選択…')),
      ],
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({
    required this.summaries,
    required this.display,
    required this.selected,
    required this.onSelect,
  });

  final List<ActorSummary> summaries;
  final String Function(String) display;

  /// 詳細を開いている人（実名）。
  final String? selected;

  /// 行を押したとき（実名を渡す）。
  final ValueChanged<String> onSelect;

  static String _n(int v) => formatInt(v);
  static String _pct(double? v) => formatPct(v);

  @override
  Widget build(BuildContext context) {
    final total = summaries.fold<int>(0, (a, s) => a + s.damage);
    DataCell num(String s) => DataCell(Text(s));
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          showCheckboxColumn: false,
          columns: const [
            DataColumn(
              label: Tooltip(message: '行を押すと、その人の詳細を右に出す', child: Text('名前')),
            ),
            DataColumn(label: Text('与ダメージ'), numeric: true),
            DataColumn(label: Text('割合'), numeric: true),
            DataColumn(
              label: Tooltip(
                message:
                    '戦闘時間 1 秒あたりの与ダメージ。開始後に読んだ行だけで計算し、'
                    '10 秒を超える空白は戦闘時間に入れない',
                child: Text('DPS'),
              ),
              numeric: true,
            ),
            DataColumn(label: Text('通常攻撃'), numeric: true),
            DataColumn(label: Text('命中率'), numeric: true),
            DataColumn(label: Text('クリ率'), numeric: true),
            DataColumn(label: Text('WS 回数'), numeric: true),
            DataColumn(label: Text('WS 平均'), numeric: true),
            DataColumn(label: Text('WS 最大'), numeric: true),
            DataColumn(label: Text('魔法'), numeric: true),
            DataColumn(label: Text('MB'), numeric: true),
            DataColumn(label: Text('MB 回数'), numeric: true),
            DataColumn(label: Text('MB 最大'), numeric: true),
            DataColumn(label: Text('追加'), numeric: true),
            DataColumn(label: Text('技連携'), numeric: true),
            DataColumn(label: Text('回復'), numeric: true),
          ],
          rows: [
            for (final s in summaries)
              DataRow(
                selected: s.name == selected,
                onSelectChanged: (_) => onSelect(s.name),
                cells: [
                  DataCell(Text(display(s.name))),
                  num(_n(s.damage)),
                  num(total == 0 ? '–' : _pct(s.damage / total)),
                  num(s.dps == null ? '–' : s.dps!.toStringAsFixed(1)),
                  num(_n(s.meleeDamage)),
                  num(_pct(s.accuracy)),
                  num(_pct(s.critRate)),
                  num(_n(s.wsCount)),
                  num(s.wsAverage == null ? '–' : _n(s.wsAverage!.round())),
                  num(_n(s.wsMax)),
                  num(_n(s.spellDamage)),
                  num(_n(s.mbDamage)),
                  num(_n(s.mbCount)),
                  num(_n(s.mbMax)),
                  num(_n(s.addDamage)),
                  num(_n(s.scDamage)),
                  num(_n(s.heal)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// CSV の記録の状態（書いているファイル・行数・書き込みの失敗）。
class _RecordStatus extends StatelessWidget {
  const _RecordStatus({required this.monitor, required this.settings});

  final LogMonitor monitor;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = monitor.recorder;
    final String text;
    var isError = false;
    if (!settings.exportCsv) {
      text = 'CSV には記録しない';
    } else if (settings.outputDir == null) {
      text = '出力先が未選択のため、CSV には記録していません';
      isError = monitor.running;
    } else if (r == null) {
      text = monitor.running ? '戦闘の行が出たら CSV に記録を始めます' : '開始すると CSV に記録します';
    } else if (r.error != null) {
      text = '書き込めません（${r.pending} 行を保留中。ファイルを開いていたら閉じてください）: ${r.error}';
      isError = true;
    } else {
      final name = r.file.uri.pathSegments.last;
      text = '記録中: $name（事実 ${r.written} 行・戦闘の行 ${r.linesWritten} 行）';
    }
    final unsaved = monitor.unsaved;
    return Text(
      unsaved == 0 ? text : '$text／前のファイルに $unsaved 行を保留中（閉じると書きます）',
      style: theme.textTheme.bodySmall?.copyWith(
        color: isError ? theme.colorScheme.error : theme.colorScheme.outline,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.monitor, required this.loaded});

  final LogMonitor monitor;
  final RecordedLog? loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = monitor.session;
    final l = loaded;
    final parts = l != null
        ? ['CSV を表示中: ${l.sources.join('、')}', '事実 ${l.eventCount} 件']
        : <String>[
            monitor.running ? '監視中' : '停止中',
            if (s != null) ...[
              '事実 ${s.eventCount} 件',
              if (s.readability != null) '読めた行 ${s.readability!.toStringAsFixed(1)}%',
              if (s.unparsedCount > 0) '読めない行 ${s.unparsedCount}',
              if (s.lastUpdated != null) '最終更新 ${_time(s.lastUpdated!)}',
            ],
          ];
    // CSV の表示中は、停止前の監視のエラーを出さない。
    final error = l == null ? monitor.error : null;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          error ?? parts.join('　'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: error == null ? null : theme.colorScheme.error,
          ),
        ),
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

/// 戦闘の行をそのまま並べる（チャットなどは出さない）。新しい行が下に増え、最下部にいる間は自動で追従する。
class _LogView extends StatelessWidget {
  const _LogView({required this.lines, required this.empty, required this.masker});

  final Iterable<({LogLine line, DateTime? observedAt})> lines;

  /// 行がないときの案内。
  final String empty;
  final NameMasker? masker;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return Center(child: Text(empty));
    final theme = Theme.of(context);
    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SelectionArea(
      child: ListView.builder(
        // 下端を起点にし、新しい行が増えても最下部に留まる。
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final l = lines.elementAt(lines.length - 1 - i);
          final t = l.observedAt;
          final text = masker?.maskText(l.line.text) ?? l.line.text;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(t == null ? '--:--:--' : _StatusBar._time(t), style: timeStyle),
                ),
                Expanded(child: Text(text)),
              ],
            ),
          );
        },
      ),
    );
  }
}
