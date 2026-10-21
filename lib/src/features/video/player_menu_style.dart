import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/app_radius.dart';
import 'player_overlay_surface.dart';
import 'player_wheel_guard.dart';

/// 播放器弹层的统一材质。
///
/// 底部那一串弹层（音量面板、画幅 / 集数 / Anime4K / 清晰度 / 倍速 / 更多）
/// 原来是 Material 默认的 `surfaceContainer` 实心方块 + 4px 圆角，压在视频上
/// 就是一块块不透明的黑；而控制条早在 [PlayerOverlaySurface] 里统一成了
/// 半透明 + 背景模糊 + 大圆角的悬浮条，两者并排时像从两个界面拼出来的。
///
/// 麻烦在于 `MenuStyle` 只有 backgroundColor / shape / padding 这些字段
/// （`menu_style.dart`），`_MenuPanelState.build` 最后就是一句
/// `Material(color: backgroundColor, shape: shape, ...)`，没有插自定义 Widget
/// 的位置 —— 光调 `MenuStyle` 只能得到一个纯色块，做不出模糊。
///
/// 所以做法是分两半：
/// 1. [playerMenuPanelStyle] 把 Material 那一层彻底让出来（透明、零圆角、零内边距），
/// 让它只剩定位与测量；
/// 2. [playerMenuPanel] 把 [menuChildren] 整体包进一个 [PlayerOverlaySurface]，
///    与控制条共用同一份材质，用的是同一个组件，不会再有偏差。

/// 面板容器的样式：把 Material 自身画的那层让空。
///
/// 真正的底色和圆角交给 [playerMenuPanel] 里的 [PlayerOverlaySurface]。
/// `backgroundColor` 必须给一个全透明的颜色而不是 null —— 传 null 时
/// `_MenuPanelState.build` 会退到 `MaterialType.transparency`，那时 `shape`
/// 会被忽略、阴影也不画，定位和测量反而更不可控。
MenuStyle playerMenuPanelStyle({AlignmentGeometry? alignment}) => MenuStyle(
  alignment: alignment,
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
);

/// 把一组菜单项包成一块和控制条同材质的悬浮面板。
///
/// 返回值是**列表**，直接当 `menuChildren:` 用 —— `MenuAnchor` 的
/// `menuChildren` 是 `List<Widget>`，而 `_MenuPanel` 会把多于一屏的内容
/// 塞进 `SingleChildScrollView`；包成单个 child 才有一整块面板的样子。
///
/// [maxHeight] 限的是**内容**高度，不是面板：给了之后滚动发生在
/// [PlayerOverlaySurface] 内部，滚动的项被 [ClipRRect] 裁住，圆角始终在。
/// 不设的话超长列表会先长到屏幕外，再让 `MenuAnchor` 自己在外层滚 ——
/// 那时滚动的是整块面板，滚起来顶部圆角就跟着内容一起滚出去了。
List<Widget> playerMenuPanel(
  List<Widget> children, {
  double radius = AppRadius.lg,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 6,
  ),
  double? maxHeight,
  bool? swallowScroll,
}) {
  // 只有内容真的会滚动时才需要拦：不滚的面板（音量、倍速这类）原本就没有
  // 可滚区域，滚轮一直是调音量的，保持原样。
  final swallow = swallowScroll ?? (maxHeight != null);
  final column = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
  final content = maxHeight == null
      ? column
      : ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(child: column),
        );

  if (!swallow) {
    // 不滚的面板不拦滚轮（滚轮照旧调音量），但一样要登记「开着」——
    // 否则鼠标移到它上面时控制条照常倒计时消失，面板跟着按钮一起被卸载。
    return <Widget>[
      PlayerWheelGuardRegion(
        blocksWheel: false,
        child: PlayerOverlaySurface(
          radius: radius,
          padding: padding,
          child: content,
        ),
      ),
    ];
  }
  // 面板插在 Navigator 的 Overlay 里，不在播放器子树内，滚轮只能靠
  // `PointerSignalResolver` 抢 —— 抢不稳（面板滚到顶时内部 Scrollable 就不再
  // 注册，播放器那个 Listener 反而赢）。所以在拦事件之外，再把面板占据的
  // 屏幕矩形登记给 [PlayerWheelGuard]，让播放器按区域直接放弃。
  return <Widget>[
    PlayerWheelGuardRegion(
      child: Listener(
        onPointerSignal: _swallowScroll,
        child: PlayerOverlaySurface(
          radius: radius,
          padding: padding,
          child: content,
        ),
      ),
    ),
  ];
}

/// 把子树占据的屏幕矩形登记进 [PlayerWheelGuard]。
///
/// 面板是插进 Overlay 的独立子树，只有在它自己的 `build` 之后才能拿到
/// `RenderBox` 的全局偏移；而打开动画期间位置和尺寸都还在变，所以每个已排
/// 版的帧都同步一次 —— 一次 `findRenderObject` 加一次 Map 写入，不 `setState`，
/// 不会自己触发新帧。
class PlayerWheelGuardRegion extends StatefulWidget {
  const PlayerWheelGuardRegion({
    required this.child,
    this.blocksWheel = true,
    super.key,
  });

  final Widget child;

  /// 是否连滚轮一起拦（面板里有滚动内容时为 true）。
  final bool blocksWheel;

  @override
  State<PlayerWheelGuardRegion> createState() => _PlayerWheelGuardRegionState();
}

class _PlayerWheelGuardRegionState extends State<PlayerWheelGuardRegion> {
  final Object _token = Object();

  @override
  void dispose() {
    PlayerWheelGuard.instance.remove(_token);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      PlayerWheelGuard.instance.remove(_token);
      return;
    }
    PlayerWheelGuard.instance.update(
      _token,
      box.localToGlobal(Offset.zero) & box.size,
      blocksWheel: widget.blocksWheel,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    return widget.child;
  }
}

void _swallowScroll(PointerSignalEvent event) {
  if (event is! PointerScrollEvent) return;
  GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
    (resolved as PointerScrollEvent).respond(allowPlatformDefault: false);
  });
}

/// 菜单项（[MenuItemButton] / [SubmenuButton]）的统一样式。
///
/// 播放器浮层永远压在视频画面上，不跟主题走：一律白字、悬停时提亮一层。
/// 不给的话浅色主题下是黑字，压在模糊后的亮画面上直接看不见。
ButtonStyle playerMenuItemStyle() => ButtonStyle(
  foregroundColor: WidgetStateProperty.resolveWith<Color>(
    (states) =>
        states.contains(WidgetState.disabled) ? Colors.white38 : Colors.white,
  ),
  iconColor: WidgetStateProperty.resolveWith<Color>(
    (states) =>
        states.contains(WidgetState.disabled) ? Colors.white24 : Colors.white70,
  ),
  overlayColor: const WidgetStatePropertyAll(Color(0x1FFFFFFF)),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  ),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  ),
  // 高亮块比面板圆角小一档，贴着圆角边才不会切掉。
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm)),
  ),
  animationDuration: const Duration(milliseconds: 120),
);

/// 选中项的样式：把字色固定成强调色并加粗。
///
/// 选中项往往把 `onPressed` 设成 null（点了也是回到自己），而
/// [playerMenuItemStyle] 的 disabled 分支会把字压成白色 38% —— 那样「当前
/// 状态」反而比别的项更淡。所以这里不按状态分支，直接给死色。
ButtonStyle playerMenuItemSelectedStyle(Color accent) =>
    playerMenuItemStyle().copyWith(
      foregroundColor: WidgetStatePropertyAll(accent),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );

/// 统一后的菜单项。
///
/// 「当前状态」只用字体颜色表示，不加勾选图标：勾选图标占一格宽度、和左侧
/// 图标列对不齐，面板一窄还会把文字顶出去。UI 上就是选中项换成强调色，
/// 一眼扫下去整列都是字，哪一项高亮一目了然。
Widget playerMenuItem({
  required VoidCallback? onPressed,
  required Widget child,
  Widget? leadingIcon,
  Widget? trailingIcon,
  bool selected = false,
}) {
  if (!selected) {
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
      style: playerMenuItemStyle(),
      child: child,
    );
  }
  // 强调色要从主题取，这里没有 context，用 Builder 借一个 —— Builder 是
  // 透明的中间层，不影响菜单项的布局与命中测试。
  return Builder(
    builder: (context) => MenuItemButton(
      onPressed: onPressed,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
      style: playerMenuItemSelectedStyle(Theme.of(context).colorScheme.primary),
      child: child,
    ),
  );
}

/// 统一后的二级菜单入口。
///
/// 二级面板是另一个 `MenuAnchor`，容器样式要单独给；它挂在主面板里，
/// 所以用更小一档的圆角，视觉上才知道是从上面那层里长出来的。
///
/// [menuChildren] 收**已经包好的**面板（调用处直接写 `playerMenuPanel([...])`），
/// 这里不再包一层 —— 两层 `PlayerOverlaySurface` 会叠出两重模糊和两层边框。
Widget playerSubmenu({
  required List<Widget> menuChildren,
  required Widget child,
}) => SubmenuButton(
  style: playerMenuItemStyle(),
  menuStyle: playerMenuPanelStyle(),
  menuChildren: menuChildren,
  child: child,
);
