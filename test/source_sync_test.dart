// 回归测试：设置异步就绪时，播放器不得「先用 fallback 加载一遍、再重建」。
//
// 背景（用户报的现象）：点视频 → 加载出来 → 过几秒画面又重来一遍，且每次必现。
// 根因：进播放页时 settingsProvider 还是 AsyncLoading（它的 build() 里要做一次
// 网络地址探测），_syncSource 以前直接 `?? 720` 先加载 720 片源；等设置就绪后
// build() 里的 ref.listen 再次触发同步，这回解析出用户真实偏好（如 1080），与
// 已加载画质不同 —— 播放器整个重建。只要偏好 != 720 就每次都发生。
//
// 这里直接调用生产代码的 pickSourceToLoad（不是复刻），把这条不变量锁住。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/video/video_player_panel.dart';

VideoSource _source(String quality) =>
    VideoSource(quality: quality, url: 'https://example.com/$quality.mp4');

final _sources = [_source('1080'), _source('720'), _source('480')];

void main() {
  group('设置未就绪时不得先加载一遍（用户报的场景）', () {
    test('settingsProvider 仍在加载 → 不选源（修复的核心）', () {
      expect(
        pickSourceToLoad(
          sources: _sources,
          preferredQuality: null, // AsyncLoading
          settingsHasError: false,
        ),
        isNull,
      );
    });

    test('对比旧行为：拿 720 兜底会选中 720，而用户偏好其实是 1080', () {
      // 旧代码等价于 preferredQuality: 720，于是「先 720、后就绪换 1080」两次加载。
      final byFallback = pickSourceToLoad(
        sources: _sources,
        preferredQuality: 720,
        settingsHasError: false,
      );
      final afterReady = pickSourceToLoad(
        sources: _sources,
        preferredQuality: 1080,
        settingsHasError: false,
      );
      expect(byFallback?.quality, '720');
      expect(afterReady?.quality, '1080');
      expect(
        byFallback?.quality,
        isNot(afterReady?.quality),
        reason: '两次选源不同 = 播放器会被重建一次',
      );
    });

    test('设置就绪后直接用真实偏好，只加载一次', () {
      expect(
        pickSourceToLoad(
          sources: _sources,
          preferredQuality: 1080,
          settingsHasError: false,
        )?.quality,
        '1080',
      );
    });

    test('设置读取出错时用 720 兜底（不能让播放器停在加载态）', () {
      expect(
        pickSourceToLoad(
          sources: _sources,
          preferredQuality: null,
          settingsHasError: true,
        )?.quality,
        '720',
      );
    });
  });

  group('选源的基本行为', () {
    test('用户手动选过画质 → 以手动选择为准', () {
      expect(
        pickSourceToLoad(
          sources: _sources,
          preferredQuality: 1080,
          settingsHasError: false,
          selectedQuality: '480',
        )?.quality,
        '480',
      );
    });

    test('没有精确匹配 → 取最接近的', () {
      expect(
        pickSourceToLoad(
          sources: [_source('1080'), _source('480')],
          preferredQuality: 720,
          settingsHasError: false,
        )?.quality,
        '480',
      );
    });

    test('画质标签带单位（1080p）也能解析', () {
      expect(
        pickSourceToLoad(
          sources: [_source('1080p'), _source('720p')],
          preferredQuality: 720,
          settingsHasError: false,
        )?.quality,
        '720p',
      );
    });

    test('已加载的就是目标画质 → 返回 null，不重复加载', () {
      expect(
        pickSourceToLoad(
          sources: _sources,
          preferredQuality: 1080,
          settingsHasError: false,
          loadedQuality: '1080',
        ),
        isNull,
      );
    });

    test('没有片源 → 返回 null（交给调用方走清空分支）', () {
      expect(
        pickSourceToLoad(
          sources: const [],
          preferredQuality: 1080,
          settingsHasError: false,
        ),
        isNull,
      );
    });

    test('偏好高于所有片源 → 取最高画质', () {
      expect(
        pickSourceToLoad(
          sources: [_source('720'), _source('480')],
          preferredQuality: 2160,
          settingsHasError: false,
        )?.quality,
        '720',
      );
    });
  });
}
