import 'package:flutter/material.dart';

/// 全应用统一的动效规范层。
///
/// 这里不发明新的时长／曲线，只是把 Flutter 自带的 Material 3 token
/// （[Durations] 与 [Easing]，由 Material Design token 数据库代码生成）
/// 收拢成一处业务语义命名，让页面里不再出现 `Duration(milliseconds: 180)`
/// 这类随手写的字面量。
///
/// 迁移时按语义就近替换即可：
/// - 50/100/150/200 → short1..short4
/// - 250/300/350/400 → medium1..medium4
/// - 450..600 → long1..long4
/// - 700..1000 → extralong1..extralong4
///
/// 偏离规范的历史值（如 180、170、220、260、320）统一归到最接近的一档，
/// 避免同一个动作在页面间快慢不一。
abstract final class AppMotion {
  // ---- 时长：直接引用官方 token ----

  /// 极短反馈（按压、hover 高亮）：50ms。
  static const Duration instant = Durations.short1;

  /// 短反馈（图标切换、tooltip 淡入）：100ms。
  static const Duration quick = Durations.short2;

  /// 短过渡（控件展开／收起、焦点态）：150ms。
  static const Duration brief = Durations.short3;

  /// 标准过渡（页面内小幅位移、卡片状态变化）：200ms。
  static const Duration standard = Durations.short4;

  /// 中等过渡（面板展开、底部弹层）：250ms。
  static const Duration emphasis = Durations.medium1;

  /// 中长过渡（对话框进出）：300ms。
  static const Duration dialog = Durations.medium2;

  /// 长过渡（整页切换）：400ms。
  static const Duration page = Durations.medium4;

  /// 超长（启动动画、进度扫光）：700ms。
  static const Duration showcase = Durations.extralong1;

  // ---- 曲线：直接引用官方 token ----

  /// 进入屏幕的元素（减速收尾）。
  static const Curve enter = Easing.emphasizedDecelerate;

  /// 离开屏幕的元素（加速离场）。
  static const Curve exit = Easing.emphasizedAccelerate;

  /// 标准缓动，多数过渡的默认选择。
  static const Curve standardCurve = Easing.standard;

  /// 标准加速。
  static const Curve accelerate = Easing.standardAccelerate;

  /// 标准减速。
  static const Curve decelerate = Easing.standardDecelerate;

  /// 线性，用于连续动画（进度、扫光）。
  static const Curve linear = Easing.linear;

  /// 通用的「短过渡」组合，页面里最常用。
  static const Duration shortDuration = standard;
}

/// 判断是否应当播放动画：系统「减少动画」或祖先 [TickerMode] 关闭时跳过。
///
/// 与 `MediaQuery.disableAnimationsOf` + `TickerMode.valuesOf` 一致，
/// 收在一处是为了避免各处写法不一。
bool motionEnabledOf(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;

/// 按 [enabled] 返回时长；关闭动效时归零，控件直接跳到终态。
Duration motionDuration(BuildContext context, Duration duration) =>
    motionEnabledOf(context) ? duration : Duration.zero;
