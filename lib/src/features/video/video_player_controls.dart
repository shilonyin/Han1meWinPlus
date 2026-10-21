import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_surface_tokens.dart';
import '../../core/settings.dart';
import '../../data/local/keyframe_repository.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../shared/press_scale.dart';
import 'android_cast_button.dart';
import '../../core/app_dialog.dart';
import '../shared/motion_icon.dart';
import 'player_overlay_surface.dart';
import 'player_menu_style.dart';

/// 进度条（带内边距的 Slider）在控制条里的占位高度，音量面板据此把弹层放到进度条上方。
///
/// 这里的两个滑块在深色控制条上要自己盖一套白轨道（见
/// [AppSurfaceTokens.darkTrackTheme]）。
const double _progressBarHeight = 28;

/// 悬浮控制条的最大宽度。
///
/// 控制条铺满整个画面宽度时，那条进度条会横穿底边（1280 宽窗口下约 1256px），
/// 压着画面又难看出「这是一枚浮起来的条」。给它一个上限并居中：窄窗口
/// （画中画、小窗）仍然占满可用宽度，宽窗口则收成一枚居中的圆角条。
///
/// 680 是实测出来的：按钮行内容最少要 620px（左侧四个 40px 按钮 + 197px 时间
/// 文本 ≈ 272，右侧六个菜单按钮 + 全屏/画中画 ≈ 240–320），而 `roomy` 的阈值
/// 就是 620 —— 再往下压，右侧那排菜单会被收进「更多」，用户会看到按钮凭空少掉。
const double kPlayerControlsMaxWidth = 680;

/// 悬浮控制条离画面左右边与底边的距离。
///
/// 控制条不再贴底通栏，而是浮在画面上的一枚圆角条：留出这段距离才有「悬浮」
/// 的观感，它同时也是暂停标记等浮层的定位基准。
const double kPlayerControlsInset = 12;

/// 按钮行里每个按钮的**实际**边长，以及整行的底部内边距。
///
/// 这一行的高度不是画出来的，是每个 IconButton 把它撑开的：默认 `minimumSize`
/// 是 40×40、点击区 48，整行就顶到 48 高，光改常量压不下去。真正生效的是 build
/// 收口处那个 `IconButtonTheme`，这里只声明「我们要多高」。
const double _buttonRowHeight = 30;
const double _buttonRowPadding = 2;

/// `VisualDensity.compact` 从 `minimumSize` 每边收掉的像素。
///
/// 行内按钮都带 compact，实测 `minimumSize: 38` 出来的是 30 —— 想要
/// [_buttonRowHeight] 这个真实尺寸，主题里得写成 `_buttonRowHeight + 8`。
const double _compactDensityInset = 8;

/// 悬浮控制条的整体高度（进度条 + 按钮行）。
///
/// 由 [_progressBarHeight] 与按钮行推出来，不要再手写数字：需要避让控制条的
/// 浮层（曾经是暂停标记）用它当基准，差几个像素看不出来，少算就会和控制条叠在一起。
const double kPlayerControlsHeight =
    _progressBarHeight + _buttonRowHeight + _buttonRowPadding;

/// 音量面板的固定尺寸（大约是半尺寸，不要占满播放器）与和进度条之间的间距。
/// 选集面板最多露出的高度（四集）。
///
/// 每项高度由 TextButton 的 `minimumSize` 40 撑开，四集 160 正好。
/// 超出的集数在面板内部滚动，滚出圆角的部分由 `ClipRRect` 裁掉。
const double _episodeMenuMaxHeight = 160;

const double _volumePanelWidth = 40;
const double _volumePanelHeight = 100;
const double _volumePanelGap = 8;

/// 竖排滑杆的长度与宽度（旋转 270° 后长度就是面板里的竖向轨道）。
const double _volumeSliderLength = 70;
const double _volumeSliderThickness = 30;

class VideoPlayerControls extends StatelessWidget {
  const VideoPlayerControls({
    required this.controller,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onInteraction,
    required this.video,
    required this.quality,
    required this.onQualitySelected,
    required this.onSuperResolutionSelected,
    this.onNext,
    this.onEpisodeSelected,
    this.onFloat,
    super.key,
  });
  final VideoPlayerController controller;
  final bool fullscreen;
  final Future<void> Function() onFullscreen;
  final VoidCallback onInteraction;
  final VideoDetail video;
  final ValueListenable<String?> quality;
  final ValueChanged<VideoSource> onQualitySelected;
  final ValueChanged<SuperResolutionMode> onSuperResolutionSelected;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;

  /// 弹出系统级悬浮窗（独立窗口）。非桌面端不传。
  final VoidCallback? onFloat;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: kPlayerControlsInset,
    // 悬浮圆角条：半透明黑底 + 背景模糊，压在视频画面上而不遮满底部。
    //
    // 不再用贴底通栏的渐隐底衬（[ProgressiveFade.bottomSolid]）：那条把画面
    // 下半截整体压暗，和「浮起来的一枚控制条」是两种观感。
    // 居中并限宽：宽窗口下它是一枚居中的条，窄窗口下仍占满可用宽度。
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kPlayerControlsMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPlayerControlsInset),
          child: PlayerOverlaySurface(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final l10n = AppLocalizations.of(context)!;
                final progress = value.duration == Duration.zero
                    ? 0.0
                    : value.position.inMilliseconds /
                          value.duration.inMilliseconds;
                // 已缓冲到的位置：直接画在进度条轨道上，卡住时一眼能看出
                // 是「缓冲没跟上」还是别的问题（比如解码/渲染卡住时缓冲条是跑在前面的）。
                final buffered = value.buffered.isEmpty
                    ? Duration.zero
                    : value.buffered.last.end;
                final bufferedFraction = value.duration.inMilliseconds == 0
                    ? 0.0
                    : (buffered.inMilliseconds / value.duration.inMilliseconds)
                          .clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _progressBarHeight,
                      child: SliderTheme(
                        data: AppSurfaceTokens.darkTrackTheme.copyWith(
                          trackHeight: 3,
                          trackShape: _BufferedTrackShape(
                            fraction: bufferedFraction,
                          ),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          // 2024 版的轨道要让开 6px 的缺口：播放头（白竖条）齐到轨道端点时
                          // 会压进缝里，改用形状齐平、没有缺口的 2023 版轨道。
                          // 只有浮动标签那类样式在 2024 版，这里显式补上和 2023 版一样的两种形状。
                          valueIndicatorShape:
                              const DropSliderValueIndicatorShape(),
                          valueIndicatorColor: Colors.white,
                          valueIndicatorTextStyle: TextStyle(
                            color: Colors.black.withValues(alpha: 0.87),
                          ),
                          year2023: true,
                        ),
                        child: Slider(
                          value: progress.clamp(0, 1).toDouble(),
                          onChanged: (next) {
                            controller.seekTo(
                              Duration(
                                milliseconds:
                                    (next * value.duration.inMilliseconds)
                                        .round(),
                              ),
                            );
                            onInteraction();
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        8,
                        0,
                        8,
                        _buttonRowPadding,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // 窄窗口下把冷门操作收进「更多」，避免图标行溢出
                          final roomy = constraints.maxWidth >= 620;
                          // 画中画小窗（380 逻辑像素）里，7 个 48px 按钮加时间文本要 440px，
                          // 必然溢出、右侧的全屏/画中画被裁掉。用 IconButtonTheme 把这一行的
                          // 按钮统一收到 32px —— Skip 与音量是各自独立的组件，只有主题能一次
                          // 改到它们内部的 IconButton。
                          final tight = constraints.maxWidth < 420;
                          final row = Row(
                            children: [
                              PressScale(
                                child: IconButton(
                                  color: Colors.white,
                                  tooltip: value.isPlaying
                                      ? l10n.pause
                                      : l10n.play,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    value.isPlaying
                                        ? controller.pause()
                                        : controller.play();
                                    onInteraction();
                                  },
                                  icon: MotionStateIcon(
                                    icon: value.isPlaying
                                        ? Symbols.pause_rounded
                                        : Symbols.play_arrow_rounded,
                                  ),
                                ),
                              ),
                              if (onNext != null)
                                PressScale(
                                  child: IconButton(
                                    color: Colors.white,
                                    tooltip: l10n.autoPlayNext,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onNext,
                                    icon: const Icon(Symbols.skip_next_rounded),
                                  ),
                                ),
                              // 快进按钮：从顶部条移到左下角控制行
                              VideoPlayerSkipButton(
                                controller: controller,
                                onInteraction: onInteraction,
                              ),
                              VideoPlayerVolumeButton(
                                controller: controller,
                                onInteraction: onInteraction,
                              ),
                              // 时间文本：固定宽度，不参与 flex。
                              //
                              // 实测（test/player_controls_alignment_test.dart）：把它包进
                              // Flexible(flex:1) 会与后面的 Spacer(flex:1) 平分剩余空间，
                              // 窄窗口下确实能自动收缩防溢出，但**宽窗口下会让整行铺不满、
                              // 右侧按钮离开右缘上百像素**（1000 逻辑像素时实测偏 130.8px）。
                              // 实测时间文本自身宽度 197.3px 在任何宽度下都够用，真正会溢出
                              // 的是右侧那一组菜单，所以防溢出交给下面的 Expanded，而不是这里。
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              // 右侧按钮组：吃掉剩余空间并右对齐。
                              //
                              // 用 Expanded + Align 而不是「Spacer + 固定子节点」：Expanded 会把
                              // 剩余宽度全部拿走后交给 Align 右对齐，右侧按钮因此始终贴右缘；
                              // 而里面加一层 SingleChildScrollView(horizontal) 让**极窄窗口**下
                              // 按钮组自己可横向滚动，而不是把这一行撑破（原 Flexible 写法的用意）。
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    reverse: true,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (roomy) ...[
                                          _AspectMenu(),
                                          if (onEpisodeSelected != null &&
                                              video.playlist.isNotEmpty)
                                            _EpisodeMenu(
                                              video: video,
                                              onSelected: onEpisodeSelected!,
                                            ),
                                          _Anime4KMenu(
                                            onSelected:
                                                onSuperResolutionSelected,
                                          ),
                                          if (video.sources.isNotEmpty)
                                            _QualityMenu(
                                              sources: video.sources,
                                              quality: quality,
                                              onSelected: onQualitySelected,
                                            ),
                                          _SpeedMenu(
                                            controller: controller,
                                            onInteraction: onInteraction,
                                          ),
                                          AndroidCastButton(
                                            sources: video.sources,
                                            quality: quality,
                                          ),
                                        ] else
                                          VideoPlayerPortraitMoreMenu(
                                            controller: controller,
                                            video: video,
                                            quality: quality,
                                            onQualitySelected:
                                                onQualitySelected,
                                            onSuperResolutionSelected:
                                                onSuperResolutionSelected,
                                          ),
                                        PressScale(
                                          child: IconButton(
                                            color: Colors.white,
                                            tooltip: fullscreen
                                                ? l10n.exitFullscreen
                                                : l10n.fullscreenPlayback,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: onFullscreen,
                                            icon: Icon(
                                              fullscreen
                                                  ? Symbols
                                                        .fullscreen_exit_rounded
                                                  : Symbols.fullscreen_rounded,
                                            ),
                                          ),
                                        ),
                                        if (onFloat != null)
                                          PressScale(
                                            child: IconButton(
                                              color: Colors.white,
                                              tooltip: l10n.floatWindow,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: onFloat,
                                              icon: const Icon(
                                                Symbols
                                                    .picture_in_picture_rounded,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                          // 整行统一套一遍尺寸：IconButton 默认 40 的框 + 48 的点击区，
                          // 这一行就被撑到 48 高，压不下去。compact 还会每边再收 8，
                          // 所以 minimumSize 要写 edge + 8，出来的实际边长才等于 edge。
                          // `tight`（画中画 380px）再紧一档，否则 7 个按钮加时间文本必然溢出。
                          final edge = tight ? 24.0 : _buttonRowHeight;
                          final box = edge + _compactDensityInset;
                          return IconButtonTheme(
                            data: IconButtonThemeData(
                              style: ButtonStyle(
                                minimumSize: WidgetStatePropertyAll(
                                  Size(box, box),
                                ),
                                padding: const WidgetStatePropertyAll(
                                  EdgeInsets.zero,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            child: row,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// 在原本的进度条轨道下面先画一段「已缓冲」的亮色。
///
/// 画在原本的轨道之前，所以未播放的半透明轨道会盖在上面（变成稍亮的一段），
/// 已播放的白色段照旧盖在最上层：视觉上就是常见在线视频的
/// 「已播放 / 已缓冲 / 未加载」三段。
class _BufferedTrackShape extends RoundedRectSliderTrackShape {
  const _BufferedTrackShape({required this.fraction});

  /// 已缓冲比例（0-1）。
  final double fraction;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final width = rect.width * fraction.clamp(0.0, 1.0);
    if (width > 0 && rect.height > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, width, rect.height),
          Radius.circular(rect.height / 2),
        ),
        Paint()..color = Colors.white54,
      );
    }
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }
}

/// 左下角的音量入口：点开后用竖排滑杆调音量（桌面端调的是播放器音量）。
class VideoPlayerVolumeButton extends StatelessWidget {
  const VideoPlayerVolumeButton({
    required this.controller,
    required this.onInteraction,
    super.key,
  });
  final VideoPlayerController controller;
  final VoidCallback onInteraction;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, value, _) => MenuAnchor(
      // 控制条贴在播放器底部，音量面板固定弹在按钮正上方（对齐按钮左上角）
      // 半透明圆角面板，压在进度条上方而不是盖住它
      style: playerMenuPanelStyle(alignment: Alignment.topLeft),
      menuChildren: playerMenuPanel(
        [
          SizedBox(
            width: _volumePanelWidth,
            height: _volumePanelHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 6, 5, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    height: _volumeSliderLength,
                    // 旋转 270° 让滑杆变成下小上大的竖条
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SizedBox(
                        width: _volumeSliderLength,
                        height: _volumeSliderThickness,
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: controller,
                          builder: (context, current, _) => SliderTheme(
                            data: AppSurfaceTokens.darkTrackTheme.copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10,
                              ),
                              inactiveTrackColor: Colors.white30,
                              year2023: true,
                            ),
                            child: Slider(
                              value: current.volume.clamp(0.0, 1.0).toDouble(),
                              onChanged: (next) {
                                controller.setVolume(next);
                                onInteraction();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, current, _) => Text(
                      '${(current.volume.clamp(0.0, 1.0) * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        radius: AppRadius.md,
        padding: EdgeInsets.zero,
      ),
      builder: (context, menu, child) => PressScale(
        child: IconButton(
          color: Colors.white,
          visualDensity: VisualDensity.compact,
          tooltip: AppLocalizations.of(context)!.volume,
          // 用 position 直接指定弹层位置：面板顶边 = 按钮顶边 - (面板高度 + 进度条高度 + 间距)，也就是让它停在进度条上方
          onPressed: () => menu.isOpen
              ? menu.close()
              : menu.open(
                  position: const Offset(
                    (_buttonRowHeight - _volumePanelWidth) / 2,
                    -(_volumePanelHeight +
                        _progressBarHeight +
                        _volumePanelGap),
                  ),
                ),
          icon: Icon(
            value.volume <= 0
                ? Symbols.volume_off_rounded
                : (value.volume < .5
                      ? Symbols.volume_down_rounded
                      : Symbols.volume_up_rounded),
          ),
        ),
      ),
    ),
  );
}

class VideoPlayerSkipButton extends ConsumerWidget {
  const VideoPlayerSkipButton({
    required this.controller,
    required this.onInteraction,
    super.key,
  });
  final VideoPlayerController controller;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(settingsProvider).valueOrNull?.skipSeconds ?? 80;
    return GestureDetector(
      onLongPress: () => _configure(context, ref, seconds),
      child: PressScale(
        child: IconButton(
          color: Colors.white,
          tooltip: AppLocalizations.of(context)!.seconds(seconds),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final value = controller.value;
            final target = (value.position.inSeconds + seconds).clamp(
              0,
              value.duration.inSeconds,
            );
            controller.seekTo(Duration(seconds: target));
            onInteraction();
          },
          icon: const Icon(Symbols.forward_10_rounded),
        ),
      ),
    );
  }

  Future<void> _configure(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final result = await showAppDialog<int>(
      context: context,
      builder: (_) => _SkipSecondsDialog(initialValue: '$current'),
    );
    if (result != null && result > 0) {
      await ref
          .read(settingsProvider.notifier)
          .saveChanges((settings) => settings.copyWith(skipSeconds: result));
    }
  }
}

class _SkipSecondsDialog extends StatefulWidget {
  const _SkipSecondsDialog({required this.initialValue});
  final String initialValue;

  @override
  State<_SkipSecondsDialog> createState() => _SkipSecondsDialogState();
}

class _SkipSecondsDialogState extends State<_SkipSecondsDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.seconds(int.tryParse(widget.initialValue) ?? 0)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(_controller.text.trim())),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}

class _AspectMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspect =
        ref.watch(settingsProvider).valueOrNull?.videoAspectRatio ??
        VideoAspectRatio.auto;
    return MenuAnchor(
      style: playerMenuPanelStyle(),
      builder: (context, controller, child) => PressScale(
        child: IconButton(
          color: Colors.white,
          tooltip: AppLocalizations.of(context)!.videoAspectRatio,
          onPressed: controller.open,
          icon: const Icon(Symbols.aspect_ratio_rounded),
        ),
      ),
      menuChildren: playerMenuPanel(
        VideoAspectRatio.values
            .map(
              (item) => playerMenuItem(
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .saveChanges(
                      (settings) => settings.copyWith(videoAspectRatio: item),
                    ),
                selected: item == aspect,
                child: Text(_aspectLabel(AppLocalizations.of(context)!, item)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _EpisodeMenu extends StatelessWidget {
  const _EpisodeMenu({required this.video, required this.onSelected});
  final VideoDetail video;
  final ValueChanged<VideoCard> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: playerMenuPanelStyle(),
    builder: (context, controller, child) => PressScale(
      child: IconButton(
        color: Colors.white,
        tooltip: AppLocalizations.of(context)!.episodeList,
        onPressed: controller.open,
        icon: const Icon(Symbols.view_list_rounded),
      ),
    ),
    menuChildren: playerMenuPanel(
      // 一集 40 高（TextButton 的 minimumSize），露出四集就够翻页了；
      // 集数多的番有几十集，不限高会一路长到屏幕外。
      maxHeight: _episodeMenuMaxHeight,
      video.playlist
          .map(
            (episode) => playerMenuItem(
              onPressed: episode.id == video.id
                  ? null
                  : () => onSelected(episode),
              selected: episode.id == video.id,
              // 标题自己顶宽把整个面板撑到画外去了：给个上限，短的按内容宽，
              // 长的截断。上限取原来 280 的一半。
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class VideoPlayerPortraitMoreMenu extends ConsumerWidget {
  const VideoPlayerPortraitMoreMenu({
    required this.controller,
    required this.video,
    required this.quality,
    required this.onQualitySelected,
    required this.onSuperResolutionSelected,
    super.key,
  });
  final VideoPlayerController controller;
  final VideoDetail video;
  final ValueListenable<String?> quality;
  final ValueChanged<VideoSource> onQualitySelected;
  final ValueChanged<SuperResolutionMode> onSuperResolutionSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final aspect = settings?.videoAspectRatio ?? VideoAspectRatio.auto;
    final superResolution =
        settings?.superResolutionMode ?? SuperResolutionMode.off;
    // 画质和倍速在外面是 ValueListenable：子菜单展开后改这两项，
    // 这里不跟着重建的话高亮那一行会留在旧值上。
    return ListenableBuilder(
      listenable: Listenable.merge([controller, quality]),
      builder: (context, _) => MenuAnchor(
        style: playerMenuPanelStyle(),
        builder: (context, menu, child) => PressScale(
          child: IconButton(
            color: Colors.white,
            tooltip: AppLocalizations.of(context)!.more,
            onPressed: menu.open,
            icon: const Icon(Symbols.more_vert_rounded),
          ),
        ),
        menuChildren: playerMenuPanel([
          playerSubmenu(
            menuChildren: VideoAspectRatio.values
                .map(
                  (item) => playerMenuItem(
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .saveChanges(
                          (settings) =>
                              settings.copyWith(videoAspectRatio: item),
                        ),
                    selected: item == aspect,
                    child: Text(
                      _aspectLabel(AppLocalizations.of(context)!, item),
                    ),
                  ),
                )
                .toList(),
            child: Text(AppLocalizations.of(context)!.videoAspectRatio),
          ),
          playerSubmenu(
            menuChildren: <double>[.5, .75, 1, 1.25, 1.5, 2, 3]
                .map(
                  (speed) => playerMenuItem(
                    onPressed: () => controller.setPlaybackSpeed(speed),
                    selected: controller.value.playbackSpeed == speed,
                    child: Text('${speed}x'),
                  ),
                )
                .toList(),
            child: Text(AppLocalizations.of(context)!.playbackSpeed),
          ),
          playerSubmenu(
            menuChildren: SuperResolutionMode.values
                .map(
                  (mode) => playerMenuItem(
                    onPressed: () => onSuperResolutionSelected(mode),
                    selected: mode == superResolution,
                    child: Text(
                      _superResolutionLabel(
                        AppLocalizations.of(context)!,
                        mode,
                      ),
                    ),
                  ),
                )
                .toList(),
            child: Text(AppLocalizations.of(context)!.superResolution),
          ),
          if (video.sources.isNotEmpty)
            playerSubmenu(
              menuChildren: video.sources
                  .map(
                    (source) => playerMenuItem(
                      onPressed: () => onQualitySelected(source),
                      selected: source.quality == quality.value,
                      child: Text(source.quality),
                    ),
                  )
                  .toList(),
              child: Text(AppLocalizations.of(context)!.quality),
            ),
          if (video.sources.isNotEmpty)
            playerMenuItem(
              onPressed: () => _openExternal(video.sources, quality.value),
              leadingIcon: const Icon(Symbols.open_in_new_rounded),
              child: Text(AppLocalizations.of(context)!.externalPlayback),
            ),
        ]),
      ),
    );
  }

  Future<void> _openExternal(List<VideoSource> sources, String? current) async {
    final source =
        sources.where((source) => source.quality == current).firstOrNull ??
        sources.first;
    await launchUrl(
      Uri.parse(source.url),
      mode: LaunchMode.externalApplication,
    );
  }
}

class VideoPlayerFullscreenMoreMenu extends StatelessWidget {
  const VideoPlayerFullscreenMoreMenu({
    required this.sources,
    required this.quality,
    super.key,
  });
  final List<VideoSource> sources;
  final ValueListenable<String?> quality;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: playerMenuPanelStyle(),
    builder: (context, menu, child) => PressScale(
      child: IconButton(
        color: Colors.white,
        tooltip: AppLocalizations.of(context)!.more,
        onPressed: menu.open,
        icon: const Icon(Symbols.more_vert_rounded),
      ),
    ),
    menuChildren: playerMenuPanel([
      if (sources.isNotEmpty)
        playerMenuItem(
          onPressed: () => _openExternal(),
          leadingIcon: const Icon(Symbols.open_in_new_rounded),
          child: Text(AppLocalizations.of(context)!.externalPlayback),
        ),
    ]),
  );

  Future<void> _openExternal() async {
    final source =
        sources
            .where((source) => source.quality == quality.value)
            .firstOrNull ??
        sources.first;
    await launchUrl(
      Uri.parse(source.url),
      mode: LaunchMode.externalApplication,
    );
  }
}

String _superResolutionLabel(AppLocalizations l10n, SuperResolutionMode mode) =>
    switch (mode) {
      SuperResolutionMode.off => l10n.superResolutionOff,
      SuperResolutionMode.efficiency => l10n.superResolutionEfficiency,
      SuperResolutionMode.quality => l10n.superResolutionQuality,
      SuperResolutionMode.natural => l10n.superResolutionNatural,
    };

String _aspectLabel(AppLocalizations l10n, VideoAspectRatio aspect) =>
    switch (aspect) {
      VideoAspectRatio.auto => l10n.aspectAuto,
      VideoAspectRatio.crop => l10n.aspectCrop,
      VideoAspectRatio.stretch => l10n.aspectStretch,
      VideoAspectRatio.ratio4x3 => l10n.aspectFourThree,
    };

class _Anime4KMenu extends ConsumerWidget {
  const _Anime4KMenu({required this.onSelected});

  final ValueChanged<SuperResolutionMode> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode =
        ref.watch(settingsProvider).valueOrNull?.superResolutionMode ??
        SuperResolutionMode.off;
    final l10n = AppLocalizations.of(context)!;
    return MenuAnchor(
      style: playerMenuPanelStyle(),
      builder: (context, menu, child) => PressScale(
        child: IconButton(
          color: Colors.white,
          tooltip: l10n.superResolution,
          onPressed: menu.open,
          icon: Icon(
            mode == SuperResolutionMode.off
                ? Symbols.auto_awesome_rounded
                : Symbols.auto_awesome_rounded,
          ),
        ),
      ),
      menuChildren: playerMenuPanel(
        SuperResolutionMode.values.map((option) {
          final selected = option == mode;
          return playerMenuItem(
            onPressed: () => onSelected(option),
            selected: selected,
            child: Text(_superResolutionLabel(l10n, option)),
          );
        }).toList(),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return duration.inHours > 0
      ? '${duration.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}

class _QualityMenu extends StatelessWidget {
  const _QualityMenu({
    required this.sources,
    required this.quality,
    required this.onSelected,
  });
  final List<VideoSource> sources;
  final ValueListenable<String?> quality;
  final ValueChanged<VideoSource> onSelected;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: quality,
    builder: (context, current, _) => MenuAnchor(
      style: playerMenuPanelStyle(),
      builder: (context, menu, child) => PressScale(
        child: IconButton(
          color: Colors.white,
          tooltip: AppLocalizations.of(context)!.quality,
          onPressed: menu.open,
          icon: const Icon(Symbols.high_quality_rounded),
        ),
      ),
      menuChildren: playerMenuPanel(
        sources.map((source) {
          final selected = source.quality == current;
          return playerMenuItem(
            onPressed: () => onSelected(source),
            selected: selected,
            child: Text(source.quality),
          );
        }).toList(),
      ),
    ),
  );
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({required this.controller, required this.onInteraction});
  final VideoPlayerController controller;
  final VoidCallback onInteraction;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) => MenuAnchor(
          style: playerMenuPanelStyle(),
          builder: (context, menu, child) => PressScale(
            child: IconButton(
              color: Colors.white,
              tooltip: AppLocalizations.of(context)!.playbackSpeed,
              onPressed: menu.open,
              icon: const Icon(Symbols.speed_rounded),
            ),
          ),
          menuChildren: playerMenuPanel(
            <double>[.5, .75, 1, 1.25, 1.5, 2, 3].map((speed) {
              final selected = value.playbackSpeed == speed;
              return playerMenuItem(
                onPressed: () {
                  controller.setPlaybackSpeed(speed);
                  onInteraction();
                },
                selected: selected,
                child: Text('${speed}x'),
              );
            }).toList(),
          ),
        ),
      );
}

class VideoKeyframeDrawer extends ConsumerWidget {
  const VideoKeyframeDrawer({
    required this.video,
    required this.controller,
    super.key,
  });
  final VideoDetail video;
  final ValueListenable<VideoPlayerController?> controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyframes =
        ref.watch(keyframesProvider(video.id)).valueOrNull ?? const <int>[];
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(AppLocalizations.of(context)!.keyframes),
              subtitle: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: keyframes.isEmpty
                  ? Center(
                      child: Text(AppLocalizations.of(context)!.noKeyframes),
                    )
                  : ListView.separated(
                      itemCount: keyframes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final position = keyframes[index];
                        return ListTile(
                          title: Text(_formatKeyframe(position)),
                          subtitle: Text('$position ms'),
                          onTap: () {
                            controller.value?.seekTo(
                              Duration(milliseconds: position),
                            );
                            Navigator.of(context).pop();
                          },
                          trailing: PressScale(
                            child: IconButton(
                              icon: const Icon(Symbols.delete_rounded),
                              onPressed: () => ref
                                  .read(keyframesProvider(video.id).notifier)
                                  .remove(position),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatKeyframe(int positionMs) {
    final position = Duration(milliseconds: positionMs);
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return position.inHours > 0
        ? '${position.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}
