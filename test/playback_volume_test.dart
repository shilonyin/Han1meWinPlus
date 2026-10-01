// 回归测试：播放器音量持久化。
//
// 背景（用户报的问题）：调低音量后，下次打开视频又变回满音量。
// 根因：`VideoPlayerController` 的默认音量就是 1.0（满），而应用从没把用户
// 调过的音量存下来——settings 里原本连音量字段都没有。
//
// 修复：新增 `playbackVolume` 字段（0–1）。新建播放器时在
// `_applyPlaybackPreferences` 里恢复它；调整音量时经 `_persistVolumeIfChanged`
// 防抖写回。本文件锁住 settings 层的序列化与默认值，确保「存了能读回、
// 老配置不崩、越界被钳制」。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';

void main() {
  group('playbackVolume 序列化', () {
    test('默认值是满音量 1.0（与 VideoPlayerController 的默认一致）', () {
      expect(const AppSettings().playbackVolume, 1.0);
    });

    test('写入后能原样读回（toJson → fromJson 往返）', () {
      const original = AppSettings(playbackVolume: 0.35);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.playbackVolume, closeTo(0.35, 0.001));
    });

    test('老配置没有该字段时回退到满音量，不崩', () {
      // 模拟用户升级前的 setting.json：没有 playbackVolume 这个键。
      final json = <String, dynamic>{};
      final settings = AppSettings.fromJson(json);
      expect(settings.playbackVolume, 1.0, reason: '老配置缺失时必须回退到默认满音量，而不是 0（静音）');
    });

    test('越界值被钳制到 0–1', () {
      final loud = AppSettings.fromJson({'playbackVolume': 5.0});
      expect(loud.playbackVolume, 1.0, reason: '超过 1 应钳到 1');
      final negative = AppSettings.fromJson({'playbackVolume': -0.5});
      expect(negative.playbackVolume, 0.0, reason: '负值应钳到 0');
    });

    test('copyWith 能正确覆盖与保留', () {
      const base = AppSettings(playbackVolume: 0.5);
      final changed = base.copyWith(playbackVolume: 0.8);
      expect(changed.playbackVolume, closeTo(0.8, 0.001));
      final unchanged = base.copyWith(defaultPlaybackSpeed: 2.0);
      expect(unchanged.playbackVolume, closeTo(0.5, 0.001), reason: 'copyWith 不传该参数时应保留原值');
    });
  });

  group('与现有播放偏好的关系', () {
    test('playbackVolume 与 defaultPlaybackSpeed 互不干扰', () {
      const settings = AppSettings(playbackVolume: 0.3, defaultPlaybackSpeed: 1.5);
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.playbackVolume, closeTo(0.3, 0.001));
      expect(restored.defaultPlaybackSpeed, closeTo(1.5, 0.001));
    });
  });
}
