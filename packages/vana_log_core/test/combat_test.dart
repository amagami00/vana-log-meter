import 'package:test/test.dart';
import 'package:vana_log_core/vana_log_core.dart';

import 'helpers.dart';

/// 行を順に流し込み、出てきた事実をまとめて返す。
List<CombatEvent> run(CombatParser p, List<(String, int, int)> lines) {
  var n = 0;
  return [
    for (final (text, mode, msg) in lines) ...p.add(logLine(text, mode: mode, msg: msg, line: ++n)),
  ];
}

void main() {
  test('通常攻撃の命中とミス', () {
    final e = run(CombatParser(), [
      ('Aliceの攻撃→Goblinに、120ダメージ。', 0x14, 1),
      ('Aliceの攻撃→Goblinに、ミス。', 0x14, 2),
    ]);
    expect(e.map((x) => x.stat), ['melee', 'miss']);
    expect(e.first.actor, 'Alice');
    expect(e.first.target, 'Goblin');
    expect(e.first.damage, 120);
    expect(e.first.isHit, isTrue);
    expect(e.last.isMiss, isTrue);
  });

  test('クリティカルは見出し行と矢印行を同じメッセージ番号でつなぐ', () {
    final p = CombatParser();
    final e = run(p, [('Aliceの攻撃。クリティカル！', 0x14, 5), ('→Goblinに、300ダメージ。', 0x14, 5)]);
    expect(e, hasLength(1));
    expect(e.single.stat, 'crit');
    expect(e.single.isCrit, isTrue);
    expect(e.single.actor, 'Alice');
    expect(e.single.damage, 300);
    expect(p.counts[LineCategory.context], 1);
  });

  test('構えの後の実行はウェポンスキル、追加ダメージと技連携は行為者を推定する', () {
    final e = run(CombatParser(), [
      ('Aliceは、Fooの構え。', 0x14, 1),
      ('Aliceは、Fooを実行。', 0x14, 2),
      ('→Goblinに、5000ダメージ。', 0x14, 2),
      ('技連携・光→Goblinに、7000ダメージ。', 0x14, 3),
      ('Aliceの攻撃→Goblinに、100ダメージ。', 0x14, 4),
      ('追加ダメージ→Goblinに、30ダメージ。', 0x14, 5),
    ]);
    expect(e.map((x) => x.stat), ['ws', 'sc', 'melee', 'add']);
    expect(e[0].actionName, 'Foo');
    expect(e[0].damage, 5000);
    expect(e[1].scType, '光');
    expect(e[1].actor, 'Alice');
    expect(e[1].actorInferred, isTrue);
    expect(e[3].actor, 'Alice');
    expect(e[3].actorInferred, isTrue);
  });

  test('魔法の発動とマジックバースト', () {
    final e = run(CombatParser(), [
      ('Bobは、GoblinにBarを唱えた。', 0x19, 1),
      ('BobのBarが発動。', 0x19, 2),
      ('→マジックバースト！Goblinに、800ダメージ。', 0x19, 2),
    ]);
    expect(e.single.stat, 'mb');
    expect(e.single.actor, 'Bob');
    expect(e.single.actionName, 'Bar');
    expect(e.single.damage, 800);
  });

  test('範囲魔法の 2 体目以降は、メッセージ番号が増えても直前の行の文脈につなぐ', () {
    final p = CombatParser();
    final e = run(p, [
      ('AliceのBazが発動。', 0x14, 10),
      ('→Goblinに、600ダメージ。', 0x14, 10),
      ('→Orcに、610ダメージ。', 0x14, 11),
      ('→Koboldに、620ダメージ。', 0x14, 12),
      // 間に別の行が入ると、つながない。
      ('Bobの攻撃→Goblinに、ミス。', 0x19, 13),
      ('→Orcに、630ダメージ。', 0x14, 14),
      // モードが違えば、つながない。
      ('AliceのBazが発動。', 0x14, 15),
      ('→Goblinに、600ダメージ。', 0x14, 15),
      ('→Orcに、640ダメージ。', 0x1c, 16),
    ]);
    final hits = e.where((x) => (x.damage ?? 0) > 0);
    expect(hits.map((x) => (x.actor, x.target, x.damage)), [
      ('Alice', 'Goblin', 600),
      ('Alice', 'Orc', 610),
      ('Alice', 'Kobold', 620),
      ('Alice', 'Goblin', 600),
    ]);
    expect(hits.first.actionName, 'Baz');
    expect(p.counts[LineCategory.unparsed], 2);
  });

  test('反撃・回復・撃破', () {
    final e = run(CombatParser(), [
      ('Aliceの反撃効果→Goblinに、40ダメージ。', 0x14, 1),
      ('BobのBaz→AliceのHPが、250回復。', 0x19, 2),
      ('Aliceは、Goblinを倒した。', 0x14, 3),
    ]);
    expect(e.map((x) => x.stat), ['counter', 'heal', 'defeat']);
    expect(e[1].heal, 250);
    expect(e[1].target, 'Alice');
  });

  test('戦闘以外の行・効果切れ・チャットは事実にしない', () {
    final p = CombatParser();
    final e = run(p, [
      ('装備セット1を実行しました。', 0x14, 1),
      ('Aliceは、Fooの効果がきれた。', 0x14, 2),
      ('[12:34] hello', 0x05, 3),
    ]);
    expect(e, isEmpty);
    expect(p.counts[LineCategory.unparsed], 0);
  });

  test('Roster は味方と敵を推定し、side を決める', () {
    final ev = run(CombatParser(), [
      ('Aliceの攻撃→Goblinに、10ダメージ。', 0x14, 1),
      ('Goblinの攻撃→Aliceに、5ダメージ。', 0x20, 2),
    ]);
    final r = Roster()..addAll(ev);
    expect(r.isAlly('Alice'), isTrue);
    expect(r.isEnemy('Goblin'), isTrue);
    expect(ev.map(r.sideOf), ['offense', 'defense']);
  });

  test('Roster は、魔法だけで戦う自分と、自分が受けた攻撃の行動者を判定する', () {
    final ev = run(CombatParser(), [
      ('AliceのBazが発動。', 0x14, 1),
      ('→Goblinに、600ダメージ。', 0x14, 1),
      ('Orcの攻撃→Aliceに、9ダメージ。', 0x1c, 2),
      ('Orcの攻撃→Aliceに、ミス。', 0x1d, 3),
    ]);
    final r = Roster()..addAll(ev);
    expect(r.isAlly('Alice'), isTrue);
    expect(r.self, {'Alice'});
    expect(r.isEnemy('Goblin'), isTrue);
    expect(r.isEnemy('Orc'), isTrue);
    expect(ev.map(r.sideOf), ['offense', 'defense', 'defense']);
  });

  test('遠隔攻撃の命中とミス（本文の形は仮定）', () {
    final e = run(CombatParser(), [
      ('Aliceの遠隔攻撃→Goblinに、250ダメージ。', 0x14, 1),
      ('Aliceの遠隔攻撃→Goblinに、ミス。', 0x14, 2),
    ]);
    expect(e.map((x) => (x.actionType, x.stat)), [('ranged', 'ranged'), ('ranged', 'miss')]);
    expect(e.first.damage, 250);
    expect(Roster()..addAll(e), isA<Roster>().having((r) => r.isAlly('Alice'), 'ally', isTrue));
  });

  test('WS のミスは実行行の文脈につなぐ', () {
    final e = run(CombatParser(), [
      ('Aliceは、Fooの構え。', 0x14, 1),
      ('Aliceは、Fooを実行。', 0x14, 2),
      ('→Goblinに、ミス。', 0x14, 2),
    ]);
    expect(e.single.actionType, 'ws');
    expect(e.single.stat, 'miss');
    expect(e.single.actionName, 'Foo');
    expect(e.single.hitNo, 1);
  });
}
