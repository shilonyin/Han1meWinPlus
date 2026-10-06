import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/glass_budget.dart';
import 'package:han1me_win_plus/src/core/runtime_visual_guard.dart';

/// 端到端：从"帧数据"到"折射路径"的完整链路。
///
/// 纯函数测试说明不了"接对了没有" —— 判定算对了但没接到 `GlassBudget` 上，
/// 纯函数测试照样全绿。这里喂真实帧序列，断言最终解析出的折射路径确实变了。
void main() {
  /// 造一帧超过预算的时序（build+raster 合计 > 16.67ms）。
  void feedJankyFrame(RuntimeVisualGuard guard, {int count = 1}) {
    for (var i = 0; i < count; i++) {
      guard.handleFrame(
        build: const Duration(milliseconds: 12),
        raster: const Duration(milliseconds: 12),
      );
    }
  }

  void feedSmoothFrame(RuntimeVisualGuard guard, {int count = 1}) {
    for (var i = 0; i < count; i++) {
      guard.handleFrame(
        build: const Duration(milliseconds: 2),
        raster: const Duration(milliseconds: 2),
      );
    }
  }

  RuntimeVisualGuard freshGuard() {
    final guard = RuntimeVisualGuard();
    guard.resetForTest();
    return guard;
  }

  group('守卫判定 → 折射路径（端到端）', () {
    test('静止期间喂满掉帧帧也不降级（不进分母）', () {
      final guard = freshGuard();
      // 没有标记任何交互源 → 全是静止帧。
      feedJankyFrame(guard, count: 200);
      expect(
        guard.degraded.value,
        isFalse,
        reason: '静止帧不该参与统计，因此不可能触发降级',
      );
    });

    test('连续交互期间持续掉帧 → 降级 → 折射路径变 fallback', () {
      final guard = freshGuard();
      const source = 'scroll';
      guard.setSourceActive(source, true);

      // 两个窗口（2 × 60 帧）。
      feedJankyFrame(guard, count: 120);

      expect(guard.degraded.value, isTrue, reason: '连续 2 个窗口超阈值应降级');

      // 关键断言：降级结论确实传导到折射路径。
      expect(
        resolveGlassRefractionPath(
          isScrolling: false,
          tickerActive: true,
          guardDegraded: guard.degraded.value,
        ),
        GlassRefractionPath.fallback,
      );
      // 对照：不传降级标志时是 realtime，说明变化确实来自守卫。
      expect(
        resolveGlassRefractionPath(isScrolling: false, tickerActive: true),
        GlassRefractionPath.realtime,
      );
    });

    test('交互结束后的静止帧不再累积（不会靠静止帧把窗口补满）', () {
      final guard = freshGuard();
      const source = 'scroll';
      guard.setSourceActive(source, true);
      // 只喂 10 帧不平滑也不掉帧的交互帧。
      feedSmoothFrame(guard, count: 10);
      // 结束交互。
      guard.setSourceActive(source, false);
      // 之后大量掉帧的静止帧。
      feedJankyFrame(guard, count: 200);
      expect(
        guard.degraded.value,
        isFalse,
        reason: '交互已结束，静止帧不应把它推到降级',
      );
    });

    test('多面板滚动：全部停下才算交互结束', () {
      final guard = freshGuard();
      guard.setSourceActive('panel-a', true);
      guard.setSourceActive('panel-b', true);

      // 只停一个 → 仍在交互。
      guard.setSourceActive('panel-a', false);
      expect(guard.isInteractionActive, isTrue);

      // 两个都停 → 交互结束。
      guard.setSourceActive('panel-b', false);
      expect(guard.isInteractionActive, isFalse);
    });

    test('面板销毁（setSourceActive false）不会让守卫卡在"永远滚动"', () {
      final guard = freshGuard();
      guard.setSourceActive('panel', true);
      // 模拟面板在滚动中被销毁。
      guard.setSourceActive('panel', false);
      expect(guard.isInteractionActive, isFalse);
    });

    test('关掉守卫：即使连续掉帧也不降级', () {
      final guard = freshGuard();
      guard.enabled = false;
      guard.setSourceActive('scroll', true);
      feedJankyFrame(guard, count: 200);
      expect(guard.degraded.value, isFalse);
    });

    test('冷却期内不会因为"又喂了一把流畅帧"就回弹', () {
      final guard = freshGuard();
      guard.setSourceActive('scroll', true);
      feedJankyFrame(guard, count: 120);
      expect(guard.degraded.value, isTrue);

      // 再喂 600 帧流畅帧（10 个窗口）。
      //
      // 注意这条断言的边界：冷却期是 60 秒**真实时间**，而这段代码只跑了几毫秒，
      // 所以它验证的是"处理更多窗口不会绕开冷却"，**不是**"冷却结束后才恢复" ——
      // 后者由 `runtime_visual_guard_test.dart` 里用显式 `nowMs` 的纯函数用例覆盖
      // （那里能精确构造冷却前后的时刻）。
      feedSmoothFrame(guard, count: 600);
      expect(
        guard.degraded.value,
        isTrue,
        reason: '冷却期内不得回弹 —— 否则会来回抖动，比不降级更晃',
      );
    });
  });
}
