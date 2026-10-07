/// 玻璃的**降级层级** —— 与 [GlassQuality]（材质档）是正交的两个维度。
///
/// ## 为什么单独一层，而不是往 [GlassQuality] 里再加一档
///
/// `GlassQuality` 回答的是「用户想要哪种材质」（磨砂 / 超透 / 液体玻璃），
/// 这是**用户的审美选择**。而这里回答的是「这台机器 / 这个无障碍偏好下，
/// 该不该真的去捕获背景」，这是**运行条件的约束**。
///
/// 混进同一个枚举会同时坏掉两件事：用户说不清自己选的是什么档，代码也分不清
/// 「他没开玻璃」和「我们替他降级了」。分开之后，[GlassTier.full] 时材质档原样
/// 生效，降级时只是**绕过捕获**，材质档本身不动 —— 条件恢复后立刻回到用户的选择。
///
/// ## 三级各自画什么
///
/// | 层级 | 画什么 | 捕获背景 |
/// |---|---|---|
/// | [full] | 真玻璃：折射、模糊、底色、亮边 | 是 |
/// | [cheap] | **同形状 + 同边框**，底色直接铺在背景上，不模糊不折射 | **否** |
/// | [opaque] | 一个不透明实色，取该档玻璃叠在背景上的平均观感 | **否** |
///
/// [cheap] 保留形状与边框是有意的：降级的是**成本**，不是**身份**。一块没有
/// 轮廓的色块会让人以为界面坏了，而带圆角与描边的面板一眼还是那个面板。
library;

import 'package:flutter/foundation.dart';

/// 玻璃的降级层级。见库级文档。
enum GlassTier {
  /// 真玻璃：捕获背景、做折射与模糊。用户选了档位就按档位画。
  full,

  /// 省电档：同形状 + 同边框，底色直接铺，**完全不捕获背景**。
  cheap,

  /// 不透明档：铺一个等效实色。系统「减少透明度」要的就是这个。
  opaque,
}

/// 为什么落到这一级 —— 只用于上报与调试，不参与判定。
enum GlassTierReason {
  /// 没有任何降级信号，用完整玻璃。
  byDefault,

  /// 系统开了「减少透明度」。
  reduceTransparency,

  /// 设备能力上限（低端机 / 用户手动选了省电）。
  deviceCeiling,
}

/// 一次层级判定的结果：层级 + 原因。
@immutable
class GlassTierChoice {
  const GlassTierChoice(this.tier, this.reason);

  const GlassTierChoice.byDefault()
      : tier = GlassTier.full,
        reason = GlassTierReason.byDefault;

  final GlassTier tier;
  final GlassTierReason reason;

  /// 这一级还需不需要捕获背景。`full` 之外都不需要 —— 那是省下来的全部开销。
  bool get readsBackdrop => tier == GlassTier.full;

  @override
  bool operator ==(Object other) =>
      other is GlassTierChoice && other.tier == tier && other.reason == reason;

  @override
  int get hashCode => Object.hash(tier, reason);

  @override
  String toString() => 'GlassTierChoice(${tier.name}, ${reason.name})';
}

/// 解析该用哪一级 —— **纯函数**，不读任何全局状态。
///
/// 顺序是有讲究的，照 g1455 的 `GlassTierPolicy.choose()`：
///
/// 1. [pinned] —— 最高优先。测试、截图、基准要用固定的一级，不能被环境信号改写。
/// 2. [reduceTransparency] —— 系统的无障碍开关。它要的就是"别透"，给 [GlassTier.opaque]。
/// 3. [ceiling] —— 设备能力上限。只在比 [GlassTier.full] 更低时才起作用。
/// 4. 兜底 [GlassTier.full]。
///
/// ## 为什么「减少透明度」不等同于「减少动画」
///
/// 这两个开关常被一起提，但语义完全不同：前者说的是**可见性**（别让内容透出来），
/// 后者说的是**运动**（别动）。拿「减少动画」去降玻璃透明度是错的 —— 用户要的是
/// 别晃，不是别透。本仓库的 `motionEnabledOf` 只管动效时长，不碰材质，这条边界
/// 在 `glass_budget.dart` 里也写过一次。
GlassTierChoice resolveGlassTier({
  GlassTier? pinned,
  bool reduceTransparency = false,
  GlassTier? ceiling,
}) {
  if (pinned != null) {
    return GlassTierChoice(pinned, GlassTierReason.byDefault);
  }
  if (reduceTransparency) {
    return const GlassTierChoice(GlassTier.opaque, GlassTierReason.reduceTransparency);
  }
  if (ceiling != null && ceiling != GlassTier.full) {
    return GlassTierChoice(ceiling, GlassTierReason.deviceCeiling);
  }
  return const GlassTierChoice.byDefault();
}

/// [resolveGlassTier] 的自由函数名版本，读起来更像一句话。
///
/// 与 [resolveGlassTier] 同义；留两个入口只是因为调用点想写
/// 「chooseGlassTier(...)」而不想把 `resolve` 与 `tier` 拼在一起读。
GlassTierChoice chooseGlassTier({
  GlassTier? pinned,
  bool reduceTransparency = false,
  GlassTier? ceiling,
}) => resolveGlassTier(
  pinned: pinned,
  reduceTransparency: reduceTransparency,
  ceiling: ceiling,
);
