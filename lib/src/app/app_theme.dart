import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/settings.dart';

/// 页面跳转过渡：淡入 + 极小的上浮。
///
/// 桌面端默认用的是 `ZoomPageTransitionsBuilder`（整页从 0.85 缩放进场），切换时
/// 大块内容“弹”一下，和这个以卡片/列表为主、配色平滑的界面不搭；这里改成以淡入为主、
/// 位移只做点缀，和主题切换（320ms easeInOut）的平滑感保持一致。
class _AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(curve), child: child),
    );
  }
}

/// 只替换桌面平台的过渡：Android 保持 PredictiveBack、iOS/macOS 保持 Cupertino（含边缘返回手势），
/// 都跟 Flutter 自带默认值一致，避免影响移动端。
const _pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: _AppPageTransitionsBuilder(),
    TargetPlatform.windows: _AppPageTransitionsBuilder(),
  },
);

/// 开启窗口材质后界面要"透"：系统材质画在窗口底下，表面不透明就全被盖住。
///
/// 透明度按 M3 的海拔层次递进——越靠前的容器越不透明，材质只在最底层明显，
/// 这样层级关系还能看出来，不至于整片糊成一团。
const double _surfaceAlpha = .70;
const double _surfaceContainerLowestAlpha = .55;
const double _surfaceContainerLowAlpha = .62;
const double _surfaceContainerAlpha = .70;
const double _surfaceContainerHighAlpha = .78;
const double _surfaceContainerHighestAlpha = .86;

/// 全局图标轴：把 Material Symbols 统一到「线性描边 + 常规字重」。
///
/// 这四条是 `material_symbols_icons` 暴露的可变字体轴，只有 Material Symbols 字体会读，
/// Material 内置图标（MD3 组件内部的下拉箭头、SnackBar 关闭钮等）会忽略——两者共存无冲突。
///
/// - `fill: 0` 线性描边（选中/激活态在调用处显式给 `fill: 1`）
/// - `weight: 400` 与正文的常规字重对齐
/// - `opticalSize: 48` 与界面里图标的主流字号一致
/// - 深色下细线条会发糊，把 `grade` 压到 -25 提清晰度（浅色保持 0）
IconThemeData _iconTheme(Brightness brightness) => IconThemeData(
  fill: 0,
  weight: 400,
  grade: brightness == Brightness.dark ? -25 : 0,
  opticalSize: 48,
);

ThemeData appTheme(ColorScheme? dynamicScheme, Color seedColor, {Brightness brightness = Brightness.light, bool amoled = false, bool useSystemFont = false, DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot, bool neutralSurfaces = false, WindowBackdrop backdrop = WindowBackdrop.none}) {
  var scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness, dynamicSchemeVariant: variant);
  // white 主题是刻意的「白底 + 中性灰」，保持它自己的中性面；
  // 其余主题走 morrow（明隙）式淡染，中性面带上主色倾向。
  if (neutralSurfaces) {
    scheme = _neutralSurfaces(scheme, brightness);
  } else {
    scheme = _tintedSurfaces(scheme, brightness);
  }
  // AMOLED 是纯黑，跟材质叠不出效果，以纯黑为准。
  final transparent = backdrop != WindowBackdrop.none && !amoled;
  if (transparent) {
    scheme = scheme.copyWith(
      surface: scheme.surface.withValues(alpha: _surfaceAlpha),
      surfaceContainerLowest: scheme.surfaceContainerLowest.withValues(alpha: _surfaceContainerLowestAlpha),
      surfaceContainerLow: scheme.surfaceContainerLow.withValues(alpha: _surfaceContainerLowAlpha),
      surfaceContainer: scheme.surfaceContainer.withValues(alpha: _surfaceContainerAlpha),
      surfaceContainerHigh: scheme.surfaceContainerHigh.withValues(alpha: _surfaceContainerHighAlpha),
      surfaceContainerHighest: scheme.surfaceContainerHighest.withValues(alpha: _surfaceContainerHighestAlpha),
    );
  }
  if (amoled) {
    // AMOLED 的语义是「大面积纯黑省电」，但**不能把六层 surface 全压成黑**：
    // 卡片和底色同色之后，设置页整片糊成一块，连分组边界都看不出来（morrow 的
    // 深色恰恰是底色 #181720、卡片 #292634 的明度差）。
    // 这里底色保持纯黑，靠上的容器给一档极暗的主色灰把层次留住——
    // 纯黑仍然占绝大多数面积，省电意图不受影响。
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Color.lerp(Colors.black, scheme.primary, .05)!,
      surfaceContainer: Color.lerp(Colors.black, scheme.primary, .08)!,
      surfaceContainerHigh: Color.lerp(Colors.black, scheme.primary, .12)!,
      surfaceContainerHighest: Color.lerp(Colors.black, scheme.primary, .16)!,
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    iconTheme: _iconTheme(brightness),
    // 默认用内置 HarmonyOS Sans SC（可变字体，单文件自带 9 档字重）；
    // 系统字体开关打开时交回平台默认字体。
    // fallback 用于该字体没有的字符（emoji、生僻字）与彩色 emoji。
    fontFamily: useSystemFont ? null : 'HarmonyOS Sans SC',
    fontFamilyFallback: useSystemFont ? null : const ['Microsoft YaHei UI', 'Segoe UI Emoji', 'Segoe UI Symbol'],
    // 背景画布（AppBackdrop）铺在应用最底层，Scaffold 必须让出底色才能露出渐变。
    // AMOLED 例外：它要的就是纯黑，画布也一并关掉。
    scaffoldBackgroundColor: amoled ? Colors.black : Colors.transparent,
    canvasColor: amoled ? Colors.black : null,
    // M3 tints the app bar with the primary colour once content scrolls under
    // it, which stands out badly against the flat/AMOLED surfaces this app uses.
    // Keep the bar the same colour as the page.
    // 页面背景已经统一交给 AppBackdrop（Scaffold 是透明的），所以 AppBar 也必须透明：
    // 只要它铺自己的底色，顶部就会横出一条和下面内容不同色的实色条。
    // 原来只有"开着窗口材质"时才透明，关掉材质就露馅（用户看到的「右侧顶部出问题」）。
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
    pageTransitionsTheme: _pageTransitionsTheme,
    // 贴底的通栏 SnackBar 在这个布局里显得很重，改成半透明浮动圆角。
    // 它是浮起来的，同样给一层投影 —— 否则在半透明卡片上像贴纸。
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
      contentTextStyle: TextStyle(color: scheme.onSurface),
      actionTextColor: scheme.primary,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: const SliderThemeData(year2023: false),
    // 卡片的层级靠**极浅描边 + 一丝投影**（见 `GlassPanel` 的同一处决定）：
    // 白卡片压在近白的页面底上时，光靠明度差读不出边界。
    // 海拔仍是 0 —— 重投影会在卡片周围糊出一圈灰，尤其是半透明窗口材质上。
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    // 浮窗必须自己带投影：遮罩已经是全透明的（见 `showAppDialog`），背景不再变暗，
    // 全靠这层阴影把浮窗从页面上托起来。阴影色用主色偏灰（照 morrow），
    // 压在浅色画布上不会发脏；深色下仍用纯黑。
    dialogTheme: DialogThemeData(
      elevation: 10,
      shadowColor: _dialogShadow(scheme),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 6,
      shadowColor: _dialogShadow(scheme),
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // 底部弹层同理：它也是浮起来的，需要自己的投影。
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 8,
      shadowColor: _dialogShadow(scheme),
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// 浮窗投影的颜色。
Color _dialogShadow(ColorScheme scheme) => scheme.brightness == Brightness.light
    ? Color.lerp(Colors.black, scheme.primary, .45)!
    : Colors.black;

extension AppThemeColorSeed on AppThemeColor {
  Color seedColor(String customColor) => switch (this) {
        AppThemeColor.rose => const Color(0xffb3265a),
        AppThemeColor.blue => const Color(0xff00639b),
        AppThemeColor.teal => const Color(0xff006b5f),
        AppThemeColor.amber => const Color(0xff875400),
        AppThemeColor.green => const Color(0xff386a20),
        AppThemeColor.orange => const Color(0xff9b4400),
        AppThemeColor.indigo => const Color(0xff4a5f9e),
        AppThemeColor.pink => const Color(0xff9c3c66),
        // morrow（明隙）的品牌紫。中性面会朝它插值 8%，整套界面因此带紫调。
        AppThemeColor.purple => const Color(0xff7662ba),
        // 「白色」= 白底 + 一抹品牌粉（参考 bilibili），种子取 b 站粉 #FB7299，
        // 配合 [schemeVariant] 的 fidelity 变体：主色就是这抹粉，中性面保持接近纯白。
        // 注意：**不能拿纯白当种子** —— HCT 色度为 0 时 Material 会回退到色相 192（青），
        // 整套界面会变成青色（`ColorScheme.fromSeed(Color(0xffffffff)).primary` = #006874）。
        AppThemeColor.white => const Color(0xfffb7299),
        AppThemeColor.custom => Color(int.parse('ff$customColor', radix: 16)),
      };

  /// 配色变体：白色主题用 fidelity（主色忠于种子、中性面近白），其余走默认 tonalSpot。
  DynamicSchemeVariant get schemeVariant => this == AppThemeColor.white ? DynamicSchemeVariant.fidelity : DynamicSchemeVariant.tonalSpot;

  /// 是否把中性面换成中性灰（参考 bilibili 的「白底 + 浅灰卡片」）。
  ///
  /// **白色主题取中性**（其余配色仍走 8% 淡染）：用户给的参考图就是这套语言 ——
  /// 页面底是中性浅灰 `#F2F2F7`（见 `AppPageColors`），卡片与侧栏是纯白，
  /// 没有一个面自带主色，主色只出现在按钮、选中态和链接上。
  /// 淡染版本下白色主题的侧栏会整片发紫（`_lightSurface` 朝 b 站粉插值 8% 的结果），
  /// 那和参考图不是一回事。
  ///
  /// 另一条依据在 `_tintedSurfaces` 上方的文档里：那一段本来就写着
  /// 「两套都不带主色倾向」，8% 淡染和它自相矛盾；这里按文档与参考图取中性。
  bool get neutralSurfaces => this == AppThemeColor.white;

  /// 色板上那个圆的颜色：白色主题画白底（它的粉只体现在高亮色上）。
  Color swatchColor(String customColor) => this == AppThemeColor.white ? const Color(0xffffffff) : seedColor(customColor);
}

/// morrow（明隙）式淡染中性面。
///
/// `ColorScheme.fromSeed` 给出的中性色是**纯灰**——背景、卡片、文字都不带一点主色，
/// 再配上 M3 默认的 outline 对比度，卡片之间的分隔线显得很硬，整体偏"标准 Material"。
///
/// 这里照 morrow 的做法重组中性面：
/// - 每个中性色朝**强调色插值 8%**，得到带主色倾向的柔和底色（紫主题下就是"紫白"）；
/// - 分隔线压到 7.5%（暗色 13%）不透明度，几乎看不见，改用明度层次分区；
/// - 卡片面比背景亮一档，靠明度差而不是描边区分层级。
///
/// 插值比例与 morrow `Palette.themeTint` 的默认值一致（.08）。
const _tintAmount = .08;

/// 中性面色阶：**照 g1455 演示站的两个主题来**（页面底色见 `AppPageColors`）。
///
/// 取值的依据是官方产物而不是手感：
/// - 亮色是「白卡片 + 中性浅灰容器」，页面底色 `#F2F2F7`（Apple 的
///   light `systemGroupedBackground`），卡片比页面亮一档 —— 白底灰面；
/// - 暗色是「蓝黑容器阶」，页面底色 `#070A12`，卡片抬到 `#141a26` 才浮得起来；
/// - 两套**都不带主色倾向**。演示站的彩度来自内容（封面图、彩色卡片）和
///   强调色，不来自中性面 —— 中性面一染色，玻璃抽出来的每一块都跟着偏色。
///
/// [_tintedSurfaces] 与 [_neutralSurfaces] 共用这一套：前者朝 `primary`
/// 插值 [_tintAmount]，后者原样用，两者只差这一点。
const Color _lightSurface = Color(0xffffffff);
const Color _lightContainerLowest = Color(0xffffffff);
const Color _lightContainerLow = Color(0xfff7f7fa);
const Color _lightContainer = Color(0xffededf2);
const Color _lightContainerHigh = Color(0xffe7e7ed);
const Color _lightContainerHighest = Color(0xffe1e1e8);
const Color _lightInk = Color(0xff1b1b1f);
const Color _lightInkVariant = Color(0xff5f5f6b);
const Color _lightOutline = Color(0xffc3c3cc);

const Color _darkSurface = Color(0xff141a26);
const Color _darkContainerLowest = Color(0xff0a0e15);
const Color _darkContainerLow = Color(0xff0f141d);
const Color _darkContainer = Color(0xff161c28);
const Color _darkContainerHigh = Color(0xff1c2330);
const Color _darkContainerHighest = Color(0xff232a38);
const Color _darkInk = Color(0xffe4e7f0);
const Color _darkInkVariant = Color(0xffa6acbb);
const Color _darkOutline = Color(0xff4e5464);

ColorScheme _tintedSurfaces(ColorScheme scheme, Brightness brightness) {
  Color tint(Color base) => Color.lerp(base, scheme.primary, _tintAmount)!;

  if (brightness == Brightness.light) {
    final ink = tint(_lightInk);
    return scheme.copyWith(
      // 中性面：从最亮的白卡片到最沉的容器灰。
      surface: tint(_lightSurface),
      surfaceContainerLowest: tint(_lightContainerLowest),
      surfaceContainerLow: tint(_lightContainerLow),
      surfaceContainer: tint(_lightContainer),
      surfaceContainerHigh: tint(_lightContainerHigh),
      surfaceContainerHighest: tint(_lightContainerHighest),
      onSurface: ink,
      onSurfaceVariant: tint(_lightInkVariant),
      // 描边整体降一档，真正的分区交给明度差。
      outline: tint(_lightOutline),
      outlineVariant: ink.withValues(alpha: .075),
      // 次要容器跟中性面同调，避免 M3 默认的灰蓝容器跳出来。
      secondaryContainer: tint(_lightContainer),
      onSecondaryContainer: ink,
      surfaceTint: Colors.transparent,
    );
  }
  final ink = tint(_darkInk);
  return scheme.copyWith(
    surface: tint(_darkSurface),
    surfaceContainerLowest: tint(_darkContainerLowest),
    surfaceContainerLow: tint(_darkContainerLow),
    surfaceContainer: tint(_darkContainer),
    surfaceContainerHigh: tint(_darkContainerHigh),
    surfaceContainerHighest: tint(_darkContainerHighest),
    onSurface: ink,
    onSurfaceVariant: tint(_darkInkVariant),
    outline: tint(_darkOutline),
    outlineVariant: ink.withValues(alpha: .13),
    secondaryContainer: tint(_darkContainerHigh),
    onSecondaryContainer: ink,
    surfaceTint: Colors.transparent,
  );
}

/// 「白底 + 灰卡片 + 品牌色点缀」的中性面（参考 bilibili）。
///
/// fidelity 变体虽然让主色忠于种子，但会把 surface 系列一并染上种子的淡粉；
/// 这里把中性角色换成固定灰阶，只留 primary / secondary 等强调色是品牌色。
///
/// 与 [_tintedSurfaces] 的唯一区别就是**不朝主色插值**，色阶本身同一套。
ColorScheme _neutralSurfaces(ColorScheme scheme, Brightness brightness) => brightness == Brightness.light
    ? scheme.copyWith(
        surface: _lightSurface,
        surfaceContainerLowest: _lightContainerLowest,
        surfaceContainerLow: _lightContainerLow,
        surfaceContainer: _lightContainer,
        surfaceContainerHigh: _lightContainerHigh,
        surfaceContainerHighest: _lightContainerHighest,
        onSurface: _lightInk,
        onSurfaceVariant: _lightInkVariant,
        outline: _lightOutline,
        outlineVariant: _lightInk.withValues(alpha: .075),
        secondaryContainer: _lightContainer,
        onSecondaryContainer: _lightInk,
      )
    : scheme.copyWith(
        surface: _darkSurface,
        surfaceContainerLowest: _darkContainerLowest,
        surfaceContainerLow: _darkContainerLow,
        surfaceContainer: _darkContainer,
        surfaceContainerHigh: _darkContainerHigh,
        surfaceContainerHighest: _darkContainerHighest,
        onSurface: _darkInk,
        onSurfaceVariant: _darkInkVariant,
        outline: _darkOutline,
        outlineVariant: _darkInk.withValues(alpha: .13),
        secondaryContainer: _darkContainerHigh,
        onSecondaryContainer: _darkInk,
      );
