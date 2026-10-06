import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 触发降级的滚动掉帧率阈值（百分比）。与参考实现一致。
const double runtimeVisualGuardHighJankThresholdPercent = 7.5;

/// 解除降级的恢复阈值（百分比）。
///
/// **刻意低于**触发阈值 —— 两者之间的间隔就是"迟滞"：没有它，掉帧率在阈值
/// 附近抖动时守卫会反复降级/回弹，反而比不降级更晃。
const double runtimeVisualGuardRecoverThresholdPercent = 4.0;

/// 降级后的冷却时长。冷却期内不再重新评估降级。
const Duration runtimeVisualGuardDowngradeCooldown = Duration(seconds: 60);

/// 连续多少个"高掉帧窗口"才真正降级。
///
/// 取 2 而不是 1：单个窗口偏高可能只是一次偶发卡顿（后台任务、GC），
/// 连续两个窗口都高才说明是持续性的扛不住。
const int runtimeVisualGuardRequiredHighJankWindows = 2;

/// 一帧的预算，60Hz 下的 16.67ms。build + raster 超过它就算一次掉帧。
///
/// 高刷屏（120Hz）的实际预算是 8.3ms，这里仍按 60Hz 计：本仓库的判定只用来
/// 决定"要不要切折射路径"，用偏宽松的阈值可以避免在 120Hz 屏上因为正常波动
/// 就误判降级。真要按刷新率动态取预算，得先拿到 `Display.refreshRate`，
/// 那是另一个决定。
const Duration runtimeVisualGuardFrameBudget = Duration(microseconds: 16667);

/// 一个窗口的帧数。60 帧 ≈ 1 秒（60Hz），够采样又不会把很久以前的情况算进来。
const int runtimeVisualGuardWindowFrames = 60;

/// 一次判定的结果。
@immutable
class RuntimeVisualGuardDecision {
  const RuntimeVisualGuardDecision({
    required this.degraded,
    required this.nextLastDowngradeAtMs,
  });

  /// 当前是否应当降级。
  final bool degraded;

  /// 下一次判定要传回来的"上次降级时刻"。
  ///
  /// 判定是纯函数，不能自己记状态，所以由调用方持有并回传 —— 这也是它可测的前提。
  final int? nextLastDowngradeAtMs;

  @override
  bool operator ==(Object other) =>
      other is RuntimeVisualGuardDecision &&
      other.degraded == degraded &&
      other.nextLastDowngradeAtMs == nextLastDowngradeAtMs;

  @override
  int get hashCode => Object.hash(degraded, nextLastDowngradeAtMs);

  @override
  String toString() =>
      'RuntimeVisualGuardDecision(degraded: $degraded, '
      'nextLastDowngradeAtMs: $nextLastDowngradeAtMs)';
}

/// 判定是否应当降级 —— 纯函数，不持有任何状态。
///
/// 对应上游的判定实现，阈值与冷却都照搬，
/// 但去掉了它那个 `forceLowBudget` 入参：本仓库目前没有"外部强制低预算"的
/// 来源（它是给 Android 的省电模式用的），留着就是空参数。
///
/// - [enabled]：守卫总开关，关掉时原样返回不降级；
/// - [rollingJankPercent]：**只统计连续交互帧**的掉帧率（静止帧不进分母，
///   否则界面静止时的流畅帧会把真实掉帧率稀释掉）；
/// - [consecutiveHighJankWindows]：已经连续多少个窗口超过触发阈值；
/// - [lastDowngradeAtMs] / [nowMs]：用于冷却判断的单调时钟毫秒值。
///
/// 顺序与上游一致：先看是否触发 → 再看冷却 → 再看是否维持。
RuntimeVisualGuardDecision resolveRuntimeVisualGuardDecision({
  required bool enabled,
  required double rollingJankPercent,
  required int consecutiveHighJankWindows,
  required int? lastDowngradeAtMs,
  required int nowMs,
}) {
  if (!enabled) {
    return RuntimeVisualGuardDecision(
      degraded: false,
      nextLastDowngradeAtMs: lastDowngradeAtMs,
    );
  }

  final shouldTrigger =
      rollingJankPercent >= runtimeVisualGuardHighJankThresholdPercent &&
      consecutiveHighJankWindows >= runtimeVisualGuardRequiredHighJankWindows;
  if (shouldTrigger) {
    return RuntimeVisualGuardDecision(
      degraded: true,
      nextLastDowngradeAtMs: nowMs,
    );
  }

  final inCooldown = lastDowngradeAtMs != null &&
      (nowMs - lastDowngradeAtMs) <
          runtimeVisualGuardDowngradeCooldown.inMilliseconds;
  if (inCooldown) {
    return RuntimeVisualGuardDecision(
      degraded: true,
      nextLastDowngradeAtMs: lastDowngradeAtMs,
    );
  }

  final shouldStay =
      lastDowngradeAtMs != null &&
          rollingJankPercent > runtimeVisualGuardRecoverThresholdPercent;
  if (shouldStay) {
    return RuntimeVisualGuardDecision(
      degraded: true,
      nextLastDowngradeAtMs: lastDowngradeAtMs,
    );
  }

  return RuntimeVisualGuardDecision(
    degraded: false,
    nextLastDowngradeAtMs: lastDowngradeAtMs,
  );
}

/// 合并多个信号各自的判定：**任一信号降级 → 全局降级**。
///
/// 各信号窗口互相独立（竖滑与横滑会同帧共存，混在一个窗口里会互相污染分母），
/// 但对外只暴露一个结论，且取最保守的那个。
///
/// 与上游的差异：它额外把 `effectiveMotionTier` 一起 fold，本仓库的降级
/// 只影响折射路径、没有分档，所以只合并"降不降"。
RuntimeVisualGuardDecision mergeRuntimeVisualGuardDecisions(
  Iterable<RuntimeVisualGuardDecision> decisions,
) {
  final degraded = decisions.where((d) => d.degraded).toList(growable: false);
  if (degraded.isEmpty) {
    return const RuntimeVisualGuardDecision(
      degraded: false,
      nextLastDowngradeAtMs: null,
    );
  }
  return RuntimeVisualGuardDecision(
    degraded: true,
    nextLastDowngradeAtMs: degraded
        .map((d) => d.nextLastDowngradeAtMs)
        .whereType<int>()
        .fold<int?>(null, (max, value) => max == null || value > max ? value : max),
  );
}

/// 只累积**连续交互期间**帧的一个滑动窗口。
///
/// ## 为什么必须"只在交互期间记"
///
/// 这是上游特意强调的取舍：界面静止时也长期挂着的高频状态（例如"当前分类"）
/// 会把静止帧算进分母 —— 而静止帧几乎不掉，于是真实掉帧率被稀释，
/// 守卫永远不触发。所以 [addFrame] 带 [active] 参数，非交互帧**直接不参与统计**
/// （既不加分子也不加分母），而不是记成"没掉帧"。
class JankWindow {
  JankWindow({this.capacity = runtimeVisualGuardWindowFrames});

  /// 一个窗口最多累积多少帧。
  final int capacity;

  int _frames = 0;
  int _jankyFrames = 0;

  /// 已累积的帧数（只含交互帧）。
  int get frames => _frames;

  /// 窗口是否已满。
  bool get isFull => _frames >= capacity;

  /// 当前窗口的掉帧率（百分比）。没有采样时返回 0。
  double get jankPercent => _frames == 0 ? 0 : _jankyFrames / _frames * 100;

  /// 记一帧。[active] 为 `false`（非连续交互）时**什么都不做**。
  void addFrame({
    required Duration build,
    required Duration raster,
    required bool active,
  }) {
    if (!active) return;
    _frames++;
    if (build + raster > runtimeVisualGuardFrameBudget) _jankyFrames++;
  }

  /// 窗口满了就清零，返回清零前的掉帧率；没满返回 `null`（还没到该判定的时候）。
  double? takeCompletedWindow() {
    if (!isFull) return null;
    final percent = jankPercent;
    reset();
    return percent;
  }

  void reset() {
    _frames = 0;
    _jankyFrames = 0;
  }
}

/// 把帧回调接到上面的判定逻辑上的运行时外壳。
///
/// 判定本身是纯函数（[resolveRuntimeVisualGuardDecision]）；这个类只负责
/// **持有状态、订阅帧、把结论广播出去**。所以它的核心方法
/// [handleFrame] 收的是两个 `Duration` 而不是 `FrameTiming` —— `FrameTiming`
/// 的构造函数是私有的、测试里造不出来，收 Duration 才能对它做单测。
class RuntimeVisualGuard {
  RuntimeVisualGuard({this.enabled = true, JankWindow? window})
      : _window = window ?? JankWindow();

  /// 全局单例。玻璃面板很多，降级是**全局**结论，必须只有一份状态。
  static final RuntimeVisualGuard instance = RuntimeVisualGuard();

  /// 守卫总开关。关掉时判定恒为"不降级"，且不影响任何已生效的状态。
  bool enabled;

  /// 当前是否处于降级态。玻璃渲染监听它。
  final ValueNotifier<bool> degraded = ValueNotifier<bool>(false);

  final JankWindow _window;
  final Stopwatch _clock = Stopwatch();
  /// 正在连续交互的来源。用集合而不是计数，是为了面板被销毁时不会漏减。
  final Set<Object> _activeSources = <Object>{};
  int _consecutiveHighJankWindows = 0;
  int? _lastDowngradeAtMs;
  bool _installed = false;

  /// 是否正在连续交互（有任一来源报告活跃）。
  bool get isInteractionActive => _activeSources.isNotEmpty;

  /// 订阅全局帧回调。重复调用无副作用。
  void install() {
    if (_installed) return;
    _installed = true;
    _clock.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// 退订。主要给测试用；应用内这个对象与进程同生命周期。
  void dispose() {
    if (!_installed) return;
    _installed = false;
    _clock.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// 标记某个来源开始/结束了连续交互（这里是玻璃面板的滚动状态）。
  ///
  /// 全部来源都停下时把**未采满的半个窗口丢掉** —— 半截窗口跨着一段静止时间，
  /// 混进下一次交互里会让数据不干净。已经采满并结算过的窗口不受影响。
  void setSourceActive(Object source, bool active) {
    if (active) {
      _activeSources.add(source);
      return;
    }
    _activeSources.remove(source);
    if (_activeSources.isEmpty) _window.reset();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      handleFrame(
        build: timing.buildDuration,
        raster: timing.rasterDuration,
      );
    }
  }

  /// 喂一帧。非交互期间的帧**根本不参与统计**（见 [JankWindow.addFrame]）。
  @visibleForTesting
  void handleFrame({required Duration build, required Duration raster}) {
    _window.addFrame(
      build: build,
      raster: raster,
      active: isInteractionActive,
    );
    final completed = _window.takeCompletedWindow();
    if (completed == null) return;

    // "连续"指的是**连续采满的窗口**：静止帧从不进统计，所以一段静止之后
    // 新开的窗口仍然接着数，不会被静止期打断 —— 与"静止不进分母"是同一套语义。
    _consecutiveHighJankWindows =
        completed >= runtimeVisualGuardHighJankThresholdPercent
            ? _consecutiveHighJankWindows + 1
            : 0;

    final decision = resolveRuntimeVisualGuardDecision(
      enabled: enabled,
      rollingJankPercent: completed,
      consecutiveHighJankWindows: _consecutiveHighJankWindows,
      lastDowngradeAtMs: _lastDowngradeAtMs,
      nowMs: _clock.elapsedMilliseconds,
    );
    _lastDowngradeAtMs = decision.nextLastDowngradeAtMs;
    if (degraded.value != decision.degraded) degraded.value = decision.degraded;
  }

  /// 仅供测试：重置全部内部状态。
  @visibleForTesting
  void resetForTest() {
    _window.reset();
    _activeSources.clear();
    _consecutiveHighJankWindows = 0;
    _lastDowngradeAtMs = null;
    degraded.value = false;
  }
}
