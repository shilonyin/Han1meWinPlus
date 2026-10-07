import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../domain/models/video.dart';
import '../shared/press_scale.dart';
import 'video_comments.dart';
import 'video_controller.dart';
import 'video_detail_content.dart';
import 'video_player_panel.dart';
import '../../core/app_motion.dart';

// 播放页的内容布局：主窗口的播放页和「独立播放窗口」共用这一份，
// 所以任何播放页的视觉调整只改这里，两边自动同步。

/// 内容区宽度：**始终铺满**可用宽度，应用层不再额外留黑边。
///
/// 这里踩过两轮坑，最后收敛到「就是铺满」：
///  1. 原先固定 1600 上限 + 居中，超宽屏上画面被压成正中一小块（两侧空 480、
///     上下黑边 365），用户拿 b 站对比后指出「最大化界面有问题」；
///  2. 改成按屏幕动态放大上限后，收起侧栏仍居中留边，于是**视频两边又多出一段
///     黑边**——视频自己的 letterbox 已经够显眼，再叠一层就成了双层黑边
///     （用户：「视频本身就已经有黑边了还在这基础加一段」）。
///
/// 现在不管侧栏展开还是收起都铺满：播放器撑满左列、侧栏贴右，与 b 站一致；
/// 画面比例不匹配时由播放器自己居中留黑——那才是真正必要的那一层。
///
/// 抽成纯函数便于单测（见 test/stage_width_test.dart）。
double stageWidthFor({required double availableWidth, required bool sidebarCollapsed}) {
  return availableWidth;
}

/// 右侧内容栏宽度：参考 b 站（1920 下约 336px）定上限，窗口再宽也不会越拉越宽 ——
/// 之前按 1/4 弹性算，全屏时能到 600+ 逻辑像素，播放器反被挤窄、上下黑边更多。
const double kSidebarWidth = 336;
const double kSidebarMinWidth = 280;
const double kSidebarHandleWidth = 36;

/// 播放页主体：宽窗是「左播放器 + 右简介/评论」，窄窗退化成上下排布。
///
/// [showSidebarToggle] 为真时右侧信息栏带一个可收起的把手（主窗口播放页用）；
/// 独立播放窗口没有「收起侧栏」的概念，传 false 即可。
class VideoPageBody extends ConsumerStatefulWidget {
  const VideoPageBody({
    super.key,
    required this.video,
    required this.onBack,
    this.onHome,
    this.onPrevious,
    this.onNext,
    this.onEpisodeSelected,
    this.showSidebarToggle = true,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;
  final bool showSidebarToggle;

  /// 隐去播放器自带的顶部条：独立播放窗口的窗口标题栏已经含
  /// 「回到主界面 / 上下集 / 标题」，再叠一条会出现两个返回键和两行标题。
  final bool hidePlayerTopBar;

  @override
  ConsumerState<VideoPageBody> createState() => _VideoPageBodyState();
}

class _VideoPageBodyState extends ConsumerState<VideoPageBody> {
  late final M3EFloatingToolbarScrollBehavior _scrollBehavior =
      M3EFloatingToolbarScrollBehavior.exitAlways(
        exitDirection: M3EFloatingToolbarExitDirection.bottom,
      );

  /// 桌面宽度下右侧内容栏是否收起（收起后播放器占满宽度）
  var _sidebarCollapsed = false;

  /// 鼠标是否在播放器上 / 侧栏把手上（把手只在鼠标靠近时出现）
  var _pointerOnPlayer = false;
  var _pointerOnHandle = false;

  /// 触屏等没有悬停的设备上把手常驻，否则收起来就找不回来了
  bool get _hoverSupported => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };
  bool get _showSidebarHandle =>
      !_hoverSupported || _pointerOnPlayer || _pointerOnHandle;

  void _setPointerOnPlayer(bool value) {
    if (_pointerOnPlayer != value) setState(() => _pointerOnPlayer = value);
  }

  void _setPointerOnHandle(bool value) {
    if (_pointerOnHandle != value) setState(() => _pointerOnHandle = value);
  }

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
    final sidebarCollapsed = widget.showSidebarToggle && _sidebarCollapsed;
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          if (isTablet)
            _TabletVideoLayout(
              video: video,
              scrollBehavior: _scrollBehavior,
              sidebarCollapsed: sidebarCollapsed,
              showHandle: widget.showSidebarToggle && _showSidebarHandle,
              onToggleSidebar: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              onPlayerHover: _setPointerOnPlayer,
              onHandleHover: _setPointerOnHandle,
              onBack: widget.onBack,
              onHome: widget.onHome,
              onPrevious: widget.onPrevious,
              onNext: widget.onNext,
              onEpisodeSelected: widget.onEpisodeSelected,
              hidePlayerTopBar: widget.hidePlayerTopBar,
            )
          else
            _CompactVideoLayout(
              video: video,
              scrollBehavior: _scrollBehavior,
              onBack: widget.onBack,
              onHome: widget.onHome,
              onPrevious: widget.onPrevious,
              onNext: widget.onNext,
              onEpisodeSelected: widget.onEpisodeSelected,
              hidePlayerTopBar: widget.hidePlayerTopBar,
            ),
        ],
      ),
    );
  }
}

class _CompactVideoLayout extends StatelessWidget {
  const _CompactVideoLayout({
    required this.video,
    required this.scrollBehavior,
    required this.onBack,
    this.onHome,
    this.onPrevious,
    this.onNext,
    this.onEpisodeSelected,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;
  final bool hidePlayerTopBar;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1280),
      child: _VideoTabsView(
        video: video,
        scrollBehavior: scrollBehavior,
        showPlayer: true,
        onBack: onBack,
        onHome: onHome,
        onPrevious: onPrevious,
        onNext: onNext,
        onEpisodeSelected: onEpisodeSelected,
        hidePlayerTopBar: hidePlayerTopBar,
      ),
    ),
  );
}

class _TabletVideoLayout extends StatelessWidget {
  const _TabletVideoLayout({
    required this.video,
    required this.scrollBehavior,
    required this.sidebarCollapsed,
    required this.showHandle,
    required this.onToggleSidebar,
    required this.onPlayerHover,
    required this.onHandleHover,
    required this.onBack,
    this.onHome,
    this.onPrevious,
    this.onNext,
    this.onEpisodeSelected,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final bool sidebarCollapsed;
  final bool showHandle;
  final VoidCallback onToggleSidebar;
  final ValueChanged<bool> onPlayerHover;
  final ValueChanged<bool> onHandleHover;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;

  /// 隐去播放器自带顶部条（独立播放窗口用，见 [VideoPageBody.hidePlayerTopBar]）。
  final bool hidePlayerTopBar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // b 站那套：播放器与右侧信息栏是**两个独立的块**，内容始终铺满可用宽度，
      // 应用层不留任何额外黑边（见 [stageWidthFor] 里记的两轮返工）。
      final stageWidth = stageWidthFor(
        availableWidth: constraints.maxWidth,
        sidebarCollapsed: sidebarCollapsed,
      );
      final sidebarWidth = (stageWidth * .26).clamp(
        kSidebarMinWidth,
        kSidebarWidth,
      );
      // 播放器区域宽度（手把要骑在它的右缘上）
      final playerWidth = sidebarCollapsed
          ? stageWidth
          : stageWidth - sidebarWidth - 1;
      // 舞台高度：左列整高都是播放器舞台（纯黑）。画面本身不拉伸：16:9 的片子在
      // 更高的舞台里由 _PlayerFrame 垂直居中，上下留对称的黑 —— 比起「盒子贴顶、
      // 下方一片页面底色」更像剧院，收起把手也能对齐舞台竖直中心。
      final stageHeight = constraints.maxHeight;
      // 内容区始终贴左：宽度已经铺满，居中没有意义；而且一旦居中就要求 stageWidth
      // 小于可用宽度，那必然在两侧留出黑边（就是用户报的「视频两边又多一段黑边」）。
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: stageWidth,
          height: constraints.maxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 播放器舞台：宽度撑满左列、整高纯黑，画面在舞台里居中。
                    SizedBox(
                      width: playerWidth,
                      height: stageHeight,
                      child: MouseRegion(
                        onEnter: (_) => onPlayerHover(true),
                        onExit: (_) => onPlayerHover(false),
                        child: ColoredBox(
                          color: Colors.black,
                          child: VideoPlayerPanel(
                            video: video,
                            onBack: onBack,
                            onHome: onHome,
                            onPrevious: onPrevious,
                            onNext: onNext,
                            onEpisodeSelected: onEpisodeSelected,
                            hideTopBar: hidePlayerTopBar,
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // 侧栏：整高，与播放器顶部对齐。收起时宽度动画到 0（而不是直接消失），
                    // 这样收起 / 展开是一个平滑的过渡而不是硬切。
                    AnimatedContainer(
                      duration: AppMotion.standard,
                      curve: Curves.easeOutCubic,
                      width: sidebarCollapsed ? 0 : sidebarWidth,
                      height: constraints.maxHeight,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: sidebarWidth,
                          maxWidth: sidebarWidth,
                          child: SizedBox(
                            width: sidebarWidth,
                            child: _VideoTabsView(
                              video: video,
                              scrollBehavior: scrollBehavior,
                              showPlayer: false,
                              onBack: onBack,
                              onHome: onHome,
                              onPrevious: onPrevious,
                              onNext: onNext,
                              onEpisodeSelected: onEpisodeSelected,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 把手：展开时骑在舞台右缘（舞台竖直中心），收起后贴窗口右缘。
              Positioned(
                left: sidebarCollapsed
                    ? null
                    : playerWidth - kSidebarHandleWidth / 2,
                right: sidebarCollapsed ? 8 : null,
                top: (stageHeight - 64) / 2,
                child: Center(
                  child: _SidebarHandle(
                    collapsed: sidebarCollapsed,
                    visible: showHandle,
                    onPressed: onToggleSidebar,
                    onHover: onHandleHover,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 侧栏收起/展开手把：半透明圆角，贴在视频右缘、竖向居中，鼠标靠近才出现
class _SidebarHandle extends StatelessWidget {
  const _SidebarHandle({
    required this.collapsed,
    required this.visible,
    required this.onPressed,
    required this.onHover,
  });

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
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: PressScale(child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: kSidebarHandleWidth,
                height: 64,
                child: Icon(
                  collapsed ? Symbols.chevron_left_rounded : Symbols.chevron_right_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            )),
          ),
        ),
      ),
    );
  }
}

class _VideoTabsView extends ConsumerStatefulWidget {
  const _VideoTabsView({
    required this.video,
    required this.scrollBehavior,
    required this.showPlayer,
    required this.onBack,
    this.onHome,
    this.onPrevious,
    this.onNext,
    this.onEpisodeSelected,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final M3EFloatingToolbarScrollBehavior scrollBehavior;
  final bool showPlayer;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;

  /// 隐去播放器自带顶部条（独立播放窗口用，见 [VideoPageBody.hidePlayerTopBar]）。
  final bool hidePlayerTopBar;

  @override
  ConsumerState<_VideoTabsView> createState() => _VideoTabsViewState();
}

class _VideoTabsViewState extends ConsumerState<_VideoTabsView>
    with SingleTickerProviderStateMixin {
  /// 侧栏只有简介 / 评论两个页签（相关推荐已并进简介）
  static const _tabCount = 2;
  late final TabController _controller;
  final _playerCollapse = ValueNotifier(0.0);
  var _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: _initialIndex(),
    );
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

  int _initialIndex() =>
      ref.read(videoTabProvider(widget.video.id)).clamp(0, _tabCount - 1);

  void _syncTab() {
    if (_controller.indexIsChanging) return;
    ref.read(videoTabProvider(widget.video.id).notifier).state =
        _controller.index;
    widget.scrollBehavior.state
      ..contentOffset = 0
      ..offset = 0;
  }

  bool _handleScroll(ScrollNotification notification) {
    if (!widget.showPlayer || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.scrollDelta != null) {
      final delta = notification.scrollDelta!;
      if (delta > 0 && _isPlaying) return false;
      final next = (_playerCollapse.value + delta / 240)
          .clamp(0.0, 1.0)
          .toDouble();
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
    if (_controller.index != selected && !_controller.indexIsChanging) {
      _controller.index = selected.clamp(0, _tabCount - 1);
    }
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        if (widget.showPlayer)
          ValueListenableBuilder<double>(
            valueListenable: _playerCollapse,
            child: RepaintBoundary(
              child: VideoPlayerPanel(
                key: ValueKey(widget.video.id),
                video: widget.video,
                onBack: widget.onBack,
                onHome: widget.onHome,
                onPrevious: widget.onPrevious,
                onNext: widget.onNext,
                onEpisodeSelected: widget.onEpisodeSelected,
                onPlayingChanged: _setPlaying,
                hideTopBar: widget.hidePlayerTopBar,
              ),
            ),
            builder: (context, collapse, player) => Column(
              children: [
                ClipRect(
                  child: Align(
                    heightFactor: 1 - collapse,
                    alignment: Alignment.topCenter,
                    child: player,
                  ),
                ),
                if (collapse >= .99)
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: PressScale(child: TextButton.icon(
                      onPressed: () => _playerCollapse.value = 0,
                      icon: const Icon(Symbols.play_arrow_rounded),
                      label: Text(l10n.play),
                    )),
                  ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.showPlayer ? 12 : 8, 16, 4),
          child: TabBar(
            controller: _controller,
            isScrollable: !widget.showPlayer,
            tabAlignment: !widget.showPlayer ? TabAlignment.start : null,
            tabs: [
              Tab(text: l10n.description),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.comments),
                    if (widget.video.commentCount case final count?) ...[
                      const SizedBox(width: 5),
                      Badge(label: Text('$count')),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: TabBarView(
              controller: _controller,
              children: [
                M3EFloatingToolbarScrollWrapper(
                  behavior: widget.scrollBehavior,
                  child: VideoDescriptionView(video: widget.video),
                ),
                M3EFloatingToolbarScrollWrapper(
                  behavior: widget.scrollBehavior,
                  child: VideoCommentsView(video: widget.video),
                ),
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
