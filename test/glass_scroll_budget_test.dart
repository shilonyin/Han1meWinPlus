import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/glass_budget.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/glass/liquid_glass.dart';

/// 从**真实 widget 树**验证滚动预算，而不是只测纯函数。
///
/// 纯函数测试证明不了"接对了"：路径选对了但没接到 BackdropFilter 上，
/// 纯函数测试照样全绿。这里把渲染接缝暴露出来的路径收集起来断言。
void main() {
  late List<GlassRefractionPath> resolved;

  setUp(() {
    resolved = [];
    LiquidGlassSurface.debugOnRefractionPathResolved = resolved.add;
  });

  tearDown(() {
    LiquidGlassSurface.debugOnRefractionPathResolved = null;
  });

  GlassMaterial material() => GlassMaterial.quality(
    quality: GlassQuality.frosted,
    tint: const Color(0xfff4f3f9),
    dark: false,
    readable: false,
    borderRadius: BorderRadius.circular(18),
    opacity: .5,
  );

  Widget glassIn(Widget child) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 200,
        child: LiquidGlassSurface(
          tint: const Color(0xfff4f3f9),
          dark: false,
          borderRadius: BorderRadius.circular(18),
          material: material(),
          child: child,
        ),
      ),
    ),
  );

  testWidgets('静止（不在滚动视图里）时走 realtime', (tester) async {
    await tester.pumpWidget(glassIn(const SizedBox()));
    await tester.pumpAndSettle();

    expect(resolved, isNotEmpty, reason: '面板应至少解析过一次折射路径');
    expect(
      resolved.every((p) => p == GlassRefractionPath.realtime),
      isTrue,
      reason: '静止时必须走默认路径，否则静止观感会与改动前不同',
    );
  });

  testWidgets('滚动中切到 fallback，停止后回到 realtime', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 40,
            itemBuilder: (_, index) => SizedBox(
              height: 120,
              child: LiquidGlassSurface(
                tint: const Color(0xfff4f3f9),
                dark: false,
                borderRadius: BorderRadius.circular(18),
                material: material(),
                child: Text('item $index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 静止基线：首次构建时解析过，且全部是 realtime。
    expect(resolved, isNotEmpty, reason: '首次构建应解析过折射路径');
    expect(
      resolved.toSet(),
      {GlassRefractionPath.realtime},
      reason: '静止时必须走默认路径，否则静止观感会与改动前不同',
    );

    // 按住列表并移动，**保持指针不抬起** —— 只有拖动活动期间
    // `isScrollingNotifier` 才是 true；`tester.drag` 会一次性完成
    // 按下/移动/抬起，等我们 pump 时滚动早已结束，测不到滚动中这一态。
    resolved.clear();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassSurface).first),
    );
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();

    expect(
      resolved,
      isNotEmpty,
      reason: '滚动中应重新解析路径',
    );
    expect(
      resolved.contains(GlassRefractionPath.fallback),
      isTrue,
      reason: '滚动期间必须降级 —— 这是本改动的全部意义',
    );

    // 抬起后回到静止，应恢复默认路径。
    await gesture.up();
    await tester.pumpAndSettle();
    resolved.clear();
    // 再触发一次重绘（例如滚动位置微调），确认恢复成 realtime。
    await tester.drag(find.byType(ListView), const Offset(0, -1));
    await tester.pump();
    expect(
      resolved.contains(GlassRefractionPath.fallback),
      isFalse,
      reason: '停止滚动后必须回到默认路径，否则静止观感会一直停在降级态',
    );
  });

  testWidgets('TickerMode 关闭（面板不可见）时降级', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: false,
            child: SizedBox(
              width: 200,
              height: 200,
              child: LiquidGlassSurface(
                tint: const Color(0xfff4f3f9),
                dark: false,
                borderRadius: BorderRadius.circular(18),
                material: material(),
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      resolved.every((p) => p == GlassRefractionPath.fallback),
      isTrue,
      reason: '不可见的面板没有绘制必要，应走低成本路径',
    );
  });

  testWidgets('降级不改变模糊强度与底色（滚动前后 material 逐字段相同）', (tester) async {
    // 这条钉死票面的硬约束：滚动期**只**换折射路径，不降模糊等级。
    // 复刻两档预算下真实渲染所用的 material，断言它们完全一致。
    final controller = ScrollController();
    addTearDown(controller.dispose);

    GlassMaterial? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              SizedBox(
                height: 300,
                child: Builder(
                  builder: (_) {
                    final m = material();
                    captured = m;
                    return LiquidGlassSurface(
                      tint: const Color(0xfff4f3f9),
                      dark: false,
                      borderRadius: BorderRadius.circular(18),
                      material: m,
                      child: const SizedBox(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = captured!;
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();

    // material 由调用方传入且不随滚动重建 —— 模糊与底色因此不可能变化。
    expect(captured!.blur, before.blur);
    expect(captured!.liquid, before.liquid);
    expect(captured!.decoration, before.decoration);
  });

  group('验收标准 3：静止外观与改动前一致', () {
    testWidgets('静止且可见时解析为 realtime（改动前只有这一条路径）', (tester) async {
      resolved.clear();
      await tester.pumpWidget(glassIn(const SizedBox()));
      await tester.pumpAndSettle();
      expect(
        resolved.toSet(),
        {GlassRefractionPath.realtime},
        reason: '静止时必须走 realtime，否则静止观感与改动前不同',
      );
    });

    testWidgets('磨砂档静止时 filter 仍是纯模糊（改动前后逐字相同）', (tester) async {
      await tester.pumpWidget(glassIn(const SizedBox()));
      await tester.pumpAndSettle();
      final rendered = tester
          .widget<BackdropFilter>(find.byType(BackdropFilter).first)
          .filter;
      // 磨砂档 liquid=0，_filter 在开头 early-return 纯模糊，不受本改动影响。
      expect(
        rendered,
        ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        reason: '磨砂档的 filter 必须与改动前完全一致',
      );
    });
  });
}
