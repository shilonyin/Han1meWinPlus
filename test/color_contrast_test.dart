import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/color_contrast.dart';

/// 浅色主题的语义色（对齐本仓库 morrow 淡染中性面的实际取值），
/// 供"压明度兜底"那组测试复用。
ColorScheme _lightScheme(Color surface) => ColorScheme.fromSeed(
  seedColor: const Color(0xff7662ba),
).copyWith(
  surface: surface,
  onSurface: const Color(0xff302d43),
  onSurfaceVariant: const Color(0xff777184),
  scrim: Colors.black,
);

void main() {
  group('阈值常量', () {
    test('正文 4.5、UI 元素 3.0（WCAG AA）', () {
      expect(accessibleTextMinContrast, 4.5);
      expect(accessibleUiMinContrast, 3.0);
    });
  });

  group('contrastRatio', () {
    test('纯黑对纯白为 21.0', () {
      expect(
        contrastRatio(Colors.black, Colors.white),
        closeTo(21.0, 0.01),
      );
      // 交换顺序结果不变：对比度只看亮度差。
      expect(
        contrastRatio(Colors.white, Colors.black),
        closeTo(21.0, 0.01),
      );
    });

    test('同色对比度为 1.0', () {
      expect(
        contrastRatio(const Color(0xff3a3a3a), const Color(0xff3a3a3a)),
        closeTo(1.0, 0.001),
      );
    });

    test('忽略 alpha：同名 RGB 的半透明色对比度相同', () {
      expect(
        contrastRatio(const Color(0x80ffffff), Colors.black),
        closeTo(contrastRatio(Colors.white, Colors.black), 0.001),
      );
    });

    test('meetsContrast 按阈值判定，UI 阈值更宽松', () {
      // 中灰 #949494 压白底：对比度约 3.03 —— 正文（4.5）不达标，但当 UI 元素（3.0）刚好达标。
      const mid = Color(0xff949494);
      expect(meetsContrast(mid, Colors.white), isFalse);
      expect(
        meetsContrast(mid, Colors.white, minimumContrast: accessibleUiMinContrast),
        isTrue,
      );
      // 更浅的灰 (约 2.17)：连 UI 阈值都够不上。
      const lighter = Color(0xffb0b0b0);
      expect(contrastRatio(lighter, Colors.white), closeTo(2.17, .01));
      expect(
        meetsContrast(lighter, Colors.white, minimumContrast: accessibleUiMinContrast),
        isFalse,
      );
      // 更深的 #767676 约 4.54：正文与 UI 都达标。
      const deeper = Color(0xff767676);
      expect(contrastRatio(deeper, Colors.white), closeTo(4.54, .01));
      expect(
        meetsContrast(deeper, Colors.white, minimumContrast: accessibleUiMinContrast),
        isTrue,
      );
    });
  });

  group('opaqueCompositeOver', () {
    test('50% 白叠在黑上：中间值 0.5，且输出不透明', () {
      final result = opaqueCompositeOver(
        const Color.from(alpha: .5, red: 1, green: 1, blue: 1),
        Colors.black,
      );
      expect(result.a, 1.0);
      expect(result.r, closeTo(.5, .001));
      expect(result.g, closeTo(.5, .001));
      expect(result.b, closeTo(.5, .001));
    });

    test('不透明前景完全覆盖背景', () {
      final result = opaqueCompositeOver(
        const Color(0xff123456),
        Colors.white,
      );
      expect(result.a, 1.0);
      expect(result, const Color(0xff123456));
    });

    test('背景也半透明时按 alpha 累积', () {
      // 50% 白压 50% 黑压（透明的）底：输出 alpha 仍为 1，色值偏白。
      final result = opaqueCompositeOver(
        const Color.from(alpha: .5, red: 1, green: 1, blue: 1),
        const Color.from(alpha: .5, red: 0, green: 0, blue: 0),
      );
      expect(result.a, 1.0);
      // outAlpha = .5 + .5*.5 = .75；red = (.5*1) / .75 ≈ .667
      expect(result.r, closeTo(2 / 3, .001));
    });

    test('两层都完全透明时返回 Colors.transparent', () {
      expect(
        opaqueCompositeOver(Colors.transparent, Colors.transparent),
        Colors.transparent,
      );
    });
  });

  group('resolveReadableTextColor（单回退）', () {
    test('候选达标就用候选', () {
      expect(
        resolveReadableTextColor(
          candidate: Colors.black,
          background: Colors.white,
          fallback: Colors.white,
        ),
        Colors.black,
      );
    });

    test('候选不达标就用回退', () {
      expect(
        resolveReadableTextColor(
          candidate: const Color(0xffeeeeee),
          background: Colors.white,
          fallback: Colors.black,
        ),
        Colors.black,
      );
    });
  });

  group('resolveReadableThemeTextColor（多回退）', () {
    test('候选达标时原样返回，不被任何回退替换', () {
      const candidate = Color(0xff000000);
      final resolved = resolveReadableThemeTextColor(
        candidate: candidate,
        background: Colors.white,
        fallbacks: const [Color(0xff111111), Color(0xff222222)],
      );
      // 已经可读的颜色一个字节都不该被改动。
      expect(resolved, candidate);
      expect(identical(resolved, candidate), isTrue);
    });

    test('候选达标时连 alpha 都保持原样（只有兜底才强制不透明）', () {
      const candidate = Color(0xb3ffffff); // white70
      final resolved = resolveReadableThemeTextColor(
        candidate: candidate,
        background: Colors.black,
        fallbacks: const [Color(0xff00ff00)],
      );
      expect(resolved, candidate);
      // Colors.white70 的 alpha 是 0xB3/255 ≈ 0.70196，不是 0.7。
      expect(resolved.a, closeTo(0xb3 / 0xff, 1e-9));
    });

    test('候选不足时选中第一个达标的回退色（跳过更弱的那个）', () {
      final resolved = resolveReadableThemeTextColor(
        candidate: const Color(0xffcccccc), // 白底上不可读
        background: Colors.white,
        fallbacks: const [
          Color(0xffdddddd), // 更弱，应被跳过
          Color(0xff000000), // 第一个达标
          Color(0xff0000ff),
        ],
      );
      expect(resolved, const Color(0xff000000));
    });

    test('全部候选都不足时返回对比度最高的那个，并强制 alpha = 1', () {
      final resolved = resolveReadableThemeTextColor(
        candidate: const Color(0x801a1a1a), // 半透明，黑底上不可读
        background: Colors.black,
        fallbacks: const [
          Color(0xff151515),
          Color(0xff202020), // 黑底上最亮 → 对比度最高
        ],
      );
      expect(resolved, const Color(0xff202020));
      expect(resolved.a, 1.0);
    });
    test('全部不足且回退为空时返回候选，并强制 alpha = 1', () {
      final resolved = resolveReadableThemeTextColor(
        candidate: const Color(0x801a1a1a),
        background: Colors.black,
        fallbacks: const [],
      );
      expect(resolved, const Color(0xff1a1a1a));
      expect(resolved.a, 1.0);
    });

    test('候选本身是最高的那个时不被回退顶掉', () {
      final resolved = resolveReadableThemeTextColor(
        candidate: const Color(0xff303030), // 黑底上比两个回退都亮
        background: Colors.black,
        fallbacks: const [Color(0xff101010), Color(0xff202020)],
      );
      expect(resolved, const Color(0xff303030));
      expect(resolved.a, 1.0);
    });

    test('可传 UI 阈值放宽要求', () {
      // #949494 压白底约 3.03：正文阈值（4.5）不达标 → 回退到黑；
      // 放宽到 UI 阈值（3.0）后候选自己就够格 → 原样保留。
      const candidate = Color(0xff949494);
      expect(contrastRatio(candidate, Colors.white), closeTo(3.03, .01));

      expect(
        resolveReadableThemeTextColor(
          candidate: candidate,
          background: Colors.white,
          fallbacks: const [Color(0xff000000)],
        ),
        const Color(0xff000000),
      );
      expect(
        resolveReadableThemeTextColor(
          candidate: candidate,
          background: Colors.white,
          fallbacks: const [Color(0xff000000)],
          minimumContrast: accessibleUiMinContrast,
        ),
        candidate,
      );
    });
  });

  group('压明度兜底（保留主次层次）', () {
    // 这一组钉住一个具体的坏法：次要文字在浅色玻璃上差一点不达标时，
    // 若直接换成 onSurface，次要文字与正文会同色，层次被抹平。
    // 正确行为是只推明度、保住色相，刚好达标即可。

    test('差一点不达标时压明度，而不是换成语义色', () {
      const surface = Color(0xffedebf4); // 浅色玻璃等效底
      final scheme = _lightScheme(surface);
      final body = scheme.onSurface;
      final resolved = resolveReadableThemeTextColor(
        candidate: scheme.onSurfaceVariant,
        background: surface,
        fallbacks: [body, scheme.scrim],
      );

      // 1) 达标了。
      expect(contrastRatio(resolved, surface), greaterThanOrEqualTo(4.5));
      // 2) 但没有变成正文色 —— 层次还在。
      expect(resolved, isNot(body));
      // 3) 也没有虚高：刚好压在达标线附近，不做多余的加深。
      expect(contrastRatio(resolved, surface), lessThan(6.0));
      // 4) 色相/饱和度与候选基本一致（只动了明度）。
      //    HSL 往返转换有量化漂移，实测色相差约 1 度，肉眼不可辨。
      final before = HSLColor.fromColor(scheme.onSurfaceVariant);
      final after = HSLColor.fromColor(resolved);
      expect(after.hue, closeTo(before.hue, 2.0));
      expect(after.saturation, closeTo(before.saturation, .05));
    });

    test('差得远时压明度不接手，改走语义回退色', () {
      // 黑字压在深色玻璃上：候选对比度约 1.4，远低于门槛。
      // 此时压明度只会得到一块中灰，正确做法是回退到白色。
      final resolved = resolveReadableThemeTextColor(
        candidate: Colors.black,
        background: const Color(0xff101014),
        fallbacks: const [Colors.white],
      );
      expect(resolved, Colors.white);
    });

    test('明度极值也够不到时返回 null，交给调用方回退', () {
      // 中灰底配相近的中灰候选：候选对比度仅约 1.29，远低于接近度门槛
      // （连"微调"的资格都没有），所以直接返回 null，由调用方换语义色。
      expect(
        darkenOrLightenToContrast(
          const Color(0xff6e6e6e),
          const Color(0xff808080),
          minimumContrast: 4.5,
        ),
        isNull,
      );
    });

    test('已达标时不介入（原样返回）', () {
      final nudged = darkenOrLightenToContrast(
        const Color(0xff1a1a1a),
        Colors.white,
      );
      expect(nudged, isNotNull);
      expect(contrastRatio(nudged!, Colors.white), greaterThanOrEqualTo(4.5));
    });

    test('远低于达标线时直接返回 null（不微调）', () {
      expect(
        darkenOrLightenToContrast(Colors.black, const Color(0xff101014)),
        isNull,
      );
    });
  });

  group('resolveTextColorOnSurface', () {
    test('给定等效底色即可解析可读文字色', () {
      const surface = Color(0xffedebf4);
      final resolved = resolveTextColorOnSurface(
        candidate: const Color(0xff777184), // 浅底上约 4.2
        surface: surface,
        fallbacks: const [Color(0xff302d43)],
      );
      expect(contrastRatio(resolved, surface), greaterThanOrEqualTo(4.5));
    });
  });
}