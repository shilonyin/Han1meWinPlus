/// 玻璃折射走哪条路径。
///
/// 两条路径的**观感接近**（作者在 `liquid_glass.dart` 里注明"同样的亮边"），
/// 差别只在成本与折射精度：
/// - [realtime]：逐像素跑片元着色器（`ImageFilter.shader`），折射最准，最贵；
/// - [fallback]：一层放大平移（`ImageFilter.matrix`），成本固定在一次采样。
enum GlassRefractionPath {
  /// 逐像素片元着色器。静止时的默认路径。
  realtime,

  /// 放大平移回退。"滚动中"与"面板不该绘制"时走它。
  fallback,
}

/// 玻璃材质的**渲染预算**规范层。
///
/// ## 它解决什么
///
/// `GlassPanel` 有 19 个调用点，全部是**随内容滚动的卡片**。滚动时一屏可能同时
/// 有好几块玻璃，每块都在跑逐像素着色器 —— 这是最可能的掉帧源。
/// 这里按"当前是否在滚动 / 面板是否还该绘制"决定换用哪条折射路径。
///
/// ## 一条硬约束：预算里没有模糊强度，也没有透明度
///
/// 上游 BiliPai 的 `BlurBudgetPolicy` 带 `maxBlurLevel`，滚动时把它压到 0，
/// 并在注释里检讨说那样会造成明暗跳跃与视觉割裂（Pulsing / Popping）。
///
/// 本仓库**不重复那个错误**：降级只换折射路径，[GlassRefractionPath] 里
/// 不含任何模糊强度、底色或透明度 —— 滚动期间那几项**不可能**变化，
/// 这是由类型保证的，不是靠调用方自觉。`test/glass_scroll_budget_test.dart`
/// 会从真实 widget 树里把这条钉死。
///
/// ## 生效范围（实测，必须知道）
///
/// 折射路径**只对走折射的档位有意义**。`liquid_glass.dart` 的 `_filter` 在
/// `material.liquid <= .001` 时会直接 `return ImageFilter.blur(...)`，
/// 根本不会走到折射那一段。实测各档：
///
/// | 档位 | liquid | 本降级是否有作用 |
/// |---|---|---|
/// | `off` | 0 | 不走玻璃 |
/// | **`frosted`（新装默认）** | **0** | **无作用** —— 纯模糊，与路径无关 |
/// | `clear` | .35 | 有作用 |
/// | `liquid` | 1 | 有作用 |
///
/// 也就是说：**在默认档下这个预算不会带来性能变化**。它买的是"用户主动选了
/// 带折射的档位后，滚动不掉帧"。默认档那层大半径模糊（磨砂 sigma=26）是另一笔
/// 开销，不在本预算的管辖范围内 —— 要动它得先解决上面那条"降模糊会跳变"的
/// 老问题，那是另一个决定。
///
/// ## 为什么"减少动画"不参与判断
///
/// BiliPai 把系统「减少动画」当作降级信号，是因为 Android 上那个开关常与
/// 省电 / 低端机相关。桌面端的「减少动画」是纯粹的**无障碍偏好**，拿它永久
/// 关掉折射会改变静止外观，与"静止时观感不变"的验收标准直接冲突。
/// 这里改用 [TickerMode]：面板不可见 / 被遮挡时不再绘制，是真实收益，
/// 且不影响任何可见状态。
///
/// ## 与运行时守卫的关系
///
/// [RuntimeVisualGuard] 检测到持续掉帧时会永久降级（[guardDegraded]）。它与
/// "正在滚动"**归结为同一个后果**：切到 fallback 折射路径。也就是说守卫不会
/// 改动模糊强度或底色 —— 它让滚动更顺，代价只是折射精度下降，静止外观
/// 在降级生效后与"一直处于滚动中"完全相同。
///
/// **用户手动选最高档（`GlassQuality.liquid`）时守卫仍然生效**：那是"我要最好的
/// 材质"，不是"我宁可掉帧也要用着色器"。它只在真的持续掉帧时才介入，且恢复
/// 后自动回到 realtime。
///
/// 目前**没有**暴露给用户的开关（`RuntimeVisualGuard.enabled` 是代码级入口，
/// 默认开）。要不要在设置页给一个"性能优先"开关，是另一个决定。
abstract final class GlassBudget {
  /// 解析当前该走哪条折射路径。
  ///
  /// - [isScrolling]：最近祖先滚动视图是否正在滚动（不在滚动视图里时恒 `false`）；
  /// - [tickerActive]：祖先 [TickerMode] 是否启用；`false` 表示面板当前不可见
  ///   （被 `Offstage` / 未激活的 `Navigator` 路由遮挡等），此时没有绘制的必要；
  /// - [guardDegraded]：运行时守卫是否已判定持续掉帧。`true` 时**永久**走 fallback，
  ///   直到守卫判定恢复正常。
  ///
  /// 三个条件都**只**影响折射路径，不影响模糊与底色。
  static GlassRefractionPath resolveRefractionPath({
    required bool isScrolling,
    required bool tickerActive,
    bool guardDegraded = false,
  }) => isScrolling || !tickerActive || guardDegraded
      ? GlassRefractionPath.fallback
      : GlassRefractionPath.realtime;
}

/// [GlassBudget.resolveRefractionPath] 的自由函数形式。
///
/// 规范层用静态方法（与 `AppMotion` 一致）；单独留这个入口是为了让调用点
/// 读起来是一句话，也方便单测直接构造。
GlassRefractionPath resolveGlassRefractionPath({
  required bool isScrolling,
  required bool tickerActive,
  bool guardDegraded = false,
}) => GlassBudget.resolveRefractionPath(
  isScrolling: isScrolling,
  tickerActive: tickerActive,
  guardDegraded: guardDegraded,
);
