import 'package:flutter/material.dart';

import '../../core/app_design_tokens.dart';
import '../../core/app_motion.dart';
import 'press_scale.dart';

/// 一排下划线式页签：悬停与选中都只染文字（主题色 + 加粗），选中额外画一小段下划线。
///
/// 首页顶栏的快捷分类、搜索页的分类页签、帐号页的分组都用它，保证几处视觉一致；
/// [index] 传 -1 表示当前没有任何一项处于选中状态（例如首页选中的分类不在快捷分类里）。
///
/// 两个刻意的做法（照同类客户端的顶栏页签）：
///  * 下划线是**一根**、宽度固定，切换时只沿 X 滑过去。每项各画一根的话，切换就是
///    「这根关掉、那根打开」，是硬跳；宽度跟着文字走的话又会忽胖忽瘦。
///  * 每个页签的插槽按**选中态的粗体**预留宽度，所以鼠标划过或选中都不会把邻居挤动
///    （粗体比常规体宽，不预留的话整排会轻微位移 —— 这也是那条注释的意思）。
class UnderlineTabStrip extends StatelessWidget {
  const UnderlineTabStrip({super.key, required this.labels, required this.index, required this.onSelected, this.spacing = 0, this.padding, this.center = false, this.selectedColor});

  /// 那根下划线的尺寸。设计稿 `tabUnderline` 是 73×3、圆角 1.5；
  /// 73 对应选中项（四字）整段文字宽，这里取 28×3 的居中短段 ——
  /// 保持「单根、只滑不形变」的既有规则（见类注释与测试），同时比原来的 18×2
  /// 更接近设计稿的分量感。
  static const double underlineWidth = 28;
  static const double underlineHeight = 3;

  /// 那根下划线的 key（测试用来量它的位置与宽度）。
  static const Key underlineKey = ValueKey('underline-tab-strip-underline');

  /// 每一项自己带的水平内边距。
  ///
  /// 设计稿页签文字的相邻间隙是 20px（`tab/latestUpload` 右缘 380 → `tab/hentai` 左缘 400）。
  /// 这里 padding 8 + spacing 4 + padding 8 = 20，正好对上；字号也用设计稿的 13
  /// （设计稿文字高 17px ≈ 13 号字），比原来的 14 更贴。
  static const double _horizontalPadding = 8;

  /// 文字与下划线之间的空隙。
  static const double _gap = 2;

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelected;

  /// 相邻两项之间额外的间距（每一项自身已带 [_horizontalPadding] 的水平内边距）。
  final double spacing;
  final EdgeInsetsGeometry? padding;

  /// 内容比可用宽度窄时是否居中（超出时仍可横向滚动）。
  final bool center;

  /// 选中态（文字强调色 + 下划线）的颜色。留空则用 `colorScheme.primary`。
  ///
  /// 设计稿的顶栏页签用的是固定的胭脂粉，不跟随用户主题色 —— 首页顶栏与搜索页
  /// 的分类页签都传 `AppDesignTokens.accent`；帐号页等其余地方留空即可。
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    // 量插槽宽度用的样式：与页签里那行文字完全同一份（含环境默认字体），
    // 只是固定成选中态的粗体 —— 这样插槽宽度不随选中/悬停变化。
    final boldStyle = DefaultTextStyle.of(context).style.merge(
      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final slots = <double>[
      for (final label in labels) _slotWidth(label, boldStyle, scaler),
    ];

    final strip = Stack(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0 && spacing > 0) SizedBox(width: spacing),
              UnderlineTab(
                label: labels[i],
                width: slots[i],
                selected: i == index,
                selectedColor: selectedColor,
                onTap: () => onSelected(i),
              ),
            ],
          ],
        ),
        if (index >= 0 && index < labels.length)
          AnimatedPositioned(
            // 只动 X：宽度与高度都不变，所以滑动过程中不会形变。
            duration: motionDuration(context, AppMotion.quick),
            curve: AppMotion.standardCurve,
            left: _slotStart(slots, index) + (slots[index] - underlineWidth) / 2,
            bottom: 0,
            child: Container(
              key: underlineKey,
              height: underlineHeight,
              width: underlineWidth,
              decoration: BoxDecoration(color: selectedColor ?? scheme.primary, borderRadius: BorderRadius.circular(underlineHeight / 2)),
            ),
          ),
      ],
    );

    if (!center) {
      return SingleChildScrollView(scrollDirection: Axis.horizontal, padding: padding, child: strip);
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Center(child: strip),
        ),
      ),
    );
  }

  /// 一个插槽的宽度：文字按**粗体**量出来的宽度 + 两侧内边距。
  static double _slotWidth(String label, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    return painter.width + _horizontalPadding * 2;
  }

  /// 第 [i] 项插槽的起点：前面所有插槽 + 它们之间的间距。
  double _slotStart(List<double> slots, int i) {
    var start = 0.0;
    for (var j = 0; j < i; j++) {
      start += slots[j] + spacing;
    }
    return start;
  }
}

/// [UnderlineTabStrip] 的单项，也可以单独使用。
class UnderlineTab extends StatefulWidget {
  const UnderlineTab({super.key, required this.label, required this.selected, required this.onTap, this.width, this.selectedColor});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 选中态的强调色。由 [UnderlineTabStrip] 传下来，留空则用 `colorScheme.primary`。
  final Color? selectedColor;

  /// 插槽宽度。由 [UnderlineTabStrip] 按选中态（粗体）的文字宽度算好传进来；
  /// 单独使用时留空则按自身内容宽度。
  final double? width;

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
      child: PressScale(child: InkWell(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: UnderlineTabStrip._horizontalPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: highlighted
                        ? (widget.selectedColor ?? scheme.primary)
                        : AppDesignTokens.inkSubtleOf(context),
                    fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: UnderlineTabStrip._gap),
                // 给那根共享下划线留位置（下划线本身画在 strip 的 Stack 里，不在页签里）。
                const SizedBox(height: UnderlineTabStrip.underlineHeight),
              ],
            ),
          ),
        ),
      )),
    );
  }
}
