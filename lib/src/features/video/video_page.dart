import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_theme.dart';
import '../../core/window_chrome.dart';
import '../../data/local/library_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../domain/models/video.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import 'video_comments.dart';
import 'video_controller.dart';
import 'video_detail_content.dart';
import 'video_player_panel.dart';

VideoCard? nextEpisode(VideoDetail video) {
  final episodes = video.playlist;
  final index = episodes.indexWhere((episode) => episode.id == video.id);
  if (index >= 0 && index + 1 < episodes.length) return episodes[index + 1];
  return episodes.firstWhere((episode) => episode.id != video.id, orElse: () => const VideoCard(id: '', title: '', coverUrl: ''));
}

void _playNext(BuildContext context, VideoDetail video) {
  final next = nextEpisode(video);
  if (next == null || next.id.isEmpty) return;
  context.pushReplacement('/video/${next.id}');
}

void _playEpisode(BuildContext context, VideoCard episode) {
  if (episode.id.isEmpty) return;
  context.pushReplacement('/video/${episode.id}');
}

class VideoPage extends ConsumerStatefulWidget {
  const VideoPage({super.key, required this.id, this.localVideo});

  final String id;
  final VideoDetail? localVideo;

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
    WindowChrome.leaveImmersivePage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final localVideo = widget.localVideo;
    Widget withBackButton(Widget child) => Stack(children: [child, const SafeArea(child: Padding(padding: EdgeInsets.all(8), child: BackButton()))]);
    final content = localVideo == null
        ? ref.watch(videoDetailProvider(id)).when(
              loading: () => withBackButton(const Center(child: M3EContainedLoadingIndicator())),
              error: (error, stackTrace) => withBackButton(_VideoError(id: id, error: error)),
              data: (video) {
                ref.read(libraryProvider.notifier).addSubscriptionVideo(video);
                return _DetailBody(video: video);
              },
            )
        : _DetailBody(video: localVideo);
    // 播放页固定走「沉浸模式」（参考 b 站）：不管应用当前是浅色还是深色主题，
    // 整页都用深色 —— 播放器舞台纯黑、右侧简介/评论用深色中性面。
    //
    // 字体、配色变体、AMOLED 这些开关必须跟 App 层用同一份设置：这些也是全屏播放器
    // 继承到的主题，漏掉任何一个都会让播放页/全屏的文字跟其它页面不一样
    // （例如开了「使用系统字体」而这里还写死内置字体，看上去就是「字体异常」）。
    final settings = ref.watch(settingsProvider).valueOrNull;
    final immersive = appTheme(
      null,
      settings?.themeColor.seedColor(settings.customThemeColor) ?? const Color(0xfffb7299),
      brightness: Brightness.dark,
      amoled: settings?.amoledMode ?? false,
      useSystemFont: settings?.useSystemFont ?? false,
      variant: settings?.themeColor.schemeVariant ?? DynamicSchemeVariant.tonalSpot,
      neutralSurfaces: true,
    );
    // 页面底色再压暗一档（#101113），与纯黑的播放器舞台拉开层次但不刺眼。
    return Theme(data: immersive, child: Scaffold(backgroundColor: immersive.colorScheme.surfaceContainerLowest, body: content));
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
              FilledButton(onPressed: () => ref.invalidate(videoDetailProvider(id)), child: Text(AppLocalizations.of(context)!.retry)),
              if (error is CloudflareChallengeException)
                TextButton(
                  onPressed: () async {
                    final url = (error as CloudflareChallengeException).url;
                    if (await context.push<bool>('/cloudflare', extra: url) == true) ref.invalidate(videoDetailProvider(id));
                  },
                  child: Text(AppLocalizations.of(context)!.completeCloudflareVerification),
                ),
            ],
          ),
        ),
      );
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.video});

  final VideoDetail video;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  late final M3EFloatingToolbarScrollBehavior _scrollBehavior = M3EFloatingToolbarScrollBehavior.exitAlways(exitDirection: M3EFloatingToolbarExitDirection.bottom);
  /// 桌面宽度下右侧内容栏是否收起（收起后播放器占满宽度）
  var _sidebarCollapsed = false;
  /// 鼠标是否在播放器上 / 侧栏把手上（把手只在鼠标靠近时出现）
  var _pointerOnPlayer = false;
  var _pointerOnHandle = false;

  /// 触屏等没有悬停的设备上把手常驻，否则收起来就找不回来了
  bool get _hoverSupported => switch (defaultTargetPlatform) { TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux || TargetPlatform.fuchsia => true, _ => false };
  bool get _showSidebarHandle => !_hoverSupported || _pointerOnPlayer || _pointerOnHandle;

  void _setPointerOnPlayer(bool value) { if (_pointerOnPlayer != value) setState(() => _pointerOnPlayer = value); }
  void _setPointerOnHandle(bool value) { if (_pointerOnHandle != value) setState(() => _pointerOnHandle = value); }

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
          if (isTablet)
            _TabletVideoLayout(
              video: video,
              scrollBehavior: _scrollBehavior,
              sidebarCollapsed: _sidebarCollapsed,
              showHandle: _showSidebarHandle,
              onToggleSidebar: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              onPlayerHover: _setPointerOnPlayer,
              onHandleHover: _setPointerOnHandle,
            )
          else
            _CompactVideoLayout(video: video, scrollBehavior: _scrollBehavior),
          Positioned(
            left: isTablet ? null : 0,
            right: isTablet ? 16 : 0,
            bottom: 16,
            child: _FloatingControls(video: video, scrollBehavior: _scrollBehavior, vertical: isTablet),
          ),
        ],
      ),
    );
  }
}

class _CompactVideoLayout extends StatelessWidget {
  const _CompactVideoLayout({required this.video, required this.scrollBehavior});

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: _VideoTabsView(video: video, scrollBehavior: scrollBehavior, showPlayer: true)),
      );
}

/// 右侧内容栏宽度：参考 b 站（1920 下约 336px）定上限，窗口再宽也不会越拉越宽 ——
/// 之前按 1/4 弹性算，全屏时能到 600+ 逻辑像素，播放器反被挤窄、上下黑边更多。
const double _sidebarWidth = 336;
const double _sidebarMinWidth = 280;
/// 播放器盒子固定 16:9（与 b 站一致）。
///
/// 盒子不再拉满整窗高度：那样 16:9 的片子被按宽度铺满后，播放器里上下会多出一大條
/// 纯黑（窗口越高越多）。现在盒子跟着 16:9 走，画面外面留的是页面底色，看着就是
/// 「播放器 + 页面」，而不是「播放器里包着黑边」。
const double _playerAspectRatio = 16 / 9;
const double _sidebarHandleWidth = 36;

class _TabletVideoLayout extends StatelessWidget {
  const _TabletVideoLayout({required this.video, required this.scrollBehavior, required this.sidebarCollapsed, required this.showHandle, required this.onToggleSidebar, required this.onPlayerHover, required this.onHandleHover});

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final bool sidebarCollapsed;
  final bool showHandle;
  final VoidCallback onToggleSidebar;
  final ValueChanged<bool> onPlayerHover;
  final ValueChanged<bool> onHandleHover;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // 内容栏宽度：窗口窄时给足 280，宽了之后封顶在 336，不会无限变宽。
          final sidebarWidth = (constraints.maxWidth * .26).clamp(_sidebarMinWidth, _sidebarWidth);
          // 播放器区域宽度（手把要骑在它的右缘上）
          final playerWidth = sidebarCollapsed ? constraints.maxWidth : constraints.maxWidth - sidebarWidth - 1;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: MouseRegion(
                        onEnter: (_) => onPlayerHover(true),
                        onExit: (_) => onPlayerHover(false),
                        // 播放器盒子固定 16:9 并居中：盒子本身仍是纯黑（非 16:9 的片子在里面
                        // 居中留边），上下多出来的那部分是页面底色，不是播放器的黑边。
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _playerAspectRatio,
                            child: ColoredBox(color: Colors.black, child: VideoPlayerPanel(video: video, onBack: () => Navigator.maybePop(context), onHome: () => context.go('/'), onNext: () => _playNext(context, video), onEpisodeSelected: (episode) => _playEpisode(context, episode))),
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    if (!sidebarCollapsed) SizedBox(width: sidebarWidth, child: _VideoTabsView(video: video, scrollBehavior: scrollBehavior, showPlayer: false)),
                  ],
                ),
              ),
              Positioned(
                // 展开时骑在视频右缘；收起后贴窗口右缘、直接叠在画面上（不再留窄栏）
                left: sidebarCollapsed ? null : playerWidth - _sidebarHandleWidth / 2,
                right: sidebarCollapsed ? 8 : null,
                top: 0,
                bottom: 0,
                child: Center(child: _SidebarHandle(collapsed: sidebarCollapsed, visible: showHandle, onPressed: onToggleSidebar, onHover: onHandleHover)),
              ),
            ],
          );
        },
      );
}

/// 侧栏收起/展开手把：半透明圆角，贴在视频右缘、竖向居中，鼠标靠近才出现
class _SidebarHandle extends StatelessWidget {
  const _SidebarHandle({required this.collapsed, required this.visible, required this.onPressed, required this.onHover});

  final bool collapsed;
  final bool visible;
  final VoidCallback onPressed;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: MouseRegion(
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: Tooltip(
          message: collapsed ? l10n.expandSidebar : l10n.collapseSidebar,
          child: Material(
            color: const Color(0x73000000),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(width: _sidebarHandleWidth, height: 64, child: Icon(collapsed ? Icons.chevron_left : Icons.chevron_right, size: 24, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingControls extends ConsumerWidget {
  const _FloatingControls({required this.video, required this.scrollBehavior, this.vertical = false});

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showComment = ref.watch(videoTabProvider(video.id)) == 1 && ref.watch(accountProvider).valueOrNull != null;
    final actionColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showComment) ...[
          FloatingActionButton(onPressed: () => writeSelectedVideoComment(context, ref, video.id), child: const Icon(Icons.add_comment_outlined)),
          const SizedBox(height: 8),
        ],
      ],
    );
    return ListenableBuilder(
      listenable: scrollBehavior.state,
      builder: (context, child) {
        final state = scrollBehavior.state;
        return Transform.translate(
          offset: vertical ? Offset(-state.offset, 0) : Offset(0, -state.offset),
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

class _VideoTabsView extends ConsumerStatefulWidget {
  const _VideoTabsView({required this.video, required this.scrollBehavior, required this.showPlayer});

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final bool showPlayer;

  @override
  ConsumerState<_VideoTabsView> createState() => _VideoTabsViewState();
}

class _VideoTabsViewState extends ConsumerState<_VideoTabsView> with SingleTickerProviderStateMixin {
  /// 侧栏只有简介 / 评论两个页签（相关推荐已并进简介）
  static const _tabCount = 2;
  late final TabController _controller;
  final _playerCollapse = ValueNotifier(0.0);
  var _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _tabCount, vsync: this, initialIndex: _initialIndex());
    _controller.addListener(_syncTab);
  }

  @override
  void didUpdateWidget(_VideoTabsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _controller.index = _initialIndex();
      _playerCollapse.value = 0;
      _isPlaying = false;
    }
  }

  int _initialIndex() => ref.read(videoTabProvider(widget.video.id)).clamp(0, _tabCount - 1);

  void _syncTab() {
    if (_controller.indexIsChanging) return;
    ref.read(videoTabProvider(widget.video.id).notifier).state = _controller.index;
    widget.scrollBehavior.state
      ..contentOffset = 0
      ..offset = 0;
  }

  bool _handleScroll(ScrollNotification notification) {
    if (!widget.showPlayer || notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification && notification.scrollDelta != null) {
      final delta = notification.scrollDelta!;
      if (delta > 0 && _isPlaying) return false;
      final next = (_playerCollapse.value + delta / 240).clamp(0.0, 1.0).toDouble();
      if (next != _playerCollapse.value) _playerCollapse.value = next;
    }
    return false;
  }

  @override
  void dispose() {
    _controller.removeListener(_syncTab);
    _controller.dispose();
    _playerCollapse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(videoTabProvider(widget.video.id));
    if (_controller.index != selected && !_controller.indexIsChanging) _controller.index = selected.clamp(0, _tabCount - 1);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        if (widget.showPlayer)
          ValueListenableBuilder<double>(
            valueListenable: _playerCollapse,
            child: RepaintBoundary(child: VideoPlayerPanel(key: ValueKey(widget.video.id), video: widget.video, onBack: () => Navigator.maybePop(context), onHome: () => context.go('/'), onNext: () => _playNext(context, widget.video), onEpisodeSelected: (episode) => _playEpisode(context, episode), onPlayingChanged: _setPlaying)),
            builder: (context, collapse, player) => Column(children: [ClipRect(child: Align(heightFactor: 1 - collapse, alignment: Alignment.topCenter, child: player)), if (collapse >= .99) SizedBox(height: 40, width: double.infinity, child: TextButton.icon(onPressed: () => _playerCollapse.value = 0, icon: const Icon(Icons.play_arrow), label: Text(l10n.play)))]),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.showPlayer ? 12 : 8, 16, 4),
          child: TabBar(
            controller: _controller,
            isScrollable: !widget.showPlayer,
            tabAlignment: !widget.showPlayer ? TabAlignment.start : null,
            tabs: [
              Tab(text: l10n.description),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Text(l10n.comments), if (widget.video.commentCount case final count?) ...[const SizedBox(width: 5), Badge(label: Text('$count'))]])),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: TabBarView(
              controller: _controller,
              children: [
                M3EFloatingToolbarScrollWrapper(behavior: widget.scrollBehavior, child: VideoDescriptionView(video: widget.video)),
                M3EFloatingToolbarScrollWrapper(behavior: widget.scrollBehavior, child: VideoCommentsView(video: widget.video)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _setPlaying(bool value) {
    if (_isPlaying == value) return;
    setState(() {
      _isPlaying = value;
      if (value && _playerCollapse.value > 0) _playerCollapse.value = 0;
    });
  }
}
