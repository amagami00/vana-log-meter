import 'package:material_ui/material_ui.dart';

/// 選択肢 1 つ。[value] で選び、[label] をメニューに出す。
typedef MultiSelectOption = ({String value, String label});

/// 絞り込みの比較用に文字列をそろえる。英字の大小・全角と半角の英数字・ひらがなとカタカナを区別しない。
String normalizeForSearch(String s) => String.fromCharCodes(
  s.toLowerCase().runes.map((c) {
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角英数記号 → 半角
    if (c >= 0x41 && c <= 0x5A) c += 0x20; // 全角から来た大文字
    if (c >= 0x3041 && c <= 0x3096) c += 0x60; // ひらがな → カタカナ
    return c;
  }),
);

/// チェック付きのメニューで複数を選ぶボタン。何も選ばなければ「すべて」。
/// [searchable] なら、メニューの先頭に入力欄を出し、入力した文字列を含む項目だけを並べる。
class MultiSelectMenu extends StatefulWidget {
  const MultiSelectMenu({
    super.key,
    required this.allLabel,
    required this.unit,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.short,
    this.searchable = false,
  });

  /// 何も選んでいないときのボタンの表記（「すべての敵」など）。
  final String allLabel;

  /// 複数選んだときの数え方（「体」「人」）。
  final String unit;
  final List<MultiSelectOption> options;

  /// 選んでいる値。[options] に無い値は無視する。
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// ボタンに出す短い表記。省略すると [MultiSelectOption.label]。
  final String Function(String value)? short;

  /// 入力した文字列で項目を絞り込めるようにする。
  final bool searchable;

  @override
  State<MultiSelectMenu> createState() => _MultiSelectMenuState();
}

class _MultiSelectMenuState extends State<MultiSelectMenu> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<MultiSelectOption> get options => widget.options;
  Set<String> get selected => widget.selected;
  ValueChanged<Set<String>> get onChanged => widget.onChanged;
  String get allLabel => widget.allLabel;

  String _buttonLabel() {
    final chosen = [
      for (final o in options)
        if (selected.contains(o.value)) o,
    ];
    if (chosen.isEmpty) return allLabel;
    final first = widget.short?.call(chosen.first.value) ?? chosen.first.label;
    return chosen.length == 1 ? first : '$first ほか ${chosen.length - 1} ${widget.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final q = normalizeForSearch(_query.text.trim());
    // 選んでいる項目は、絞り込みに合わなくても隠さない（外せるように）。
    final shown = [
      for (final o in options)
        if (q.isEmpty || selected.contains(o.value) || normalizeForSearch(o.label).contains(q)) o,
    ];
    return MenuAnchor(
      // 閉じたら入力を消す。次に開いたときはすべてを出す。
      onClose: () => _query.text.isEmpty ? null : setState(_query.clear),
      menuChildren: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              width: 240,
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: '名前で絞り込む',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        MenuItemButton(
          onPressed: selected.isEmpty ? null : () => onChanged({}),
          child: Text('$allLabel（選択を解除）'),
        ),
        if (shown.isEmpty) const MenuItemButton(child: Text('一致する項目がありません')),
        for (final o in shown)
          CheckboxMenuButton(
            value: selected.contains(o.value),
            closeOnActivate: false,
            onChanged: (v) =>
                onChanged(v == true ? {...selected, o.value} : ({...selected}..remove(o.value))),
            child: Text(o.label),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: options.isEmpty
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.arrow_drop_down),
        iconAlignment: IconAlignment.end,
        label: Text(_buttonLabel()),
      ),
    );
  }
}
