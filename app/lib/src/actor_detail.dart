import 'package:material_ui/material_ui.dart';
import 'package:vana_log_core/vana_log_core.dart';

/// 桁区切りの整数（1,234,567）。
String formatInt(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 割合（12.3%）。値がなければ「–」。
String formatPct(double? v) => v == null ? '–' : '${(v * 100).toStringAsFixed(1)}%';

String _avg(double? v) => v == null ? '–' : formatInt(v.round());

String _duration(Duration d) {
  final s = d.inSeconds;
  return s < 60 ? '$s 秒' : '${s ~/ 60} 分 ${(s % 60).toString().padLeft(2, '0')} 秒';
}

/// 味方 1 人分の詳細（攻撃の内訳・命中率・WS 別の集計）。
class ActorDetailPanel extends StatelessWidget {
  const ActorDetailPanel({
    super.key,
    required this.summary,
    required this.name,
    required this.total,
    required this.time,
    required this.onClose,
  });

  final ActorSummary summary;

  /// 画面に出す名前（名前を隠す設定なら置き換えた表記）。
  final String name;

  /// 表示している人の与ダメージの合計（割合の分母）。
  final int total;

  /// 戦闘時間。
  final Duration time;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final breakdown = [
      ('通常攻撃', s.meleeDamage),
      ('遠隔', s.rangedDamage),
      ('WS', s.wsDamage),
      ('魔法', s.spellDamage),
      ('MB', s.mbDamage),
      ('追加', s.addDamage),
      ('技連携', s.scDamage),
      ('その他', s.otherDamage),
    ].where((e) => e.$2 != 0).toList();
    final ws = s.wsByName.values.toList()..sort((a, b) => b.damage.compareTo(a.damage));

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(tooltip: '閉じる', onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _Section('総合', [
                  ('与ダメージ', formatInt(s.damage)),
                  ('割合', total == 0 ? '–' : formatPct(s.damage / total)),
                  ('DPS', s.dps == null ? '–' : s.dps!.toStringAsFixed(1)),
                  ('戦闘時間', _duration(time)),
                  if (s.heal > 0) ('回復', formatInt(s.heal)),
                ]),
                if (breakdown.isNotEmpty) ...[
                  _heading(context, '与ダメージの内訳'),
                  for (final (label, v) in breakdown)
                    _Bar(label: label, value: v, ratio: s.damage == 0 ? 0 : v / s.damage),
                ],
                _Section('通常攻撃', [
                  ('ダメージ', formatInt(s.meleeDamage)),
                  ('命中 / ミス', '${formatInt(s.meleeHits)} / ${formatInt(s.meleeMisses)}'),
                  ('命中率', formatPct(s.accuracy)),
                  ('クリティカル率', formatPct(s.critRate)),
                  ('平均 / 最大', '${_avg(s.meleeAverage)} / ${formatInt(s.meleeMax)}'),
                ]),
                if (s.rangedHits + s.rangedMisses > 0)
                  _Section('遠隔攻撃', [
                    ('ダメージ', formatInt(s.rangedDamage)),
                    ('命中 / ミス', '${formatInt(s.rangedHits)} / ${formatInt(s.rangedMisses)}'),
                    ('命中率', formatPct(s.rangedAccuracy)),
                    ('平均 / 最大', '${_avg(s.rangedAverage)} / ${formatInt(s.rangedMax)}'),
                  ]),
                _Section('WS', [
                  ('ダメージ', formatInt(s.wsDamage)),
                  ('命中 / ミス', '${formatInt(s.wsCount)} / ${formatInt(s.wsMisses)}'),
                  ('命中率', formatPct(s.wsAccuracy)),
                  ('平均 / 最大', '${_avg(s.wsAverage)} / ${formatInt(s.wsMax)}'),
                ]),
                if (ws.isNotEmpty) _WsTable(ws),
                _Section('魔法', [
                  ('ダメージ（MB を除く）', formatInt(s.spellDamage)),
                  ('MB ダメージ', formatInt(s.mbDamage)),
                  ('MB 回数 / 最大', '${formatInt(s.mbCount)} / ${formatInt(s.mbMax)}'),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 4),
  child: Text(text, style: Theme.of(context).textTheme.labelLarge),
);

class _Section extends StatelessWidget {
  const _Section(this.title, this.rows);

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final num = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, title),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                Text(value, style: num),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.ratio});

  final String label;
  final int value;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
              Text(
                '${formatInt(value)}（${formatPct(ratio)}）',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: ratio.clamp(0, 1).toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}

/// WS の種類ごとの集計。
class _WsTable extends StatelessWidget {
  const _WsTable(this.ws);

  final List<WsSummary> ws;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final head = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    // 数値の列は中身の幅に合わせて折り返さない。残りの幅を WS 名の列に回す。
    Widget cell(String t, TextStyle? style, {bool right = true}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Text(
        t,
        style: style,
        textAlign: right ? TextAlign.right : TextAlign.left,
        softWrap: !right,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Table(
        columnWidths: const {0: FlexColumnWidth()},
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            children: [
              cell('WS', head, right: false),
              cell('回数', head),
              cell('命中率', head),
              cell('平均', head),
              cell('最大', head),
            ],
          ),
          for (final w in ws)
            TableRow(
              children: [
                cell(w.name.isEmpty ? '（不明）' : w.name, small, right: false),
                cell(formatInt(w.count + w.misses), small),
                cell(formatPct(w.accuracy), small),
                cell(_avg(w.average), small),
                cell(formatInt(w.max), small),
              ],
            ),
        ],
      ),
    );
  }
}
