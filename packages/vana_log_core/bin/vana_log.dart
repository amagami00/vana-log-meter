import 'dart:io';

import 'package:args/args.dart';
import 'package:vana_log_core/vana_log_core.dart';

/// ログのディレクトリをまとめて読み、戦闘の事実を CSV に書き出す。
///
/// `dart run vana_log_core:vana_log --input <TEMP のディレクトリ> --output <出力先>`
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('input', abbr: 'i', help: 'ログのディレクトリ（USER/<id>/TEMP）', mandatory: true)
    ..addOption('output', abbr: 'o', help: '出力先のディレクトリ')
    ..addOption('window', abbr: 'w', allowed: ['1', '2'], defaultsTo: '1', help: '集計するログウィンドウ')
    ..addOption('session', help: 'session 列に入れるラベル（省略時は実行日時）')
    ..addFlag('stats', help: '読解率を表示する', defaultsTo: true)
    ..addFlag('show-unparsed', help: '読めなかった行を表示する')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }
  if (opts.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final input = Directory(opts.option('input')!);
  if (!input.existsSync()) {
    stderr.writeln('ディレクトリがありません: ${input.path}');
    exitCode = 66;
    return;
  }
  final window = int.parse(opts.option('window')!);
  final now = DateTime.now();
  final session = opts.option('session') ?? _stamp(now);

  final store = LogStore()..ingestDirectory(input);
  final lines = store.linesOf(window);
  final combat = CombatParser();
  final events = [for (final l in lines) ...combat.add(l)];

  if (opts.flag('stats')) {
    final c = combat.counts;
    final combatLines =
        c[LineCategory.event]! + c[LineCategory.context]! + c[LineCategory.unparsed]!;
    final pct = combatLines == 0
        ? 0
        : 100 * (combatLines - c[LineCategory.unparsed]!) / combatLines;
    stdout
      ..writeln(
        'ウィンドウ $window: ${lines.length} 行'
        '（書き込み途中 ${store.incomplete} 行・形式不正 ${store.malformed} 行は除外）',
      )
      ..writeln(
        '  戦闘の行 $combatLines 行のうち読めた行 ${pct.toStringAsFixed(1)}%'
        '（事実 ${c[LineCategory.event]} / 文脈 ${c[LineCategory.context]}'
        ' / 読めない ${c[LineCategory.unparsed]}）',
      )
      ..writeln('  戦闘以外 ${c[LineCategory.other]} 行')
      ..writeln('  取り出した事実 ${events.length} 件');
  }
  if (opts.flag('show-unparsed')) {
    for (final l in combat.unparsed) {
      stdout.writeln('  ? #${l.lineNo} mode=${l.fields[0]} ${l.text}');
    }
  }

  final outPath = opts.option('output');
  if (outPath == null) return;
  final out = Directory(outPath)..createSync(recursive: true);
  final rows = toRows(events, session: session);
  final base = '${out.path}${Platform.pathSeparator}vanalog-${_stamp(now)}-events';
  File('$base.csv').writeAsStringSync(toCsv(rows));
  stdout.writeln('書き出し: $base.csv');
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
