import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/glass_tier.dart';

void main() {
  group('resolveGlassTier（纯函数）', () {
    test('没有任何信号 → full，且 readsBackdrop 为真', () {
      const choice = GlassTierChoice.byDefault();
      expect(choice.tier, GlassTier.full);
      expect(choice.reason, GlassTierReason.byDefault);
      expect(choice.readsBackdrop, isTrue);
    });

    test('减少透明度 → opaque（这是那个开关真正要的）', () {
      final choice = resolveGlassTier(reduceTransparency: true);
      expect(choice.tier, GlassTier.opaque);
      expect(choice.reason, GlassTierReason.reduceTransparency);
      expect(choice.readsBackdrop, isFalse);
    });

    test('设备上限 → cheap，且不捕获背景', () {
      final choice = resolveGlassTier(ceiling: GlassTier.cheap);
      expect(choice.tier, GlassTier.cheap);
      expect(choice.reason, GlassTierReason.deviceCeiling);
      expect(choice.readsBackdrop, isFalse);
    });

    test('设备上限给 full 等于没给上限', () {
      final choice = resolveGlassTier(ceiling: GlassTier.full);
      expect(choice.tier, GlassTier.full);
      expect(choice.reason, GlassTierReason.byDefault,
          reason: '上限是 full 时不该报成「被设备限制了」');
    });

    test('设备上限给 opaque 也照做（比 cheap 更省）', () {
      final choice = resolveGlassTier(ceiling: GlassTier.opaque);
      expect(choice.tier, GlassTier.opaque);
      expect(choice.reason, GlassTierReason.deviceCeiling);
    });

    test('优先级：pinned > 减少透明度 > 上限', () {
      // 三者同时给，pinned 赢。
      final pinned = resolveGlassTier(
        pinned: GlassTier.full,
        reduceTransparency: true,
        ceiling: GlassTier.cheap,
      );
      expect(pinned.tier, GlassTier.full, reason: 'pinned 最高优先');
      expect(pinned.reason, GlassTierReason.byDefault);

      // 不给 pinned 时，减少透明度压过上限。
      final rt = resolveGlassTier(
        reduceTransparency: true,
        ceiling: GlassTier.cheap,
      );
      expect(rt.tier, GlassTier.opaque);
      expect(rt.reason, GlassTierReason.reduceTransparency);
    });

    test('pinned 能强制 full —— 即使系统要求减少透明度', () {
      // 这是给测试与截图用的后门：固定某一级，不受环境改写。
      final choice = resolveGlassTier(
        pinned: GlassTier.full,
        reduceTransparency: true,
      );
      expect(choice.tier, GlassTier.full);
    });

    test('只有 full 才捕获背景', () {
      for (final tier in GlassTier.values) {
        final choice = GlassTierChoice(tier, GlassTierReason.byDefault);
        expect(choice.readsBackdrop, tier == GlassTier.full,
            reason: '${tier.name} 的捕获语义错了');
      }
    });

    test('同一组输入必定得到同一结果（无隐藏状态）', () {
      for (var i = 0; i < 3; i++) {
        expect(
          resolveGlassTier(reduceTransparency: true),
          const GlassTierChoice(GlassTier.opaque, GlassTierReason.reduceTransparency),
        );
      }
    });

    test('自由函数名版本与 resolve 版同义', () {
      for (final pinned in <GlassTier?>[null, GlassTier.cheap]) {
        for (final rt in <bool>[true, false]) {
          for (final ceiling in <GlassTier?>[null, GlassTier.cheap, GlassTier.full]) {
            expect(
              chooseGlassTier(pinned: pinned, reduceTransparency: rt, ceiling: ceiling),
              resolveGlassTier(pinned: pinned, reduceTransparency: rt, ceiling: ceiling),
            );
          }
        }
      }
    });

    test('枚举成员稳定（序列化/上报都按顺序取）', () {
      expect(GlassTier.values, [GlassTier.full, GlassTier.cheap, GlassTier.opaque]);
      expect(GlassTierReason.values, [
        GlassTierReason.byDefault,
        GlassTierReason.reduceTransparency,
        GlassTierReason.deviceCeiling,
      ]);
    });

    test('GlassTierChoice 值相等（用于 widget 短路重建）', () {
      expect(
        const GlassTierChoice(GlassTier.cheap, GlassTierReason.deviceCeiling),
        const GlassTierChoice(GlassTier.cheap, GlassTierReason.deviceCeiling),
      );
      expect(
        const GlassTierChoice(GlassTier.cheap, GlassTierReason.deviceCeiling),
        isNot(const GlassTierChoice(GlassTier.opaque, GlassTierReason.deviceCeiling)),
      );
      expect(
        const GlassTierChoice(GlassTier.cheap, GlassTierReason.deviceCeiling).hashCode,
        const GlassTierChoice(GlassTier.cheap, GlassTierReason.deviceCeiling).hashCode,
      );
    });
  });
}
