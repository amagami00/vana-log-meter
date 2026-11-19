import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

void main() {
  final p = CombatParser();
  final events = [
    ...p.add(
      logLine('Aliceの攻撃→Goblinに、10ダメージ。', line: 1),
      observedAt: DateTime(2026, 11, 19, 12, 0, 0),
    ),
    ...p.add(
      logLine('Aliceの攻撃→Goblinに、ミス。', line: 2),
      observedAt: DateTime(2026, 11, 19, 12, 0, 1, 500),
    ),
  ];
  final rows = toRows(events, session: 's1');

  test('行の値', () {
    expect(rows, hasLength(2));
    expect(rows.first['ally'], 'Alice');
    expect(rows.first['enemy'], 'Goblin');
    expect(rows.first['time'], '2026-11-19 12:00:00');
    expect(rows.first['elapsed'], '0.000');
    expect(rows.last['elapsed'], '1.500');
    expect(rows.last['damage'], isNull);
    expect(rows.last['is_miss'], 1);
  });

  test('elapsed は記録を始めた時刻を 0 にする', () {
    final r = toRows(events, session: 's1', startedAt: DateTime(2026, 11, 19, 11, 59, 50));
    expect(r.map((x) => x['elapsed']), ['10.000', '11.500']);
  });

  test('CSV は BOM・CRLF 付きで、必要なセルを引用する', () {
    final csv = toCsv([
      {...rows.first, 'text': 'a,"b"'},
    ]);
    expect(csv.startsWith('﻿session,seq,'), isTrue);
    expect(csv.split('\r\n'), hasLength(3));
    expect(csv, contains('"a,""b"""'));
  });
}
