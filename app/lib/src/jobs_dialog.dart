import 'package:material_ui/material_ui.dart';

/// 名前ごとにジョブ表記（「戦/侍」など）を入力する。空欄の名前は「PC #n」になる。
class JobsDialog extends StatefulWidget {
  const JobsDialog({super.key, required this.names, required this.jobs});

  /// 置き換えの対象になる名前（ログに登場した、敵でない名前）。
  final List<String> names;
  final Map<String, String> jobs;

  @override
  State<JobsDialog> createState() => _JobsDialogState();
}

class _JobsDialogState extends State<JobsDialog> {
  late final Map<String, TextEditingController> _c;

  @override
  void initState() {
    super.initState();
    // 保存済みでも今回のログに出てこない名前は残しておく。
    final names = {...widget.names, ...widget.jobs.keys};
    _c = {for (final n in names) n: TextEditingController(text: widget.jobs[n] ?? '')};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ジョブ表記'),
      content: SizedBox(
        width: 420,
        child: _c.isEmpty
            ? const Text('ログを読むと、ここに名前が並びます。')
            : ListView(
                shrinkWrap: true,
                children: [
                  const Text('「名前を隠す」をオンにすると、入力したジョブ表記と番号で画面に表示します（CSV は名前のまま）。'),
                  const SizedBox(height: 12),
                  for (final e in _c.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: e.value,
                              decoration: const InputDecoration(hintText: '例: 戦/侍', isDense: true),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, {for (final e in _c.entries) e.key: e.value.text}),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
