import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// 单选项分组：给「站点」这种既有 Hanime1 系、又有 AV 视频源的列表加一层分类，
/// 每组的标题可以点击折叠。
class OptionSettingGroup<T> {
  const OptionSettingGroup({required this.title, required this.options});

  final String title;
  final List<T> options;
}

/// 「内容少」的设置项统一走这个弹层，而不是 push 一个独立页面 ——
/// 为三五个单选项跳一次页面、看完再返回，代价比设置本身还大。
///
/// 形态照「代理」对话框：标题 → 说明 → 单选行（选中项右侧打勾）→ 取消 / 保存。
/// 返回选中的值；`null` 表示用户取消。选项本身还可以带一行说明
/// （硬件解码器 9 项、超分辨率 4 档都有），这是它比 `SettingsMenuItem`
/// 更合适的地方 —— 后者的菜单项只放得下纯文字。
///
/// [footer] 放在选项列表下方，用来放「和这份列表相关、但会离开本弹层」的操作，
/// 例如站点列表底部的「站点分组」。[footer] 里的按钮需要自己先 `Navigator.pop` 再做事。
Future<T?> showOptionSettingsDialog<T>({
  required BuildContext context,
  required String title,
  required T current,
  required String Function(T value) label,
  List<T> options = const [],
  List<OptionSettingGroup<T>>? groups,
  String? description,
  String Function(T value)? optionDescription,
  Widget? footer,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<T>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      return _OptionSettingsDialog<T>(
        title: title,
        description: description,
        current: current,
        options: options,
        groups: groups,
        label: label,
        optionDescription: optionDescription,
        footer: footer,
        cancelLabel: l10n.cancel,
        saveLabel: l10n.save,
        hintStyle: textTheme.bodySmall?.copyWith(color: scheme.outline),
      );
    },
  );
}

class _OptionSettingsDialog<T> extends StatefulWidget {
  const _OptionSettingsDialog({required this.title, required this.current, required this.options, required this.label, required this.cancelLabel, required this.saveLabel, this.groups, this.description, this.optionDescription, this.footer, this.hintStyle});

  final String title;
  final String? description;
  final T current;
  final List<T> options;
  final List<OptionSettingGroup<T>>? groups;
  final String Function(T value) label;
  final String Function(T value)? optionDescription;
  final Widget? footer;
  final String cancelLabel;
  final String saveLabel;
  final TextStyle? hintStyle;

  @override
  State<_OptionSettingsDialog<T>> createState() => _OptionSettingsDialogState<T>();
}

class _OptionSettingsDialogState<T> extends State<_OptionSettingsDialog<T>> {
  late var _value = widget.current;

  /// 折起来的那些分组（按标题记）。**默认全部展开** —— 保持原来「一眼看全」的观感，
  /// 想收起来时点分组标题即可。
  final _collapsed = <String>{};

  /// 没给分组时就是「一整段平铺的选项」。
  List<(String?, List<T>)> get _sections {
    final groups = widget.groups;
    if (groups == null || groups.isEmpty) return [(null, widget.options)];
    return [for (final group in groups) (group.title, group.options)];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.description != null && widget.description!.isNotEmpty) ...[
              Text(widget.description!, style: widget.hintStyle),
              const SizedBox(height: 4),
            ],
            for (final (groupTitle, options) in _sections) ...[
              if (groupTitle != null) _groupHeader(groupTitle, scheme),
              if (groupTitle == null || !_collapsed.contains(groupTitle))
                for (final option in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(widget.label(option)),
                    subtitle: widget.optionDescription == null ? null : Text(widget.optionDescription!(option)),
                    trailing: option == _value ? const Icon(Icons.check) : null,
                    onTap: () => setState(() => _value = option),
                  ),
            ],
            if (widget.footer != null) ...[
              const Divider(height: 20),
              widget.footer!,
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        FilledButton(onPressed: () => Navigator.pop(context, _value), child: Text(widget.saveLabel)),
      ],
    );
  }

  /// 分组标题：样式与设置页里的分组标题一致（`titleSmall` + 主色 + w600），
  /// 右侧一个箭头，点标题即折叠/展开。
  Widget _groupHeader(String title, ColorScheme scheme) {
    final collapsed = _collapsed.contains(title);
    return InkWell(
      onTap: () => setState(() => collapsed ? _collapsed.remove(title) : _collapsed.add(title)),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600))),
          Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: 18, color: scheme.primary),
        ]),
      ),
    );
  }
}
