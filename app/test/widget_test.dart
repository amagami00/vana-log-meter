import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:material_ui/material_ui.dart' show CheckboxMenuButton, OutlinedButton, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vana_log_core/vana_log_core.dart';
import 'package:vana_log_meter/main.dart';
import 'package:vana_log_meter/src/monitor.dart';
import 'package:vana_log_meter/src/multi_select.dart';
import 'package:vana_log_meter/src/settings.dart';

import '../../packages/vana_log_core/test/helpers.dart';

void main() {
  testWidgets('起動時はフォルダの選択を促す', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    expect(find.text('ログのフォルダを選んで開始してください'), findsOneWidget);
    expect(find.text('開始'), findsOneWidget);
    monitor.dispose();
  });

  testWidgets('開始するとログを読んで集計表を出す', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_widget_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。')))]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.inputDir = dir.path;
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('120'), findsWidgets);
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('すべての敵'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.text('集計をコピー'));
    await tester.pump();
    expect(copied, startsWith('名前\t与ダメージ'));
    expect(copied, contains('Alice\t120\t100.0%'));

    await tester.tap(find.text('ログ'));
    await tester.pumpAndSettle();
    expect(find.text('Aliceの攻撃→Goblinに、120ダメージ。'), findsOneWidget);
    expect(find.text('--:--:--'), findsOneWidget);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('集計表の行を押すとその人の詳細を出し、もう一度押すと閉じる', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_detail_');
    addTearDown(() => dir.deleteSync(recursive: true));
    var n = 0;
    List<int> l(String text, int mode, [int? msg]) =>
        lineBytes((mode: mode, msg: msg ?? ++n, line: ++n, body: sjis(text)));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([
        l('Aliceの攻撃→Goblinに、100ダメージ。', 0x14),
        l('Aliceの攻撃→Goblinに、ミス。', 0x14),
        l('Aliceは、Fooの構え。', 0x14),
        l('Aliceは、Fooを実行。', 0x14, 50),
        l('→Goblinに、1000ダメージ。', 0x14, 50),
      ]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.inputDir = dir.path;
    final monitor = LogMonitor();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(find.text('与ダメージの内訳'), findsNothing);

    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(find.text('与ダメージの内訳'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget); // 通常攻撃の命中 / ミス
    expect(find.text('1,000（90.9%）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Foo'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Foo'), findsOneWidget);

    await tester.tap(find.text('Alice').first);
    await tester.pump();
    expect(find.text('与ダメージの内訳'), findsNothing);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('敵と人をチェック付きメニューで複数選んで絞り込む', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_filter_');
    addTearDown(() => dir.deleteSync(recursive: true));
    var n = 0;
    List<int> l(String text, int mode) =>
        lineBytes((mode: mode, msg: ++n, line: n, body: sjis(text)));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([
        l('Aliceの攻撃→Goblinに、100ダメージ。', 0x14),
        l('Bobの攻撃→Orcに、30ダメージ。', 0x19),
        l('Carolの攻撃→Koboldに、7ダメージ。', 0x19),
      ]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.inputDir = dir.path;
    final monitor = LogMonitor();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();

    await tester.tap(find.text('すべての敵'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goblin（100）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orc（30）'));
    await tester.pumpAndSettle();
    // メニューは開いたまま。外を押して閉じる。
    await tester.tapAt(const Offset(1100, 700));
    await tester.pumpAndSettle();
    expect(find.text('Orc ほか 1 体'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsNothing);

    await tester.tap(find.text('すべての人'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Bob'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1100, 700));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsNWidgets(2)); // ボタンと表
    // 割合は表示している人の合計に対して出す（絞る前の Bob は 23.1%）。
    expect(find.text('23.1%'), findsNothing);
    expect(find.text('100.0%'), findsWidgets);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  test('設定を保存し、ジョブ表記の空欄は捨てる', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.load();
    s
      ..inputDir = '/x'
      ..window = 2
      ..jobs = {'A': '暗/侍', 'B': ' '};
    final again = await Settings.load();
    expect(again.inputDir, '/x');
    expect(again.window, 2);
    expect(again.jobs, {'A': '暗/侍'});
  });

  testWidgets('出力先を選んでいれば、読んだ事実を CSV に追記する', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_widget_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。')))]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings
      ..inputDir = dir.path
      ..outputDir = '${dir.path}/out'
      ..anonymize = true;
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();
    final r = monitor.recorder!;
    expect(r.written, 1);
    expect(find.textContaining('記録中: vana-log-'), findsOneWidget);
    final csv = r.file.readAsStringSync();
    expect(csv, contains('PC #1'));
    expect(csv, isNot(contains('Alice')));
    await tester.tap(find.text('ファイルを区切る'));
    await tester.pump();
    expect(monitor.recorder, isNull);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('書けなかった行は、停止や区切りの後も書けるまで書き直す', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_drain_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。')))]),
    );
    final out = Directory('${dir.path}/out');
    // 出力先の場所にファイルがあり、書けない（Excel で開いている状態の代わり）。
    File(out.path).writeAsStringSync('x');
    final monitor = LogMonitor()..recorderFactory = (s) => CsvRecorder(directory: out, session: s);
    monitor.start(dir.path, 1);
    final r = monitor.recorder!;
    expect(r.pending, 2); // CSV 1 行 + 戦闘の行 1 行
    monitor.stop();
    expect(monitor.recorder, isNull);
    expect(monitor.unsaved, 2);
    File(out.path).deleteSync();
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.unsaved, 0);
    expect(r.written, 1);
    expect(r.linesWritten, 1);
    expect(r.file.readAsStringSync(), contains('120'));
    expect(r.linesFile.readAsStringSync(), contains('Alice'));
    monitor.dispose();
  });
  testWidgets('ログのフォルダが無い・ログが無いときは画面で知らせる', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_folder_');
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.inputDir = '${dir.path}/gone';
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    expect(find.text('フォルダが見つかりません。選び直してください'), findsOneWidget);
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(monitor.running, isFalse);

    // 親のフォルダを選んだ（ログは中のフォルダにある）。
    Directory('${dir.path}/Alice').createSync();
    File('${dir.path}/Alice/1_0.log').writeAsBytesSync(logFile([]));
    settings.inputDir = dir.path;
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    expect(find.textContaining('中のフォルダを選んでください'), findsOneWidget);

    // 選んだウィンドウのログだけが無い。
    settings
      ..inputDir = '${dir.path}/Alice'
      ..window = 2;
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    expect(find.text('ウィンドウ 2 のログ（2_*.log）がありません'), findsOneWidget);
    settings.window = 1;
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    expect(find.textContaining('ありません'), findsNothing);
    monitor.dispose();
  });

  testWidgets('既定の 1+2 は両方のウィンドウを重複なく集計し、w12 の CSV に書く', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_both_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // メッセージ 1 は両方に、2 はウィンドウ 2 だけに出る。行番号はウィンドウごとに違う。
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 10, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。')))]),
    );
    File('${dir.path}/2_0.log').writeAsBytesSync(
      logFile([
        lineBytes((mode: 0x14, msg: 1, line: 5, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。'))),
        lineBytes((mode: 0x14, msg: 2, line: 6, body: sjis('Aliceの攻撃→Goblinに、30ダメージ。'))),
      ]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings
      ..inputDir = dir.path
      ..outputDir = '${dir.path}/out';
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(monitor.window, bothWindows);
    expect(monitor.session!.summary.summaries().single.damage, 150);
    expect(monitor.recorder!.written, 2);
    expect(monitor.recorder!.file.path, endsWith('-w12.csv'));
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ウィンドウを切り替えても読んだ行を CSV に書き直さない', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_window_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。')))]),
    );
    File('${dir.path}/2_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Orcに、70ダメージ。')))]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings
      ..inputDir = dir.path
      ..outputDir = '${dir.path}/out'
      ..window = 1;
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();
    final r1 = monitor.recorder!;
    expect(r1.written, 1);

    await tester.tap(find.text('ウィンドウ 2'));
    await tester.pump();
    final r2 = monitor.recorder!;
    expect(r2, isNot(same(r1)));
    expect(r2.written, 1);
    expect(r2.file.path, isNot(r1.file.path));

    // ウィンドウ 2 を表示している間に出たウィンドウ 1 の行も、ウィンドウ 1 の CSV に追記する。
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([
        lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。'))),
        lineBytes((mode: 0x14, msg: 2, line: 2, body: sjis('Aliceの攻撃→Goblinに、30ダメージ。'))),
      ]),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('ウィンドウ 1'));
    await tester.pump();
    expect(monitor.recorder, same(r1));
    expect(r1.written, 2);
    expect(r2.written, 1);
    expect(monitor.session!.summary.summaries().single.damage, 150);
    final outFiles = Directory('${dir.path}/out').listSync().map((f) => f.path);
    expect(outFiles.where((p) => p.endsWith('.csv')), hasLength(2));
    expect(outFiles.where((p) => p.endsWith('.lines.tsv')), hasLength(2));
    expect(r1.linesWritten, 2);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });
  test('絞り込みは大小・全角半角・ひらがなとカタカナを区別しない', () {
    expect(normalizeForSearch('ＧＯＢ'), normalizeForSearch('gob'));
    expect(normalizeForSearch('ごぶりん'), normalizeForSearch('ゴブリン'));
    expect(normalizeForSearch('Goblin').contains(normalizeForSearch('lin')), isTrue);
  });

  testWidgets('敵のメニューは入力した文字列で絞り込める', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_search_');
    addTearDown(() => dir.deleteSync(recursive: true));
    var n = 0;
    List<int> l(String text) => lineBytes((mode: 0x14, msg: ++n, line: n, body: sjis(text)));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([
        l('Aliceの攻撃→Goblinに、100ダメージ。'),
        l('Aliceの攻撃→Orcに、30ダメージ。'),
        l('Aliceの攻撃→Koboldに、7ダメージ。'),
      ]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.inputDir = dir.path;
    final monitor = LogMonitor();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    await tester.tap(find.text('開始'));
    await tester.pump();

    await tester.tap(find.text('すべての敵'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'GOB');
    await tester.pumpAndSettle();
    expect(find.text('Goblin（100）'), findsOneWidget);
    expect(find.text('Orc（30）'), findsNothing);
    await tester.tap(find.text('Goblin（100）'));
    await tester.pumpAndSettle();

    // 選んだ項目は、絞り込みに合わなくても残す。
    await tester.enterText(find.byType(TextField), 'ｏｒｃ');
    await tester.pumpAndSettle();
    expect(find.text('Goblin（100）'), findsOneWidget);
    expect(find.text('Orc（30）'), findsOneWidget);
    expect(find.text('Kobold（7）'), findsNothing);
    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Orc（30）'), findsNothing);

    // 閉じると入力は消え、次に開いたときはすべてを出す。
    await tester.tapAt(const Offset(1100, 700));
    await tester.pumpAndSettle();
    expect(find.text('Goblin'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Goblin'));
    await tester.pumpAndSettle();
    expect(find.text('Kobold（7）'), findsOneWidget);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });
}
