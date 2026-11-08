import 'package:flutter/material.dart';

import '../../core/app_design_tokens.dart';
import '../../core/app_radius.dart';
import '../shared/glass/glass_panel.dart';
import '../shared/press_scale.dart';
import 'settings_glass_controls.dart';

/// Settings list primitives.
///
/// Layout follows the flat, grouped style: every tile is its own surface with a
/// small gap between rows, only the outermost corners of a group get the large
/// radius. Content is centred with a maximum width so settings do not stretch
/// across a wide desktop window.
const double settingsListMaxWidth = 1000;
// 参考 morrow（明隙）：大圆角 + 更宽的卡片间距，靠"一块块浮起来的卡片"分区。
// 整组一张卡，圆角统一走 `_cardRadius`。
const double _cardRadius = AppRadius.lg;

/// Scrollable list of [SettingsSection]s.
class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    required this.sections,
    this.contentPadding,
    this.shrinkWrap = false,
    this.physics,
    this.maxWidth = settingsListMaxWidth,
  });

  final List<Widget> sections;
  final EdgeInsetsGeometry? contentPadding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: shrinkWrap,
    physics: physics,
    padding: contentPadding ?? const EdgeInsets.symmetric(vertical: 12),
    itemCount: sections.length,
    itemBuilder: (context, index) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: sections[index],
      ),
    ),
  );
}

/// A titled group of tiles.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.title,
    this.bottomInfo,
    this.margin,
    this.rowPadding = 2,
  });

  final List<Widget> tiles;
  final Widget? title;
  final Widget? bottomInfo;
  final EdgeInsetsGeometry? margin;

  /// 行内上下留白（见 [SettingsTile.rowPadding]）：
  /// 设计稿主题页 40 行高传 4，布局页 56 行高传 10。
  final double rowPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      // 设计稿的白卡实测在 x424~1251，而内容区左边界是 385 —— 左右各留 39 / 29。
      // 原来写 16/16：卡片比设计稿宽出一大截，右边缘几乎顶到窗口。
      padding: margin ?? const EdgeInsets.fromLTRB(39, 0, 29, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题**放进卡片内部**（设计稿：`配色方案` / `外观与显示` 都在白卡里面、
          // 与色块/开关同一张卡，而不是卡外单独一行灰字）。
          // 之前标题画在 `_SplitListGroup` 外面，卡片上方就多出一条独立文字，
          // 既多占了一行高度，也和设计稿「一张卡包含标题 + 条目」的观感对不上。
          _SplitListGroup(
            rowPadding: rowPadding,
            title: title == null
                ? null
                : Semantics(
                    header: true,
                    child: DefaultTextStyle.merge(
                      // 设计稿的卡片标题是 13 号粗体墨色（`setTitle`）。
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      child: title!,
                    ),
                  ),
            // 把 rowPadding 往下传：`SettingsTile` 自己不去分析
            // 「这个页面该多松」，统一由所在分组决定（主题页 4、布局页 10）。
            children: [
              for (final tile in tiles)
                _RowPaddingScope(rowPadding: rowPadding, child: tile),
            ],
          ),
          if (bottomInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DefaultTextStyle.merge(
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                child: bottomInfo!,
              ),
            ),
        ],
      ),
    );
  }
}

/// A single settings row.
/// 行内上下留白的传递：`SettingsSection.rowPadding` → 每个 tile。
///
/// 用 `InheritedWidget` 而不是给 30 多个调用点各加一个参数：
/// 松紧是**整页**的属性（设计稿主题页 40 行高、布局页 56），
/// 在分组上声明一次就够，不该让每个条目自己知道。
class _RowPaddingScope extends InheritedWidget {
  const _RowPaddingScope({required this.rowPadding, required super.child});

  final double rowPadding;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_RowPaddingScope>()
          ?.rowPadding ??
      // 没有 scope 时（比如单独测试一个 tile）用设计稿的**紧凑档 2**：
      // 主题页（8 行满页）就是这个密度，也是绝大多数设置页的样子。
      2;

  @override
  bool updateShouldNotify(_RowPaddingScope oldWidget) =>
      oldWidget.rowPadding != rowPadding;
}

/// A single settings row.
class SettingsTile<T> extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.leading,
    this.description,
    this.value,
    this.trailing,
    this.bottom,
    this.onPressed,
    this.enabled = true,
    this.rowPadding = 2,
  }) : initialValue = null,
       onToggle = null,
       toggled = null,
       radioValue = null,
       groupValue = null,
       onChanged = null;

  const SettingsTile.navigation({
    super.key,
    required this.title,
    this.leading,
    this.description,
    this.value,
    this.onPressed,
    this.enabled = true,
    this.rowPadding = 2,
  }) : trailing = null,
       bottom = null,
       initialValue = null,
       onToggle = null,
       toggled = null,
       radioValue = null,
       groupValue = null,
       onChanged = null;

  /// Row taps report a null value; the switch itself reports the new one.
  const SettingsTile.switchTile({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onToggle,
    this.toggled,
    this.leading,
    this.description,
    this.enabled = true,
    this.rowPadding = 2,
  }) : value = null,
       trailing = null,
       bottom = null,
       onPressed = null,
       radioValue = null,
       groupValue = null,
       onChanged = null;

  const SettingsTile.radioTile({
    super.key,
    required this.title,
    required T this.radioValue,
    required this.groupValue,
    this.onChanged,
    this.leading,
    this.description,
    this.enabled = true,
    this.rowPadding = 2,
  }) : value = null,
       trailing = null,
       bottom = null,
       onPressed = null,
       initialValue = null,
       onToggle = null,
       toggled = null;

  /// 行的上下留白。设计稿两种行高：
  ///   · 主题页 40 → 传 4（内容 36 + 4）
  ///   · 布局页 56 → 传 10（内容 36 + 20）
  /// 由 `SettingsCardList` 的 `rowPadding` 一路传下来。
  final double rowPadding;

  final Widget title;
  final Widget? leading;
  final Widget? description;
  final Widget? value;
  final Widget? trailing;

  /// Rendered under the row, inside the same surface (used by slider tiles).
  final Widget? bottom;

  final void Function(BuildContext context)? onPressed;
  final void Function(bool? value)? onToggle;
  final bool? initialValue;

  /// 开关的当前状态，只用来补无障碍语义（`Semantics.toggled`）。
  ///
  /// [initialValue] 是「初始值」，语义上不该拿来当状态读；而这个组件又把传进来的
  /// `Switch` 拆成了 [onToggle]，读屏于是只看到「一行 + 一段文字」——既没有开关角色，
  /// 也念不出当前是开还是关。这个字段专门把状态交还给语义层，不影响任何绘制。
  final bool? toggled;
  final T? radioValue;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  VoidCallback? _tapHandler(BuildContext context) {
    if (!enabled) return null;
    if (onToggle != null) return () => onToggle!(null);
    if (onPressed != null) return () => onPressed!(context);
    if (onChanged != null && radioValue != null) {
      return () => onChanged!(radioValue);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 次要文字/图标色。**必须走面板可读性兜底**：实测浅色玻璃面板下
    // `onSurfaceVariant` 只有 4.2 左右，够不到正文所需的 4.5（深色下没问题，7 以上）。
    // 兜底只推明度、保住色相，所以次要文字仍是"次要"的样子，不会变成正文色。
    // 禁用态（38% 透明度）刻意**不走**兜底：它本来就该显得弱，强行拉到达标线
    // 会让"不可用"看起来像"可用"。
    final secondary = enabled
        ? GlassPanelTextColor.resolve(context)
        : colorScheme.onSurface.withValues(alpha: 0.38);
    // 悬停/按下不再铺底色块，改为把图标与标题染成主题色
    // （与主侧栏、设置分类栏一套规矩：底色块比图标还抢眼）。
    return SettingsHoverTracker(
      enabled: enabled,
      // 开关行的语义**必须**在这儿补：卡片把传进来的 `Switch` 拆成了 onToggle（见
      // settings_card_list），真开关由 SettingsSwitch 重建，于是读屏只看到「一行 +
      // 一段文字」——没有开关角色，也念不出当前是开还是关。`toggled` 就是为这个
      // 传进来的状态；标题由子节点自己报，所以这里不写 label，免得念两遍。
      child: Semantics(
        container: true,
        toggled: toggled,
        enabled: enabled,
        child: PressScale(
          child: InkWell(
            onTap: _tapHandler(context),
            onHighlightChanged: _SplitListRow.pressReporterOf(context),
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            // 悬停不铺底色是刻意的（见上），但**焦点**需要一块持续可见的标记：
            // 三个透明色把 InkWell 自带的焦点高亮也一并关掉了，键盘 Tab 过来时
            // 整行没有任何变化。这里用主题色压到很淡补回来。
            focusColor: colorScheme.primary.withValues(alpha: .16),
            child: Padding(
              // 行的上下留白：整行高 = 内容 36 + rowPadding × 2。
              //
              // 设计稿实测（`17828_v6_hotkey.png` 卡片二的分隔线）：
              //   230 / 292 / 334 / 376 / 418 / 460 / 502 / 544
              // 除第一条 62（标题区）外，**严格等差 42** —— 所以快捷键页
              // 传 `rowPadding: 3`，36 + 3 × 2 = 42。
              //
              // 主题页行高 40 同理传 4；布局页 56 传 10。
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                // 显式传了 `rowPadding` 就用它，否则沿用所在分组的松紧
                // （`SettingsSection.rowPadding` → `_RowPaddingScope`）。
                vertical: rowPadding != 2
                    ? rowPadding
                    : _RowPaddingScope.of(context),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    // 内容高 **36**；再高就看右侧控件（开关 30、键帽 22 都
                    // 装得下，所以常规行就是这个数）。
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Row(
                      children: [
                        Expanded(
                          child: _TileLabel(
                            title: title,
                            leading: leading,
                            description: description,
                            secondary: secondary,
                          ),
                        ),
                        if (value != null) ...[
                          const SizedBox(width: 12),
                          DefaultTextStyle.merge(
                            style: textTheme.bodyMedium?.copyWith(
                              color: secondary,
                            ),
                            child: value!,
                          ),
                        ],
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          IconTheme.merge(
                            data: IconThemeData(color: secondary),
                            child: trailing!,
                          ),
                        ],
                        if (onToggle != null) ...[
                          const SizedBox(width: 12),
                          SettingsSwitch(
                            value: initialValue ?? false,
                            onChanged: enabled ? onToggle : null,
                          ),
                        ],
                        if (radioValue != null) ...[
                          const SizedBox(width: 12),
                          _RadioDot(
                            selected: radioValue == groupValue,
                            enabled: enabled,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (bottom != null) ...[const SizedBox(height: 4), bottom!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 行内悬停状态：子节点（标题/图标）据此变色。
/// 目前只有一种反馈方式 —— 变主题色，不铺底色块。
class SettingsHoverScope extends InheritedWidget {
  const SettingsHoverScope({
    required this.hovered,
    required super.child,
    super.key,
  });

  final bool hovered;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsHoverScope>()
          ?.hovered ??
      false;

  @override
  bool updateShouldNotify(SettingsHoverScope oldWidget) =>
      oldWidget.hovered != hovered;
}

/// 把鼠标悬停状态广播给子树（见 [SettingsHoverScope]）。
class SettingsHoverTracker extends StatefulWidget {
  const SettingsHoverTracker({
    required this.enabled,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Widget child;

  @override
  State<SettingsHoverTracker> createState() => _SettingsHoverTrackerState();
}

class _SettingsHoverTrackerState extends State<SettingsHoverTracker> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SettingsHoverScope(hovered: _hovered, child: widget.child),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.title,
    this.leading,
    this.description,
    required this.secondary,
  });

  final Widget title;
  final Widget? leading;
  final Widget? description;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 悬停时图标与标题染主题色 —— 这是行内唯一的交互反馈。
    final hovered = SettingsHoverScope.of(context);
    return Row(
      children: [
        if (leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(
              size: 24,
              color: hovered ? colorScheme.primary : secondary,
            ),
            child: leading!,
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                // 设计稿设置项标题是 14、行高 1.3（`stT*` 约 18 高）；原来用的
                // `bodyLarge` 是 16px、行高约 24，两行加起来比设计稿高 12px，
                // 一列 8 项就差出 96px —— 这是「比设计稿松」的主要原因。
                //
                // `height` 写 `18 / 14`（= 1.2857）而不是 1.3：1.3 × 14 = 18.2，
                // 那个 0.2 会让行盒在 18 与 19 之间取整抖动，一列下行距就在
                // 42/44 之间跳（实测快捷键页 8 行的基线间距 42,44,42,44…）。
                // 精确到整数像素，行距才稳定成「内容高 + rowPadding × 2」。
                style: textTheme.bodyLarge?.copyWith(
                  fontSize: 14,
                  height: 18 / 14,
                  color: hovered ? colorScheme.primary : colorScheme.onSurface,
                ),
                child: title,
              ),
              if (description != null) ...[
                // 标题 → 副标题的间距 4：两行之间要留一口气，
                // 贴着的话一列看下来是一整块密实的文字。
                const SizedBox(height: 4),
                DefaultTextStyle.merge(
                  // 副标题 12、行高 1.45、0.1 字距 —— 中文小字在这个组合下最舒展。
                  //
                  // 同样锁到整数：1.45 × 12 = 17.4 → 写成 `17 / 12`。
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 17 / 12,
                    letterSpacing: 0.1,
                    color: secondary,
                  ),
                  child: description!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Hand-drawn so the tile does not depend on the deprecated Radio parameters.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = selected ? colorScheme.primary : colorScheme.outline;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: enabled ? active : active.withValues(alpha: 0.38),
          width: selected ? 6 : 2,
        ),
      ),
    );
  }
}

class _SplitListGroup extends StatelessWidget {
  const _SplitListGroup({
    required this.children,
    required this.rowPadding,
    this.title,
  });

  final List<Widget> children;

  /// 行内上下留白，用于算卡片首尾的补偿差额（见 `_cardEdgePadding`）。
  final double rowPadding;

  /// 卡片内部的标题（设计稿的 `配色方案` / `外观与显示`）。为空时卡片只有条目。
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    // 设计稿：一个设置分组是**一整张白色圆角卡**，行与行之间没有间隙、也没有
    // 每行各自的卡片。原来每行一张 GlassPanel 再留 6px 间隙，看起来是一叠小卡，
    // 和设计稿的「一张大卡」不是一回事。
    //
    // 但整组仍用 GlassPanel 包一层（solidColor 白色、圆角16）：`SettingsTile` 的
    // 次要文字靠 `GlassPanelScope` 兜底对比度到 AA，去掉这个作用域会让描述文字
    // 在浅色卡片上对比度不足。所以「一张白卡」的外观用 GlassPanel 来实现，而不是
    // 裸 Container。
    return GlassPanel(
      borderRadius: BorderRadius.circular(_cardRadius),
      // 设计稿的卡片是**纯白**（`setCard` 填充 #FFFFFF），压在 #F4F4F7 的页面底上。
      // 原来取 `colorScheme.surface` —— 那一层跟着主题种子走，换成紫/蓝主题时
      // 整张卡会泛出紫灰或蓝灰，和设计稿的「白卡 + 浅灰底」那种干净对比差很远。
      // 所以这里固定用设计稿的白，不跟主题色（与侧栏、顶栏同属设计稿的基准面）。
      solidColor: AppDesignTokens.surface,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            // 卡内标题：左 20、上 16、下 2。
            //
            // 下边距只能给 2：标题下面紧跟第一条，而第一条自身还有上下留白
            // （`rowPadding`）—— 两处叠起来才是「标题到第一行文字」的视觉间距。
            // 之前标题给下边距 10，加上第一行的留白，实测那段空隙有 **89**，
            // 是普通行高（43）的两倍多，一眼就看得出「上面空了一大块」。
            // 给 2 之后与行间距接近，整列松紧一致。
            Padding(
              // 上 16 / 下 6：标题独立成一段，和第一条拉开距离。
              // 下边距不能太大 —— 它和第一行自己的留白是叠加的，
              // 两处都给大的话「标题到第一行文字」会比行间距宽一倍。
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: title!,
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: Color(0xFFF0F0F3),
              ),
            // 卡片**首行上沿 / 末行下沿**要单独补一段留白。
            //
            // 行自身的 `rowPadding` 只够行与行之间（快捷键页 2.5、主题页 4），
            // 但卡片首尾需要的是「内容到卡片边缘」的距离 —— 设计稿
            // （`7396_v6_network.png`）实测三张卡的首尾留白都是 **18~19**
            // （第二张卡首行上方 31 是因为它没标题，标题留白让给了首行）。
            //
            // 补的值按「有没有标题」分档：
            //   · 无标题：首行补 16 —— 卡片上沿到第一行文字要有 18 左右；
            //   · 有标题：首行补 2 —— 标题区已经带了 `20, 16, 20, 6`，
            //     再补 16 会让标题和第一行之间空出两倍距离（实测 29）。
            // 末行补 16：实测只补 5 时下沿只剩 4~7（`rowPadding` 太小兜不住），
            // 补 16 才落在设计稿的 16~19。
            //
            // 这两处补偿都要**先减掉行自身已有的留白**：快捷键页的全局卡
            // `rowPadding: 20`，再补 16 就变成 33/34（实测），比设计稿松一倍。
            // 所以按「目标 16 − 本行留白」补差额，行留白 ≥ 16 时不再补。
            _cardEdgePadding(
              index: i,
              count: children.length,
              hasTitle: title != null,
              rowPadding: rowPadding,
              child: _SplitListRow(child: children[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// 卡片首行上沿、末行下沿的留白补偿：把「内容到卡片边缘」拉到 [target]。
///
/// 行的 `rowPadding` 只管行与行之间，卡片边缘需要单独一段距离。
/// 设计稿实测各页卡片首尾都是 18 左右；这里补的是**差额**，
/// 也就是 `target − rowPadding`，而不是给一个固定值。
/// 快捷键页的全局卡 `rowPadding: 20` 已经够松，再补就会变成 33/34。
/// 网络页的行只有 2.5，必须补足才能不贴边。
Widget _cardEdgePadding({
  required int index,
  required int count,
  required bool hasTitle,
  required double rowPadding,
  required Widget child,
}) {
  // 目标 20：设计稿各页卡片首尾留白实测 18~19，但行盒与卡片圆角之间
  // 还有 2~3 的边缘余量，补到 20 实际渲染出来才落在 18。
  const target = 20.0;
  // 有标题时首行上方紧接标题，标题区自带 `16` 上留白，这里只需留一点点。
  final topNeed = index == 0 ? (hasTitle ? 2.0 : target - rowPadding) : 0.0;
  final bottomNeed = index == count - 1 ? target - rowPadding : 0.0;
  if (topNeed <= 0 && bottomNeed <= 0) return child;
  return Padding(
    padding: EdgeInsets.only(
      top: topNeed > 0 ? topNeed : 0,
      bottom: bottomNeed > 0 ? bottomNeed : 0,
    ),
    child: child,
  );
}

class _SplitListRow extends StatelessWidget {
  const _SplitListRow({required this.child});

  final Widget child;

  /// Tiles forward their InkWell highlight here so the row can animate its
  /// shape as well as its colour.
  static ValueChanged<bool>? pressReporterOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SplitRowScope>()
      ?.onPressChanged;

  @override
  Widget build(BuildContext context) {
    // 行本身不再是一张带底色的卡（底色由整组那张卡统一提供），只保留 InkWell 的
    // 按下反馈作用域。悬停/按下靠文字与图标变色表达。
    return Material(
      type: MaterialType.transparency,
      child: _SplitRowScope(onPressChanged: (_) {}, child: child),
    );
  }
}

class _SplitRowScope extends InheritedWidget {
  const _SplitRowScope({required this.onPressChanged, required super.child});

  final ValueChanged<bool> onPressChanged;

  @override
  bool updateShouldNotify(_SplitRowScope oldWidget) => false;
}
