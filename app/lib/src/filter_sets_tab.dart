import 'package:material_ui/material_ui.dart';
import 'package:vana_log_core/vana_log_core.dart';

/// フィルタセットのタブ。フォルダの `*.json` を一覧にし、セットごとに敵の絞り込みを ON/OFF する。
class FilterSetsTab extends StatelessWidget {
  const FilterSetsTab({
    super.key,
    required this.folder,
    required this.load,
    required this.selected,
    required this.present,
    required this.onReload,
    required this.onToggle,
  });

  /// 選んでいるフォルダ。未選択なら null。
  final String? folder;

  /// 読んだ結果。未選択なら null。
  final FilterSetLoad? load;

  /// 絞り込みで選んでいる敵（ログに出ていない名前も含む）。
  final Set<String> selected;

  /// ログに出ている敵。
  final Set<String> present;

  final VoidCallback onReload;
  final void Function(FilterSet set, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final l = load;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'ON にすると、セットの敵を「集計」タブの敵の絞り込みに加えます。'
                'まだログに出ていない敵は、出たときに絞り込みに入ります。',
                style: small,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: folder == null ? null : onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('読み直す'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (folder == null || l == null)
          Text('フィルタのフォルダを選んでください（*.json を読みます）', style: small)
        else ...[
          if (l.sets.isEmpty && l.errors.isEmpty)
            Text('このフォルダにフィルタセット（*.json）がありません', style: small),
          for (final set in l.sets) _tile(set, small),
          for (final e in l.errors)
            ListTile(
              dense: true,
              leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
              title: Text(e.file),
              subtitle: Text(e.message),
            ),
        ],
      ],
    );
  }

  Widget _tile(FilterSet set, TextStyle? small) {
    final on = set.enemies.every(selected.contains);
    final seen = set.enemies.where(present.contains).length;
    return SwitchListTile(
      value: on,
      onChanged: (v) => onToggle(set, v),
      title: Text(set.name),
      subtitle: Text(
        '${set.enemies.join('、')}\n'
        'ログに出ている敵: $seen / ${set.enemies.length} 体（${set.source}）',
        style: small,
      ),
      isThreeLine: true,
    );
  }
}
