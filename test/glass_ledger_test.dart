import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_ledger.dart';

/// 一个可控的探针，用来测登记册而不必建整棵 widget 树。
class _Probe implements GlassSurfaceProbe {
  _Probe(this.bounds, {this.shared = false});

  Rect? bounds;
  bool shared;

  @override
  Rect? probeGlassBounds() => bounds;

  @override
  bool get probeSharesSampling => shared;
}

void main() {
  group('resolveGlassLoad（纯函数）', () {
    const view = Size(1000, 1000);

    test('空列表 → 全零', () {
      final load = resolveGlassLoad(surfaces: const [], viewSize: view);
      expect(load.surfaceCount, 0);
      expect(load.screensOfGlass, 0);
      expect(load.overlappingPairs, 0);
      expect(load.refractingCount, 0);
    });

    test('数与面积：两块 200×100 的玻璃 = 40000 px²，占 0.04 屏', () {
      final load = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 200, 100), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 200, 200, 100), sharedSampling: true),
        ],
        viewSize: view,
      );
      expect(load.surfaceCount, 2);
      expect(load.sharedSamplingCount, 2);
      expect(load.rectAreaLogical, 40000);
      expect(load.screensOfGlass, closeTo(.04, 1e-9));
    });

    test('可共享 / 走折射分别计数，两者相加等于总数', () {
      final load = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 10, 10), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 20, 10, 10), sharedSampling: false),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 40, 10, 10), sharedSampling: false),
        ],
        viewSize: view,
      );
      expect(load.sharedSamplingCount, 1);
      expect(load.refractingCount, 2);
      expect(load.sharedSamplingCount + load.refractingCount, load.surfaceCount);
    });

    test('不重叠 → 重叠对数为 0（共享采样的前提）', () {
      final load = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 100, 100), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 100, 100, 100), sharedSampling: true),
        ],
        viewSize: view,
      );
      expect(load.overlappingPairs, 0, reason: '边贴边不算重叠');
    });

    test('两块重叠 → 记 1 对；三块两两重叠 → 记 3 对', () {
      final two = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 100, 100), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(50, 50, 100, 100), sharedSampling: true),
        ],
        viewSize: view,
      );
      expect(two.overlappingPairs, 1);

      final three = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 100, 100), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(10, 10, 100, 100), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(20, 20, 100, 100), sharedSampling: true),
        ],
        viewSize: view,
      );
      expect(three.overlappingPairs, 3, reason: '三块两两相交 = 3 对');
    });

    test('面积为 0 的矩形也计入数量，但不贡献面积', () {
      final load = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 0, 0), sharedSampling: true),
        ],
        viewSize: view,
      );
      expect(load.surfaceCount, 1);
      expect(load.rectAreaLogical, 0);
      expect(load.screensOfGlass, 0);
    });

    test('视图尺寸退化（0 或负）时占比记 0，而不是 Infinity / NaN', () {
      const surface = GlassSurfaceRecord(
        bounds: Rect.fromLTWH(0, 0, 100, 100),
        sharedSampling: true,
      );
      for (final size in const [Size.zero, Size(0, 100), Size(-5, 100)]) {
        final load = resolveGlassLoad(surfaces: const [surface], viewSize: size);
        expect(load.screensOfGlass, 0, reason: '尺寸 $size 不该算出非有限值');
        expect(load.screensOfGlass.isFinite, isTrue);
      }
    });

    test('面积和可以超过一屏（多层玻璃叠加）', () {
      final load = resolveGlassLoad(
        surfaces: const [
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 1000, 1000), sharedSampling: true),
          GlassSurfaceRecord(bounds: Rect.fromLTWH(0, 0, 1000, 500), sharedSampling: false),
        ],
        viewSize: view,
      );
      expect(load.screensOfGlass, closeTo(1.5, 1e-9));
    });
  });

  group('GlassLedger（登记册）', () {
    setUp(() => GlassLedger.instance.resetForTest());
    tearDown(() => GlassLedger.instance.resetForTest());

    test('登记与注销，重复登记不重复计数', () {
      final ledger = GlassLedger.instance;
      final probe = _Probe(const Rect.fromLTWH(0, 0, 100, 100));
      ledger.register(probe);
      ledger.register(probe);
      expect(ledger.registeredCount, 1);
      ledger.unregister(probe);
      expect(ledger.registeredCount, 0);
      ledger.unregister(probe); // 再注销一次不该炸
      expect(ledger.registeredCount, 0);
    });

    test('取不到几何的面板不计入读数', () {
      final ledger = GlassLedger.instance;
      ledger.register(_Probe(null)); // 未布局
      ledger.register(_Probe(const Rect.fromLTWH(0, 0, 100, 100)));
      final load = ledger.read(viewSize: const Size(1000, 1000));
      expect(load.surfaceCount, 1, reason: '只有拿到几何的那块算数');
      expect(ledger.registeredCount, 2, reason: '但登记数仍是 2');
    });

    test('零尺寸的面板不计入读数（避免污染重叠判定）', () {
      final ledger = GlassLedger.instance;
      ledger.register(_Probe(Rect.zero));
      ledger.register(_Probe(const Rect.fromLTWH(0, 0, 100, 100)));
      expect(ledger.read(viewSize: const Size(1000, 1000)).surfaceCount, 1);
    });

    test('增删会通知（读数面板据此刷新），几何变化不会', () {
      final ledger = GlassLedger.instance;
      var notifications = 0;
      void listener() => notifications++;
      ledger.addListener(listener);
      addTearDown(() => ledger.removeListener(listener));

      final probe = _Probe(const Rect.fromLTWH(0, 0, 10, 10));
      ledger.register(probe);
      expect(notifications, 1);

      // 移动：几何变了，但不通知 —— 读数本来就要现取。
      probe.bounds = const Rect.fromLTWH(50, 50, 10, 10);
      expect(notifications, 1, reason: '几何变化不该触发通知');

      expect(ledger.read(viewSize: const Size(100, 100)).rectAreaLogical, 100,
          reason: '但读出来的是新位置');
      ledger.unregister(probe);
      expect(notifications, 2);
    });

    test('读数按探针当前状态折算可共享数', () {
      final ledger = GlassLedger.instance;
      ledger.register(_Probe(const Rect.fromLTWH(0, 0, 10, 10), shared: true));
      ledger.register(_Probe(const Rect.fromLTWH(0, 20, 10, 10), shared: false));
      final load = ledger.read(viewSize: const Size(100, 100));
      expect(load.sharedSamplingCount, 1);
      expect(load.refractingCount, 1);
    });
  });
}
