import 'package:flutter/material.dart';

/// 非线性渐隐：消除线性渐变中段的**马赫带**（Mach-Band）切面。
///
/// 移植自某即时通讯客户端的停靠点算法。
///
/// ## 解决什么问题
///
/// 遮罩类渐变（海报压暗、播放器控制栏底衬）一直是
/// `colors: [Colors.transparent, Colors.black87]` 这种**两阶线性**写法。
/// 线性 alpha 在感知亮度上并不线性：明暗过渡集中在中段，两端反而平缓，
/// 人眼会把它读成一道看得见的"硬边"。压在海报或视频画面上时尤其刺眼 ——
/// 这正是为什么手工微调 `stops` 往往治标不治本。
///
/// 该做法的核心是**把 alpha 的收敛集中到贴近实色的一端**，用 5 阶非线性
/// 停靠点（255 → 232 → 176 → 96 → 0）让消散过程平滑收尾：靠实色处迅速
/// 收敛为纯色，离开实色处极其柔和地淡出，中段不再有可辨识的边界。
///
/// ## 用法
///
/// 用 [topSolid] / [bottomSolid] 替换手写的 `LinearGradient`：
///
/// ```dart
/// // 旧：两阶线性，中段有硬边
/// BoxDecoration(
///   gradient: LinearGradient(
///     begin: Alignment.topCenter,
///     end: Alignment.bottomCenter,
///     colors: [Colors.transparent, Colors.black87],
///   ),
/// )
///
/// // 新：五阶非线性，消散平滑
/// BoxDecoration(gradient: ProgressiveFade.bottomSolid(Colors.black87))
/// ```
///
/// 该模块只产出 `LinearGradient`，不引入任何 widget 或状态，便于单测与复用。
abstract final class ProgressiveFade {
  /// 阶梯位置：五等分。
  static const List<double> stops = <double>[0, .25, .5, .75, 1];

  /// 实测的 alpha 阶梯（基准 255）。
  ///
  /// 0xFF → 0xE8 → 0xB0 → 0x60 → 0x00，即 255 / 232 / 176 / 96 / 0。
  /// 这组值不是随手取的：它让 alpha 在靠实色端的斜率平缓、靠透明端陡峭，
  /// 恰好抵消感知亮度在线性空间里的非线性。
  static const List<double> alphaFactors = <double>[
    1,
    232 / 255,
    176 / 255,
    96 / 255,
    0,
  ];

  /// 实色端在上（顶部压暗，向下消散）。用于播放器顶部栏这类贴顶 chrome。
  ///
  /// [extent] 是渐变覆盖的高度占整体的比例：`1` 表示从最顶端一路过渡到底部，
  /// 取值更小则渐变收窄、只占顶部一段（空白区域保持完全透明）。
  static LinearGradient topSolid(Color solid, {double extent = 1}) {
    final span = extent.clamp(0.0, 1.0);
    return _gradient(
      solid: solid,
      begin: Alignment.topCenter,
      end: Alignment(0, -1 + 2 * span),
      reversed: false,
    );
  }

  /// 实色端在下（底部压暗，向上消散）。用于播放器控制栏底衬、海报标题遮罩。
  static LinearGradient bottomSolid(Color solid, {double extent = 1}) {
    final span = extent.clamp(0.0, 1.0);
    return _gradient(
      solid: solid,
      begin: Alignment(0, 1 - 2 * span),
      end: Alignment.bottomCenter,
      reversed: true,
    );
  }

  /// 按阶梯缩放 [solid] 自身的 alpha，得到 5 阶色标。
  ///
  /// **关键**：消散端的落点是 `solid` 的透明版本，而不是 `Colors.transparent`。
  /// `Colors.transparent` 是透明**黑**，色相和实色不一致；带色遮罩（例如
  /// 主题色底衬）用它收尾会在末端出现明显的偏色。
  static List<Color> fadeColors(Color solid, {required bool reversed}) {
    final base = solid.a;
    final factors = reversed ? alphaFactors.reversed : alphaFactors;
    return <Color>[
      for (final factor in factors) solid.withValues(alpha: base * factor),
    ];
  }

  static LinearGradient _gradient({
    required Color solid,
    required Alignment begin,
    required Alignment end,
    required bool reversed,
  }) => LinearGradient(
    begin: begin,
    end: end,
    colors: fadeColors(solid, reversed: reversed),
    stops: stops,
  );
}
