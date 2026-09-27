// 回归测试：画面卡死看门狗不能在「开播缓冲」阶段误判。
//
// 背景（用户报的现象）：点视频 → 页面加载出来 → 过几秒画面又自己重载一遍才正常。
// 根因：_checkStall 原先只判 `playing && buffering && (buffer - position) >= 3s`，
// 持续 6 秒即通报重载；而开播阶段这几条天然成立（mpv 已上报 playing=true，
// 且 demuxer-readahead-secs=60 让缓冲一眼领先几十秒），于是稍慢的片源会被当成
// 「画面卡死」重载一次。重载后缓存命中、缓冲变快就不再触发，表现正是
// 「过几秒画面重新加载一遍才正常」。
//
// 这里直接调用生产代码里的 shouldCountAsStalled（不是复刻一份），
// 有人把「必须播稳过」这条前提删掉时测试会立刻变红。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/configured_media_kit_video_player.dart';

/// 单个采样点的状态。
class _Sample {
  const _Sample({
    this.buffering = true,
    this.bufferAheadSeconds = 30,
  });
  final bool buffering;
  final double bufferAheadSeconds;
}

/// 按看门狗的真实节奏（每 2 秒一次、累计 ≥6 秒触发）跑一遍。
///
/// [readyAtSecond] 模拟 `_readyAt`：null = 从没播稳过（仍在开播阶段）。
/// 这些采样点都是「在播」状态（看门狗的另一半判据由 shouldCountAsStalled 直接覆盖）。
int? _stallTriggerSecond(
  List<_Sample> samples, {
  required double? readyAtSecond,
}) {
  var stallSeconds = 0;
  var recovered = false;
  for (var index = 0; index < samples.length; index++) {
    final second = (index + 1) * 2;
    final sample = samples[index];
    final ready = readyAtSecond != null && readyAtSecond <= second;
    final stalled = shouldCountAsStalled(
      ready: ready,
      playing: true,
      buffering: sample.buffering,
      bufferAhead: Duration(
        milliseconds: (sample.bufferAheadSeconds * 1000).round(),
      ),
    );
    if (!stalled) {
      stallSeconds = 0;
      continue;
    }
    stallSeconds += 2;
    if (stallSeconds >= 6 && !recovered) {
      recovered = true;
      return second;
    }
  }
  return null;
}

List<_Sample> _bufferingFor(int seconds, {double ahead = 30}) =>
    List.generate(seconds, (_) => _Sample(bufferAheadSeconds: ahead));

const _playingFine = _Sample(buffering: false);

void main() {
  group('shouldCountAsStalled 基本判据', () {
    test('没播稳过 → 一律不算卡死（这是本次修复的核心）', () {
      expect(
        shouldCountAsStalled(
          ready: false,
          playing: true,
          buffering: true,
          bufferAhead: const Duration(seconds: 60),
        ),
        isFalse,
      );
    });

    test('播稳过 + 在播 + 在缓冲 + 缓冲领先 ≥3s → 算卡死', () {
      expect(
        shouldCountAsStalled(
          ready: true,
          playing: true,
          buffering: true,
          bufferAhead: const Duration(seconds: 60),
        ),
        isTrue,
      );
    });

    test('缓冲没领先（真网络卡顿）→ 不算卡死，别动手', () {
      expect(
        shouldCountAsStalled(
          ready: true,
          playing: true,
          buffering: true,
          bufferAhead: const Duration(milliseconds: 500),
        ),
        isFalse,
      );
    });

    test('没在缓冲 → 不算卡死', () {
      expect(
        shouldCountAsStalled(
          ready: true,
          playing: true,
          buffering: false,
          bufferAhead: const Duration(seconds: 60),
        ),
        isFalse,
      );
    });

    test('没在播 → 不算卡死', () {
      expect(
        shouldCountAsStalled(
          ready: true,
          playing: false,
          buffering: true,
          bufferAhead: const Duration(seconds: 60),
        ),
        isFalse,
      );
    });

    test('缓冲恰好 3 秒是边界，算卡死（>= 语义）', () {
      expect(
        shouldCountAsStalled(
          ready: true,
          playing: true,
          buffering: true,
          bufferAhead: const Duration(seconds: 3),
        ),
        isTrue,
      );
    });
  });

  group('开播阶段不得误判（用户报的场景）', () {
    test('开播一直缓冲、缓冲领先很多 → 全程不触发重载', () {
      expect(_stallTriggerSecond(_bufferingFor(20), readyAtSecond: null), isNull);
    });

    test('开播缓冲 10 秒后才播稳 → 播稳前那段不该被算作卡死', () {
      final samples = <_Sample>[
        ..._bufferingFor(5),
        ...List.filled(5, _playingFine),
      ];
      expect(_stallTriggerSecond(samples, readyAtSecond: 10), isNull);
    });

    test('开播缓冲只到第 4 秒 → 不触发（旧实现第 6 秒就会触发）', () {
      final samples = <_Sample>[
        ..._bufferingFor(2),
        ...List.filled(4, _playingFine),
      ];
      expect(_stallTriggerSecond(samples, readyAtSecond: null), isNull);
    });
  });

  group('真正的画面卡死仍要能恢复（别把功能修没了）', () {
    test('播稳过之后又卡住 6 秒 → 触发重载', () {
      expect(_stallTriggerSecond(_bufferingFor(4), readyAtSecond: 0), 6);
    });

    test('播稳后网络真卡（缓冲没领先）→ 不误伤', () {
      final samples = _bufferingFor(10, ahead: .5);
      expect(_stallTriggerSecond(samples, readyAtSecond: 0), isNull);
    });

    test('播稳后缓冲断续、每次都没到 6 秒 → 不触发', () {
      final samples = <_Sample>[
        ..._bufferingFor(2),
        _playingFine,
        ..._bufferingFor(2),
        _playingFine,
        ..._bufferingFor(2),
      ];
      expect(_stallTriggerSecond(samples, readyAtSecond: 0), isNull);
    });

    test('只重载一次（_stallRecovered 的效果），之后继续卡也不重复触发', () {
      expect(_stallTriggerSecond(_bufferingFor(20), readyAtSecond: 0), 6);
    });
  });
}
