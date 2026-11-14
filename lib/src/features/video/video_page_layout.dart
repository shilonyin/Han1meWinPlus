import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
import '../../domain/models/video.dart';
import '../shared/press_scale.dart';
import 'video_comments.dart';
import 'video_controller.dart';
import 'video_detail_content.dart';
import 'video_detail_immersive.dart';
import 'video_player_panel.dart';

// 播放页的内容布局：主窗口的播放页和「独立播放窗口」共用这一份，
// 所以任何播放页的视觉调整只改这里，两边自动同步。

/// 内容区宽度：**始终铺满**可用宽度，应用层不再额外留黑边。
///
/// 这里踩过两轮坑，最后收敛到「就是铺满」：
///  1. 原先固定 1600 上限 + 居中，超宽屏上画面被压成正中一小块（两侧空 480、
///     上下黑边 365），用户拿同类客户端对比后指出「最大化界面有问题」；
///  2. 改成按屏幕动态放大上限后，收起侧栏仍居中留边，于是**视频两边又多出一段
///     黑边**——视频自己的 letterbox 已经够显眼，再叠一层就成了双层黑边
///     （用户：「视频本身就已经有黑边了还在这基础加一段」）。
///
/// 现在不管侧栏展开还是收起都铺满：播放器撑满左列、侧栏贴右，与同类客户端一致；
/// 画面比例不匹配时由播放器自己居中留黑——那才是真正必要的那一层。
///
/// 抽成纯函数便于单测（见 test/stage_width_test.dart）。
double stageWidthFor({
  required double availableWidth,
  required bool sidebarCollapsed,
}) {
  return availableWidth;
}

/// 右侧内容栏宽度：参考同类客户端（1920 下约 336px）定上限，窗口再宽也不会越拉越宽 ——
/// 之前按 1/4 弹性算，全屏时能到 600+ 逻辑像素，播放器反被挤窄、上下黑边更多。
/// 设计稿 `base_videodetail.png` 实测：内容区 1044 里右卡 360、播放器 640，
/// 中间留 44 的沟。之前 336 是照同类客户端估的，比设计稿窄 24。
const double kSidebarWidth = 360;
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
    // 独立播放窗口（hidePlayerTopBar）**始终**走 _TabletVideoLayout 的左右两栏布局，
    // 不按窗口尺寸切到 _CompactVideoLayout —— 后者是「播放器在上、Tab 在下」的竖排，
    // 小窗播放时右栏会被挤到底部、顶部「简介/评论」也看不到。主窗口仍按尺寸切。
    final isTablet =
        widget.hidePlayerTopBar ||
        MediaQuery.sizeOf(context).shortestSide >= 600;
    final sidebarCollapsed =
        widget.showSidebarToggle &&
        ref.watch(videoSidebarCollapsedProvider(video.id));
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
              onToggleSidebar: () {
                final notifier = ref.read(
                  videoSidebarCollapsedProvider(video.id).notifier,
                );
                notifier.state = !notifier.state;
              },
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
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      // 视频页是宽内容（播放器 + 信息面板），按可用宽度推导限宽、宽窗居中。
      // 原来写死 1280，2560 窗口下右侧空出一大片，和其它页面的推导宽度不一致。
      final width = AppResponsive.contentWidthFor(
        MediaQuery.sizeOf(context).width,
        cap: AppResponsive.wideContentCap,
      );
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
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
    },
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
  final bool hidePlayerTopBar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stageWidth = stageWidthFor(
        availableWidth: constraints.maxWidth,
        sidebarCollapsed: sidebarCollapsed,
      );
      final sidebarWidth = (stageWidth * .26).clamp(
        kSidebarMinWidth,
        kSidebarWidth,
      );
      final effectiveSidebar = sidebarCollapsed ? 0.0 : sidebarWidth;

      // 独立播放窗口：恢复 v1.1.28（上个发布版本）的「左播放器 + 右信息栏」原版布局 ——
      // 左列整高纯黑舞台 + 竖分隔线 + 右列 _VideoTabsView(showPlayer:false) 的简介/评论栏。
      // d4acbed 把这里整体换成了沉浸式详情页，播放窗口就跟着变了；这里按 hidePlayerTopBar
      // 把播放窗口单独改回原样，主窗口详情页仍是沉浸式。
      if (hidePlayerTopBar) {
        // 独立播放窗口：极简左右两栏，**不要** OverflowBox / AnimatedContainer 那套
        // 折叠动画容器 —— 那套会把右栏的高度约束搞丢，导致顶部「简介/评论」页签
        // 被挤成 0 高、看不见。播放窗口不需要侧栏折叠，直接 Row 铺满即可，
        // 高度由 Row 的 stretch 传给右栏，页签头就能正常显示。
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: stageWidth,
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
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
                SizedBox(
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
              ],
            ),
          ),
        );
      }

      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: stageWidth,
          height: constraints.maxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: VideoDetailImmersiveView(
                  video: video,
                  sidebarWidth: effectiveSidebar,
                  onBack: onBack,
                  onHome: onHome,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  onEpisodeSelected: onEpisodeSelected,
                  hidePlayerTopBar: hidePlayerTopBar,
                ),
              ),
              // 收起/展开手把（保留原有折叠交互）
              Positioned(
                left: sidebarCollapsed
                    ? null
                    : stageWidth - effectiveSidebar - kSidebarHandleWidth / 2,
                right: sidebarCollapsed ? 8 : null,
                top: (constraints.maxHeight - 64) / 2,
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
      duration: AppMotion.brief,
      child: MouseRegion(
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: Tooltip(
          message: collapsed ? l10n.expandSidebar : l10n.collapseSidebar,
          child: Material(
            color: const Color(0x73000000),
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: PressScale(
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: kSidebarHandleWidth,
                  height: 64,
                  child: Icon(
                    collapsed
                        ? Symbols.chevron_left_rounded
                        : Symbols.chevron_right_rounded,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
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
    // 播放窗口右栏（showPlayer=false）：最朴素的文本页签 + 条件渲染内容，
    // 完全不用 TabBar / TabBarView —— 它们在这套深色面板里会塌成一条 indicator，
    // 导致「简介 / 评论」标题看不见。这里用 Container 固定 48 高 + Row + Text，
    // 高度和颜色都确定，标题一定显示；点击 setState 切换内容。
    if (!widget.showPlayer) {
      final tab = _controller.index;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                _playTab(context, l10n.description, 0, tab == 0),
                const SizedBox(width: 4),
                _playTab(
                  context,
                  widget.video.commentCount != null
                      ? '${l10n.comments} ${widget.video.commentCount}'
                      : l10n.comments,
                  1,
                  tab == 1,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(
            child: tab == 0
                ? VideoDescriptionView(video: widget.video)
                : VideoCommentsView(video: widget.video),
          ),
        ],
      );
    }
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
                    child: PressScale(
                      child: TextButton.icon(
                        onPressed: () => _playerCollapse.value = 0,
                        icon: const Icon(Symbols.play_arrow_rounded),
                        label: Text(l10n.play),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.showPlayer ? 12 : 8, 16, 4),
          // 显式给 TabBar 定高 + 明确的标签颜色：默认色在深色播放面板上会和底色接近，
          // 「简介 / 评论」两个字看起来像消失。这里用主题的 onSurface / primary 保证对比度。
          child: SizedBox(
            height: 44,
            child: TabBar(
            controller: _controller,
            isScrollable: !widget.showPlayer,
            tabAlignment: !widget.showPlayer ? TabAlignment.start : null,
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
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

  /// 播放窗口右栏的页签头（普通文本，避免 TabBar 在深色面板下塌陷看不到标题）。
  Widget _playTab(BuildContext context, String label, int index, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => setState(() => _controller.index = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: Colors.yellow,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                width: 24,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ],
          ),
        ),
      ),
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
