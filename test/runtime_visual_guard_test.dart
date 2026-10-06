import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/runtime_visual_guard.dart';

void main() {
  group('resolveRuntimeVisualGuardDecision（纯函数）', () {
    RuntimeVisualGuardDecision decide({
      bool enabled = true,
      double jank = 0,
      int highWindows = 0,
      int? lastDowngradeAtMs,
      int nowMs = 0,
    }) => resolveRuntimeVisualGuardDecision(
      enabled: enabled,
      rollingJankPercent: jank,
      consecutiveHighJankWindows: highWindows,
      lastDowngradeAtMs: lastDowngradeAtMs,
      nowMs: nowMs,
    );

    test('阈值常量与 BiliPai 一致：触发 7.5%、恢复 4%、要求连续 2 窗口', () {
      expect(runtimeVisualGuardHighJankThresholdPercent, 7.5);
      expect(runtimeVisualGuardRecoverThresholdPercent, 4.0);
      expect(runtimeVisualGuardRequiredHighJankWindows, 2);
      expect(runtimeVisualGuardDowngradeCooldown, const Duration(seconds: 60));
    });

    test('首次触发：连续 2 个高掉帧窗口后降级', () {
      // 第 1 个窗口：连续数还不够，不降。
      expect(decide(jank: 9, highWindows: 1).degraded, isFalse);
      // 第 2 个窗口：达到 2，降级。
      final hit = decide(jank: 9, highWindows: 2, nowMs: 1000);
      expect(hit.degraded, isTrue);
      // 记下这一次降级的时刻，供冷却判断使用。
      expect(hit.nextLastDowngradeAtMs, 1000);
    });

    test('单窗口抖动不触发（连续数不足）', () {
      // 掉帧率很高，但只出现了一个窗口 —— 可能只是偶发卡顿（GC / 后台任务）。
      expect(decide(jank: 40, highWindows: 1).degraded, isFalse);
    });

    test('冷却期内不再重新评估：即使掉帧率已回落也维持降级', () {
      // 刚降级 30 秒（冷却 60 秒内），掉帧率已降到 0，仍应保持降级。
      final inCooldown = decide(
        jank: 0,
        highWindows: 0,
        lastDowngradeAtMs: 1000,
        nowMs: 1000 + 30 * 1000,
      );
      expect(inCooldown.degraded, isTrue);
      // 且不刷新"上次降级时刻"，冷却窗口不会被这次判定续期。
      expect(inCooldown.nextLastDowngradeAtMs, 1000);
    });

    test('迟滞恢复：掉帧率降到 4% 以下才回弹，刚过 4% 仍保持降级', () {
      final afterCooldown = 1000 + 61 * 1000;
      // 5%：高于恢复阈值（4%），继续降级 —— 这就是迟滞。
      expect(
        decide(jank: 5, lastDowngradeAtMs: 1000, nowMs: afterCooldown).degraded,
        isTrue,
      );
      // 恰好 4%：不算"低于恢复阈值"，仍降级（条件是 > 4 才维持）。
      expect(
        decide(jank: 4, lastDowngradeAtMs: 1000, nowMs: afterCooldown).degraded,
        isFalse,
      );
      // 3%：低于恢复阈值，回弹。
      expect(
        decide(jank: 3, lastDowngradeAtMs: 1000, nowMs: afterCooldown).degraded,
        isFalse,
      );
    });

    test('关掉守卫时恒不降级，且不改动已有的降级时刻', () {
      final off = decide(enabled: false, jank: 99, highWindows: 99, lastDowngradeAtMs: 1000, nowMs: 999999);
      expect(off.degraded, isFalse);
      expect(off.nextLastDowngradeAtMs, 1000, reason: '关掉不应抹掉历史状态');
    });

    test('恢复后调用方保留的时间戳不再导致降级', () {
      // 冷却早已过去、掉帧率也低 → 不降级，且时间戳原样保留。
      final recovered = decide(jank: 1, lastDowngradeAtMs: 1000, nowMs: 1000 + 120 * 1000);
      expect(recovered.degraded, isFalse);
      expect(recovered.nextLastDowngradeAtMs, 1000);
    });
  });

  group('mergeRuntimeVisualGuardDecisions（多信号取最保守）', () {
    test('任一信号降级 → 全局降级', () {
      final merged = mergeRuntimeVisualGuardDecisions([
        const RuntimeVisualGuardDecision(degraded: false, nextLastDowngradeAtMs: null),
        const RuntimeVisualGuardDecision(degraded: true, nextLastDowngradeAtMs: 500),
        const RuntimeVisualGuardDecision(degraded: false, nextLastDowngradeAtMs: null),
      ]);
      expect(merged.degraded, isTrue);
      expect(merged.nextLastDowngradeAtMs, 500);
    });

    test('全部不降级 → 不降级', () {
      final merged = mergeRuntimeVisualGuardDecisions([
        const RuntimeVisualGuardDecision(degraded: false, nextLastDowngradeAtMs: null),
        const RuntimeVisualGuardDecision(degraded: false, nextLastDowngradeAtMs: 700),
      ]);
      expect(merged.degraded, isFalse);
    });

    test('多个信号都降级时取最晚的降级时刻（冷却按最保守算）', () {
      final merged = mergeRuntimeVisualGuardDecisions([
        const RuntimeVisualGuardDecision(degraded: true, nextLastDowngradeAtMs: 100),
        const RuntimeVisualGuardDecision(degraded: true, nextLastDowngradeAtMs: 900),
        const RuntimeVisualGuardDecision(degraded: true, nextLastDowngradeAtMs: 400),
      ]);
      expect(merged.nextLastDowngradeAtMs, 900);
    });

    test('空集合 → 不降级', () {
      expect(mergeRuntimeVisualGuardDecisions(const []).degraded, isFalse);
    });
  });

  group('JankWindow：静止帧不进分母', () {
    test('非交互帧完全不计（分子分母都不进）', () {
      final window = JankWindow(capacity: 3);
      // 三帧都很卡，但都不是连续交互 → 一帧都不该记。
      for (var i = 0; i < 3; i++) {
        window.addFrame(
          build: const Duration(milliseconds: 100),
          raster: const Duration(milliseconds: 100),
          active: false,
        );
      }
      expect(window.frames, 0);
      expect(window.jankPercent, 0);
      expect(window.takeCompletedWindow(), isNull, reason: '没采到帧就不该结算');
    });

    test('静止帧不会稀释真实掉帧率（这是本设计的关键取舍）', () {
      // 对比：如果静止帧也算作"没掉帧"，真实掉帧率会被摊薄。
      final window = JankWindow(capacity: 4);
      // 2 帧交互且都掉帧。
      for (var i = 0; i < 2; i++) {
        window.addFrame(
          build: const Duration(milliseconds: 50),
          raster: Duration.zero,
          active: true,
        );
      }
      // 2 帧静止（本来会稀释分母）。
      for (var i = 0; i < 2; i++) {
        window.addFrame(build: Duration.zero, raster: Duration.zero, active: false);
      }
      expect(window.frames, 2, reason: '分母只含 2 帧交互帧');
      expect(window.jankPercent, 100, reason: '2/2 掉帧 = 100%，未被静止帧稀释');
      expect(window.takeCompletedWindow(), isNull, reason: '容量 4、只采到 2，尚未满');
    });

    test('预算内的一帧不算掉帧，超过才算', () {
      final window = JankWindow(capacity: 2);
      // 恰好等于预算（16667us）不算超过。
      window.addFrame(
        build: const Duration(microseconds: 16667),
        raster: Duration.zero,
        active: true,
      );
      expect(window.jankPercent, 0);
      // 超过一个微秒就算。
      window.addFrame(
        build: const Duration(microseconds: 16668),
        raster: Duration.zero,
        active: true,
      );
      expect(window.jankPercent, 50);
    });

    test('build + raster 合计超预算才算掉帧（两处各占一半不算）', () {
      final window = JankWindow(capacity: 1);
      window.addFrame(
        build: const Duration(milliseconds: 9),
        raster: const Duration(milliseconds: 9),
        active: true,
      );
      expect(window.jankPercent, 100, reason: '9+9=18ms > 16.67ms');
    });

    test('采满窗口后结算并清零', () {
      final window = JankWindow(capacity: 2);
      window.addFrame(build: const Duration(milliseconds: 50), raster: Duration.zero, active: true);
      window.addFrame(build: Duration.zero, raster: Duration.zero, active: true);
      final done = window.takeCompletedWindow();
      expect(done, 50);
      expect(window.frames, 0, reason: '结算后清零，开始下一个窗口');
      expect(window.isFull, isFalse);
    });
  });
}
