import 'package:flutter/material.dart';

/// 一排下划线式页签：悬停与选中都只染文字（主题色 + 加粗），选中额外画一小段下划线。
///
/// 首页顶栏的快捷分类与搜索页的分类页签都用它，保证两处视觉一致；[index] 传 -1 表示
/// 当前没有任何一项处于选中状态（例如首页选中的分类不在快捷分类里）。
class UnderlineTabStrip extends StatelessWidget {
  const UnderlineTabStrip({super.key, required this.labels, required this.index, required this.onSelected, this.spacing = 0, this.padding});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelected;

  /// 相邻两项之间额外的间距（每一项自身已带 10 的水平内边距）。
  final double spacing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0 && spacing > 0) SizedBox(width: spacing),
              UnderlineTab(label: labels[i], selected: i == index, onTap: () => onSelected(i)),
            ],
          ],
        ),
      );
}

/// [UnderlineTabStrip] 的单项，也可以单独使用。
class UnderlineTab extends StatefulWidget {
  const UnderlineTab({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<UnderlineTab> createState() => _UnderlineTabState();
}

class _UnderlineTabState extends State<UnderlineTab> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = widget.selected || _hovering;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: highlighted ? scheme.primary : scheme.onSurfaceVariant, fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400)),
              const SizedBox(height: 2),
              Container(height: 2, width: 18, decoration: BoxDecoration(color: widget.selected ? scheme.primary : Colors.transparent, borderRadius: BorderRadius.circular(1))),
            ],
          ),
        ),
      ),
    );
  }
}
