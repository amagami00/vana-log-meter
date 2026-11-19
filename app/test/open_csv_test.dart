import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show OutlinedButton;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vana_log_core/vana_log_core.dart';
import 'package:vana_log_meter/main.dart';
import 'package:vana_log_meter/src/monitor.dart';
import 'package:vana_log_meter/src/settings.dart';

import '../../packages/vana_log_core/test/helpers.dart';

/// ファイルの選択ダイアログの代わりに、決めたパスを返す。
class _FakeSelector extends FileSelectorPlatform {
  String? path;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => path == null ? null : XFile(path!);
}

void main() {
  testWidgets('停止中に CSV を開いて集計を出し、開始で監視の表示に戻る', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vana_log_open_csv_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/1_0.log').writeAsBytesSync(
      logFile([lineBytes((mode: 0x14, msg: 1, line: 1, body: sjis('Aliceの攻撃→Goblinに、120ダメージ。')))]),
    );
    final csv = File('${dir.path}/rec.csv')
      ..writeAsStringSync(
        toCsv(
          toRows([...CombatParser().add(logLine('Bobの攻撃→Orcに、77ダメージ。', line: 1))], session: 's1'),
        ),
      );
    File('${dir.path}/broken.csv').writeAsStringSync('a,b\r\n1,2\r\n');
    final selector = _FakeSelector();
    FileSelectorPlatform.instance = selector;

    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.inputDir = dir.path;
    final monitor = LogMonitor();
    await tester.pumpWidget(VanaLogMeterApp(settings: settings, monitor: monitor));
    OutlinedButton openButton() => tester.widget(
      find.ancestor(of: find.text('CSV を開く…'), matching: find.byType(OutlinedButton)),
    );

    // 監視中は開けない。
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(openButton().onPressed, isNull);
    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(openButton().onPressed, isNotNull);

    Future<void> open(String path) async {
      selector.path = path;
      await tester.tap(find.text('CSV を開く…'));
      await tester.pump();
      // compute（別の isolate）の完了を実時間で待つ。
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        if (find.textContaining('開けません').evaluate().isNotEmpty ||
            find.text('CSV を閉じる').evaluate().isNotEmpty) {
          break;
        }
      }
    }

    // このアプリの CSV でなければ知らせ、表示は変えない。
    await open('${dir.path}/broken.csv');
    expect(find.textContaining('開けません'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('CSV を閉じる'), findsNothing);

    await open(csv.path);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('77'), findsWidgets);
    expect(find.text('Alice'), findsNothing);
    expect(find.textContaining('CSV を表示中: rec.csv'), findsOneWidget);
    await tester.tap(find.text('ログ'));
    await tester.pumpAndSettle();
    expect(find.text('Bobの攻撃→Orcに、77ダメージ。'), findsOneWidget);
    await tester.tap(find.text('集計'));
    await tester.pumpAndSettle();

    // 開始すると CSV を閉じて監視の表示に戻る。
    await tester.tap(find.text('開始'));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('CSV を閉じる'), findsNothing);
    monitor.stop();
    await tester.pump(const Duration(seconds: 1));
  });
}
