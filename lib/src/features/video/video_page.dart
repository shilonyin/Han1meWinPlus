import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_theme.dart';
import '../../core/play_window_title_target.dart';
import '../../core/window_chrome.dart';
import '../../data/local/library_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../domain/models/video.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import 'video_comments.dart';
import 'video_controller.dart';
import 'video_page_layout.dart';

VideoCard? nextEpisode(VideoDetail video) {
  final episodes = video.playlist;
  final index = episodes.indexWhere((episode) => episode.id == video.id);
  if (index >= 0 && index + 1 < episodes.length) return episodes[index + 1];
  return episodes.firstWhere(
    (episode) => episode.id != video.id,
    orElse: () => const VideoCard(id: '', title: '', coverUrl: ''),
  );
}

/// 与 [nextEpisode] 对称的上一集；已经是第一集时不返回（与下一集的行为一致）。
VideoCard? previousEpisode(VideoDetail video) {
  final episodes = video.playlist;
  final index = episodes.indexWhere((episode) => episode.id == video.id);
  if (index > 0) return episodes[index - 1];
  if (index < 0) return null;
  return episodes.lastWhere(
    (episode) => episode.id != video.id,
    orElse: () => const VideoCard(id: '', title: '', coverUrl: ''),
  );
}

void _playNext(BuildContext context, VideoDetail video) {
  final next = nextEpisode(video);
  if (next == null || next.id.isEmpty) return;
  context.pushReplacement('/video/${next.id}');
}

void _playPrevious(BuildContext context, VideoDetail video) {
  final previous = previousEpisode(video);
  if (previous == null || previous.id.isEmpty) return;
  context.pushReplacement('/video/${previous.id}');
}

void _playEpisode(BuildContext context, VideoCard episode) {
  if (episode.id.isEmpty) return;
  context.pushReplacement('/video/${episode.id}');
}

class VideoPage extends ConsumerStatefulWidget {
  const VideoPage({
    super.key,
    required this.id,
    this.localVideo,
    this.onBack,
    this.onHome,
    this.inPlayWindow = false,
  });

  final String id;
  final VideoDetail? localVideo;

  /// 覆盖默认的「返回上一页 / 回主页」；独立播放窗口传「关掉本窗口 / 唤起主窗口」。
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  /// 是否运行在独立播放窗口里。
  ///
  /// 为真时做两件事：把标题 / 上下集可用性登记给窗口那条顶部栏
  /// （[PlayWindowTitleTarget]，见 play_window_title_bar.dart），并隐去播放器自带的
  /// 顶部条——窗口那条已经含「回到主界面 / 上下集 / 标题」，再叠一条会出现两个
  /// 返回键和两行标题。
  final bool inPlayWindow;

  @override
  ConsumerState<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<VideoPage> {
  @override
  void initState() {
    super.initState();
    // 播放页是沉浸页：让应用内标题栏也跟着变深（见 WindowChrome.immersivePage）。
    WindowChrome.enterImmersivePage();
  }

  @override
  void dispose() {
    if (widget.inPlayWindow) PlayWindowTitleTarget.clear(this);
    WindowChrome.leaveImmersivePage();
    super.dispose();
  }

  /// 把当前视频的标题与上下集可用性同步给窗口顶部栏。
  ///
  /// 放在 build 之后（数据到了才有 VideoDetail）：videoDetailProvider 冷启动时是
  /// loading，标题要等详情回来才能填；每次详情变化都重报一次，换集时标题跟着更新。
  ///
  /// 必须走 addPostFrameCallback：这些是 ValueNotifier，而顶部栏正用
  /// ValueListenableBuilder 监听它们。在 build 期间改值会同步标脏那个 builder，
  /// Flutter 会抛「setState() or markNeedsBuild() called during build」。
  ///
  /// 用一个 id 去重：build 每帧都可能被调用，不去重就会每帧排一个回调。
  String? _publishedVideoId;

  void _publishTitleInfo(VideoDetail video) {
    if (_publishedVideoId == video.id) return;
    _publishedVideoId = video.id;
    final previous = previousEpisode(video);
    final next = nextEpisode(video);
    final hasPrevious = previous != null && previous.id.isNotEmpty;
    final hasNext = next != null && next.id.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PlayWindowTitleTarget.register(
        owner: this,
        title: video.title,
        hasPrevious: hasPrevious,
        hasNext: hasNext,
        // 换集在窗口内导航（与播放页里的「下一集」行为一致）。
        onPrevious: hasPrevious
            ? () => context.pushReplacement('/video/${previous.id}')
            : null,
        onNext: hasNext
            ? () => context.pushReplacement('/video/${next.id}')
            : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final localVideo = widget.localVideo;
    Widget withBackButton(Widget child) => Stack(
      children: [
        child,
        const SafeArea(
          child: Padding(padding: EdgeInsets.all(8), child: BackButton()),
        ),
      ],
    );
    final content = localVideo == null
        ? ref
              .watch(videoDetailProvider(id))
              .when(
                loading: () => withBackButton(
                  const Center(child: M3EContainedLoadingIndicator()),
                ),
                error: (error, stackTrace) =>
                    withBackButton(_VideoError(id: id, error: error)),
                data: (video) {
                  ref
                      .read(libraryProvider.notifier)
                      .addSubscriptionVideo(video);
                  if (widget.inPlayWindow) _publishTitleInfo(video);
                  return _DetailBody(
                    video: video,
                    onBack: widget.onBack,
                    onHome: widget.onHome,
                    hidePlayerTopBar: widget.inPlayWindow,
                  );
                },
              )
        : (() {
            if (widget.inPlayWindow) _publishTitleInfo(localVideo);
            return _DetailBody(
              video: localVideo,
              onBack: widget.onBack,
              onHome: widget.onHome,
              hidePlayerTopBar: widget.inPlayWindow,
            );
          })();
    // 播放页固定走「沉浸模式」（参考 b 站）：不管应用当前是浅色还是深色主题，
    // 整页都用深色 —— 播放器舞台纯黑、右侧简介/评论用深色中性面。
    //
    // 字体、配色变体、AMOLED 这些开关必须跟 App 层用同一份设置：这些也是全屏播放器
    // 继承到的主题，漏掉任何一个都会让播放页/全屏的文字跟其它页面不一样
    // （例如开了「使用系统字体」而这里还写死内置字体，看上去就是「字体异常」）。
    final settings = ref.watch(settingsProvider).valueOrNull;
    final immersive = appTheme(
      null,
      settings?.themeColor.seedColor(settings.customThemeColor) ??
          const Color(0xfffb7299),
      brightness: Brightness.dark,
      amoled: settings?.amoledMode ?? false,
      useSystemFont: settings?.useSystemFont ?? false,
      variant:
          settings?.themeColor.schemeVariant ?? DynamicSchemeVariant.tonalSpot,
      neutralSurfaces: true,
    );
    // 页面底色再压暗一档（#101113），与纯黑的播放器舞台拉开层次但不刺眼。
    return Theme(
      data: immersive,
      child: Scaffold(
        backgroundColor: immersive.colorScheme.surfaceContainerLowest,
        body: content,
      ),
    );
  }
}

class _VideoError extends ConsumerWidget {
  const _VideoError({required this.id, required this.error});

  final String id;
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ref.invalidate(videoDetailProvider(id)),
            child: Text(AppLocalizations.of(context)!.retry),
          ),
          if (error is CloudflareChallengeException)
            TextButton(
              onPressed: () async {
                final url = (error as CloudflareChallengeException).url;
                if (await context.push<bool>('/cloudflare', extra: url) ==
                    true) {
                  ref.invalidate(videoDetailProvider(id));
                }
              },
              child: Text(
                AppLocalizations.of(context)!.completeCloudflareVerification,
              ),
            ),
        ],
      ),
    ),
  );
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({
    required this.video,
    this.onBack,
    this.onHome,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  /// 独立播放窗口里隐去播放器自带的顶部条（窗口那条已经有回到主界面 / 标题）。
  final bool hidePlayerTopBar;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  late final M3EFloatingToolbarScrollBehavior _scrollBehavior =
      M3EFloatingToolbarScrollBehavior.exitAlways(
        exitDirection: M3EFloatingToolbarExitDirection.bottom,
      );

  @override
  void initState() {
    super.initState();
    _scrollBehavior.state.offsetLimit = -144;
  }

  @override
  void dispose() {
    _scrollBehavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          // 播放页的内容布局与「独立播放窗口」共用一份（video_page_layout.dart）。
          VideoPageBody(
            video: video,
            onBack: widget.onBack ?? () => Navigator.maybePop(context),
            onHome: widget.onHome ?? () => context.go('/'),
            onPrevious: () => _playPrevious(context, video),
            onNext: () => _playNext(context, video),
            onEpisodeSelected: (episode) => _playEpisode(context, episode),
            hidePlayerTopBar: widget.hidePlayerTopBar,
          ),
          Positioned(
            left: isTablet ? null : 0,
            right: isTablet ? 16 : 0,
            bottom: 16,
            child: _FloatingControls(
              video: video,
              scrollBehavior: _scrollBehavior,
              vertical: isTablet,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingControls extends ConsumerWidget {
  const _FloatingControls({
    required this.video,
    required this.scrollBehavior,
    this.vertical = false,
  });

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showComment =
        ref.watch(videoTabProvider(video.id)) == 1 &&
        ref.watch(accountProvider).valueOrNull != null;
    final actionColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showComment) ...[
          FloatingActionButton(
            onPressed: () => writeSelectedVideoComment(context, ref, video.id),
            child: const Icon(Icons.add_comment_outlined),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
    return ListenableBuilder(
      listenable: scrollBehavior.state,
      builder: (context, child) {
        final state = scrollBehavior.state;
        return Transform.translate(
          offset: vertical
              ? Offset(-state.offset, 0)
              : Offset(0, -state.offset),
          child: ExcludeFocus(
            excluding: state.collapsedFraction >= 1,
            child: IgnorePointer(
              ignoring: state.collapsedFraction >= 1,
              child: child,
            ),
          ),
        );
      },
      child: vertical
          ? Align(alignment: Alignment.bottomRight, child: actionColumn)
          : Center(child: actionColumn),
    );
  }
}
