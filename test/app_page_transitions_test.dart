import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';

/// 页面切换过渡的两层淡入淡出。
///
/// 这里测的是**几何与时序**，不是像素：`buildTransitions` 返回的树里有两层
/// `FadeTransition`，外层管旧页面淡出（吃 `secondaryAnimation`），内层管新页面
/// 淡入（吃 `animation`）。原来的实现只有内层，旧页面在整个过渡期间都是不透明的，
/// 于是新页面淡到 50% 时两层内容叠在同一块区域。
///
/// 过渡器从 `appTheme()` 里取，而不是直接 new —— 顺带验证它确实挂在了 Windows 上。
void main() {
  /// 取 `buildTransitions` 返回树里两层 FadeTransition 的当前不透明度。
  ({double leaving, double entering}) opacitiesAt({required double animation, required double secondary}) {
    final builder = appTheme(null, const Color(0xFF6750A4)).pageTransitionsTheme.builders[TargetPlatform.windows]!;
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink());
    final tree = builder.buildTransitions<void>(
      route,
      _FakeContext(),
      AlwaysStoppedAnimation<double>(animation),
      AlwaysStoppedAnimation<double>(secondary),
      const SizedBox.shrink(),
    );
    final outer = tree as FadeTransition;
    final inner = outer.child! as FadeTransition;
    return (leaving: outer.opacity.value, entering: inner.opacity.value);
  }

  test('Windows 上挂的是自定义过渡', () {
    final builder = appTheme(null, const Color(0xFF6750A4)).pageTransitionsTheme.builders[TargetPlatform.windows];
    expect(builder, isNotNull);
    expect(builder.runtimeType.toString(), isNot(contains('Zoom')));
  });

  group('旧页面淡出', () {
    test('没被覆盖时不淡出', () {
      expect(opacitiesAt(animation: 0, secondary: 0).leaving, 1);
    });

    test('被完全覆盖后不透明度归零', () {
      expect(opacitiesAt(animation: 1, secondary: 1).leaving, 0);
    });

    test('被覆盖到一半时已经明显变淡', () {
      // 这是原实现做不到的：旧页面必须跟着 secondaryAnimation 掉下去。
      expect(opacitiesAt(animation: 0.5, secondary: 0.5).leaving, lessThan(0.5));
    });

    test('随覆盖进度单调下降', () {
      final samples = [0.0, 0.25, 0.5, 0.75, 1.0].map((t) => opacitiesAt(animation: t, secondary: t).leaving).toList();
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], lessThanOrEqualTo(samples[i - 1]), reason: '第 $i 个采样点比前一个还亮：$samples');
      }
    });
  });

  group('新页面淡入', () {
    test('起步时不可见', () {
      expect(opacitiesAt(animation: 0, secondary: 0).entering, 0);
    });

    test('结束时完全可见', () {
      expect(opacitiesAt(animation: 1, secondary: 0).entering, 1);
    });

    test('前段留空：旧页面还没退干净时新页面不出现', () {
      // 两段错开是为了避免两个半透明页面同时可见 —— 页面 Scaffold 背景是透明的，
      // 交叉淡入淡出会看到双重影像。
      expect(opacitiesAt(animation: 0.3, secondary: 0.3).entering, 0);
    });

    test('后段才开始出现', () {
      expect(opacitiesAt(animation: 0.6, secondary: 0.6).entering, greaterThan(0));
    });
  });

  test('两层的可见区间不重叠', () {
    // 逐点扫一遍：任何时刻都不该出现「旧页面还亮着、新页面也亮着」。
    for (var i = 0; i <= 20; i++) {
      final t = i / 20;
      final o = opacitiesAt(animation: t, secondary: t);
      expect(o.leaving * o.entering, 0, reason: 't=$t 时两层同时可见：leaving=${o.leaving} entering=${o.entering}');
    }
  });
}

/// `buildTransitions` 用不到 context 的成员，给个空壳即可。
class _FakeContext extends Fake implements BuildContext {}
