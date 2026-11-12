import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_motion.dart';
import '../../core/app_responsive.dart';
import '../../core/app_radius.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import 'video_actions.dart';
import 'video_comments.dart';
import 'play_window.dart';
import 'video_player_panel.dart';

/// 沉浸式视频详情页：上半部是铺满的 Hero（模糊背景 + 竖版海报 + 标签 + 主操作），
/// 下半部是一块白色圆角面板，用 Tab 在「概览 / 评论 / 信息 / 相关」之间切换。
///
/// 版式参照 FigCraft 的 `page/videoDetail-redesign`（Baka 番剧详情页风格）：
/// 不把评论区直接摊在页面上，信息都收进 Tab 里。
/// 旧的 [VideoDetailSplitView] 仍保留在 video_detail_content.dart，需要时可以一行切回去。
class VideoDetailImmersiveView extends ConsumerStatefulWidget {
  const VideoDetailImmersiveView({
    super.key,
    required this.video,
    required this.sidebarWidth,
    required this.onBack,
    this.onHome,
    this.onPrevious,
    this.onNext,
    this.onEpisodeSelected,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final double sidebarWidth;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;
  final bool hidePlayerTopBar;

  @override
  ConsumerState<VideoDetailImmersiveView> createState() =>
      _VideoDetailImmersiveViewState();
}

class _VideoDetailImmersiveViewState
    extends ConsumerState<VideoDetailImmersiveView> {
  /// 是否已经点过「开始观看」。进详情页先看 Hero，点了才创建播放器。
  bool _playing = false;
  int _tab = 0;

  static const _tabs = ['概览', '评论', '信息', '相关'];

  /// 「立即播放 / 开始观看」：默认弹独立播放窗口（多窗口方案），
  /// 拉不起来（窗口 exe 缺失、非 Windows 等）才回退到本页内嵌播放器。
  /// 之前这里直接 setState 内嵌，独立播放窗口就再也没出现过。
  Future<void> _play(BuildContext context, VideoDetail video) async {
    final opened =
        await openVideoInPlayWindow(context, ref, video.id);
    if (opened) return;
    if (!mounted) return;
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    if (_playing) {
      return ColoredBox(
        color: Colors.black,
        child: VideoPlayerPanel(
          video: video,
          onBack: widget.onBack,
          onHome: widget.onHome,
          onPrevious: widget.onPrevious,
          onNext: widget.onNext,
          onEpisodeSelected: widget.onEpisodeSelected,
          hideTopBar: true,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, viewport) {
        // 内容面板至少铺满 Hero 以下的视口高度，跟 Getchu 新番详情页一样
        // 一直延伸到底，不在下方露出一大片页面底色。
        final minPanelHeight =
            (viewport.maxHeight -
                    AppResponsive.scaled(
                      context,
                      AppResponsive.isCompact(viewport.maxWidth) ? 360 : 430,
                    ))
                .clamp(0.0, double.infinity);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(
                video: video,
                onBack: widget.onBack,
                onPlay: () => _play(context, video),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
              horizontal: AppResponsive.gutterFor(viewport.maxWidth),
            ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minPanelHeight),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppRadius.xl),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tabBar(),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppDesignTokens.divider,
                        ),
                        AnimatedSwitcher(
                          duration: motionDuration(context, AppMotion.brief),
                          child: KeyedSubtree(
                            key: ValueKey(_tab),
                            child: _buildTab(context, video),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tabBar() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
    child: Row(
      children: [
        for (var i = 0; i < _tabs.length; i++) ...[
          PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => setState(() => _tab = i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tabs[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _tab == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: _tab == i
                            ? AppDesignTokens.ink
                            : AppDesignTokens.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _tab == i
                            ? AppDesignTokens.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (i < _tabs.length - 1) const SizedBox(width: 12),
        ],
      ],
    ),
  );

  Widget _buildTab(BuildContext context, VideoDetail video) {
    switch (_tab) {
      case 1:
        // 评论容器高度跟随文字缩放，并以视口高为上限，避免放大后列表被裁断。
        return SizedBox(
          height: AppResponsive.scaled(context, 900).clamp(
            0.0,
            MediaQuery.sizeOf(context).height,
          ),
          child: VideoCommentsView(video: video),
        );
      case 2:
        return _InfoTab(video: video);
      case 3:
        return Padding(
          padding: EdgeInsets.fromLTRB(
  28,
  AppResponsive.scaled(context, 56),
  28,
  AppResponsive.scaled(context, 32),
),
          child: _RelatedTab(video: video),
        );
      default:
        return _OverviewTab(video: video);
    }
  }
}

/// 沉浸式 Hero：模糊放大的封面作背景，竖版海报压在左侧，右侧是标题/标签/操作。
class _Hero extends ConsumerWidget {
  const _Hero({
    required this.video,
    required this.onBack,
    required this.onPlay,
  });

  final VideoDetail video;
  final VoidCallback onBack;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = video.coverUrl;
    final actions = videoActionsFor(context, ref, video);
    final primary = actions.isNotEmpty ? actions.first : null;
    return LayoutBuilder(
      builder: (context, viewport) {
        final wide = !AppResponsive.isCompact(viewport.maxWidth);
        final heroHeight = AppResponsive.scaled(context, wide ? 430 : 360);
        final topPad = AppResponsive.scaled(context, 20);
        final bottomPad = AppResponsive.scaled(context, 50);
        final titleHeight = AppResponsive.scaled(context, 32);
        final titleGap = AppResponsive.scaled(context, 20);
        final gutter = AppResponsive.gutterFor(viewport.maxWidth);
        // 海报与右侧按钮共用同一段行高，底边才永远齐平；宽度按设计稿比例反推。
        final rowHeight = (heroHeight -
                topPad -
                bottomPad -
                titleHeight -
                titleGap)
            .clamp(120.0, double.infinity);
        final posterHeight = rowHeight;
        final posterWidth = posterHeight * (220 / 308);
        return SizedBox(
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景与 GetchuBackdrop 完全一致：封面原图不模糊，只叠**单层**
              // 由 55% → 88% → 100% 页底白的渐变遮罩，图就这样平滑收进面板。
              // 之前额外叠的顶部压暗层会在两层交界处压出一条硬边，已去掉。
              if (cover != null && cover.isNotEmpty)
                AppCachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  width: viewport.maxWidth,
                  height: heroHeight,
                  fadeInDuration: Duration.zero,
                  errorWidget: (context, url, error) =>
                      const _HeroFallback(),
                )
              else
                const _HeroFallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x8CFFFFFF),
                      Color(0xE0FFFFFF),
                      Color(0xFFFFFFFF),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  topPad,
                  gutter,
                  bottomPad,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PressScale(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            onTap: onBack,
                            child: SizedBox(
                              width: titleHeight,
                              height: titleHeight,
                              child: Icon(
                                Symbols.arrow_back_rounded,
                                size: 22,
                                color: AppDesignTokens.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: titleGap),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 竖版海报
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: SizedBox(
                              width: posterWidth,
                              height: posterHeight,
                              child: cover != null && cover.isNotEmpty
                                  ? AppCachedNetworkImage(
                                      imageUrl: cover,
                                      fit: BoxFit.cover,
                                      faceFocus: true,
                                      errorWidget: (context, url, error) =>
                                          const ColoredBox(
                                        color: Color(0xFF2B2B31),
                                      ),
                                    )
                                  : const ColoredBox(
                                      color: Color(0xFF2B2B31),
                                    ),
                            ),
                          ),
                          SizedBox(width: AppResponsive.scaled(context, 28)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppDesignTokens.ink,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (video.artist != null) video.artist!,
                                    if (video.uploadDate != null)
                                      video.uploadDate!,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppDesignTokens.inkSubtle,
                                  ),
                                ),
                                const Spacer(),
                                if (video.tags.isNotEmpty)
                                  _HeroTags(tags: video.tags),
                                SizedBox(height: AppResponsive.scaled(context, 16)),
                                Row(
                                  children: [
                                    if (primary != null)
                                      _HeroButton(
                                        label: primary.label,
                                        dark: true,
                                        icon: Symbols.add_rounded,
                                        onTap: primary.onPressed,
                                      ),
                                    const SizedBox(width: 12),
                                    _HeroButton(
                                      label: '开始观看',
                                      dark: false,
                                      icon: Symbols.play_arrow_rounded,
                                      onTap: onPlay,
                                    ),
                                    const Spacer(),
                                    if (wide && video.rating != null)
                                      _HeroRating(rating: video.rating!),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFD8D9E4), Color(0xFFECECF3), Color(0xFFFFFFFF)],
      ),
    ),
  );
}

class _HeroTags extends StatelessWidget {
  const _HeroTags({required this.tags});

  final List<VideoTag> tags;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      // IntrinsicWidth：Wrap 给子项的是无界宽度，不约束就会把每颗标签撑满整行
      // （宽窗口下见过一次），按钮和评分会被挤出 Hero。
      for (final tag in tags.take(6))
        IntrinsicWidth(
          child: PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                final url = Uri(
                  path: '/search',
                  queryParameters: {'tags[]': tag.name},
                ).toString();
                context.push(url, extra: SearchRouteRequest(initialUrl: url));
              },
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xD9FFFFFF),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  tag.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.dark,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool dark;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B1B1F) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: dark ? Colors.white : AppDesignTokens.ink,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : AppDesignTokens.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HeroRating extends StatelessWidget {
  const _HeroRating({required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        rating,
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: AppDesignTokens.ink,
        ),
      ),
      const SizedBox(width: 6),
      const Icon(Symbols.star_rounded, size: 22, color: Color(0xFFF5A623), fill: 1),
    ],
  );
}

/// 概览 Tab：左剧情简介、右基本信息，下面接选集与相关推荐。
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Padding(
    // 概览只放「剧情简介 + 基本信息」两栏，跟 Baka 的概览页一致；
    // 选集归到「信息」Tab、相关推荐归到「相关」Tab，不在概览下面堆长内容。
    padding: EdgeInsets.fromLTRB(
  28,
  AppResponsive.scaled(context, 56),
  28,
  AppResponsive.scaled(context, 32),
),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.description,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                video.description ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppDesignTokens.inkSubtle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '基本信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.ink,
                ),
              ),
              const SizedBox(height: 12),
              _InfoTab(video: video, compact: true),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 信息 Tab：键值列表。紧凑模式下用在概览右侧，不重复画标题。
class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.video, this.compact = false});

  final VideoDetail video;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (video.views != null) ('播放量', video.views!),
      if (video.rating != null) ('评分', video.rating!),
      if (video.commentCount != null) ('评论数', '${video.commentCount}'),
      if (video.duration != null) ('时长', video.duration!),
      if (video.uploadDate != null) ('发布日期', video.uploadDate!),
      if (video.artist != null) ('作者', video.artist!),
      if (video.genre != null) ('分类', video.genre!),
    ];
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          const Text(
            '基本信息',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
            ),
          ),
        if (!compact) const SizedBox(height: 16),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.inkMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (rows.isEmpty)
          const Text(
            '暂无信息',
            style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted),
          ),
      ],
    );
    if (compact) return list;
    // 独立的「信息」Tab：基本信息 + 选集（选集不再堆在概览底部）。
    return Padding(
      padding: EdgeInsets.fromLTRB(
  28,
  AppResponsive.scaled(context, 56),
  28,
  AppResponsive.scaled(context, 32),
),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          list,
          if (video.playlist.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppDesignTokens.divider,
            ),
            const SizedBox(height: 24),
            _EpisodeGrid(video: video),
          ],
        ],
      ),
    );
  }
}

/// 选集网格：4 列编号按钮，当前集用主色。
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            '选集',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '共 ${video.playlist.length} 集',
            style: const TextStyle(
              fontSize: 12,
              color: AppDesignTokens.inkMuted,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      // 固定格宽、由 Wrap 自动换行：不按窗口宽度均分，否则超宽窗口下每格会被拉成横条。
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < video.playlist.length; i++)
            Builder(
              builder: (context) {
                final item = video.playlist[i];
                final selected = item.id == video.id;
                return PressScale(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => context.push('/video/${item.id}'),
                    child: Container(
                      width: AppResponsive.scaled(context, 100),
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppDesignTokens.accentDeep
                            : AppDesignTokens.fieldFill,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? Colors.white
                              : AppDesignTokens.inkSubtle,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ],
  );
}

/// 相关 Tab：按封面正常比例（16:9）排成卡片网格，不铺成横条。
class _RelatedTab extends StatelessWidget {
  const _RelatedTab({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '相关推荐',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppDesignTokens.ink,
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 16.0;
          final minCardWidth = AppResponsive.scaled(context, 220);
          final width = AppResponsive.cardWidthFor(
            availableWidth: constraints.maxWidth,
            minCardWidth: minCardWidth,
            gap: gap,
          );
          return Wrap(
            spacing: gap,
            runSpacing: 20,
            children: [
              for (final item in video.related)
                SizedBox(width: width, child: _RelatedCard(item: item)),
            ],
          );
        },
      ),
    ],
  );
}

/// 封面真实宽高比缓存：同一张图只解析一次，滚动时不再反复解码。
final Map<String, double> _coverAspectCache = <String, double>{};

/// 读取封面实际尺寸并返回宽高比，取不到时退回 16:9。
Future<double> _coverAspect(String url) async {
  final cached = _coverAspectCache[url];
  if (cached != null) return cached;
  if (url.isEmpty) return 16 / 9;
  try {
    final stream = appNetworkImage(url).resolve(const ImageConfiguration());
    final completer = Completer<ui.Image>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stack) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    final image = await completer.future.timeout(const Duration(seconds: 8));
    final ratio = image.width / image.height;
    _coverAspectCache[url] = ratio;
    return ratio;
  } catch (_) {
    return 16 / 9;
  }
}

/// 单张相关视频卡：封面按自身真实比例显示，标题与作者/播放量在下。
class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.item});

  final VideoCard item;

  @override
  Widget build(BuildContext context) => FutureBuilder<double>(
    future: _coverAspect(item.coverUrl),
    builder: (context, snapshot) {
      // 极端长条会撑坏网格，收敛到 0.56~1.9，仍保留竖版与横版的区别。
      final ratio = (snapshot.data ?? 16 / 9).clamp(0.56, 1.9);
      return PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: item.id.isEmpty
              ? null
              : () => context.push('/video/${item.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: AppCachedNetworkImage(
                    imageUrl: item.coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        const ColoredBox(color: Color(0xFF3D3540)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (item.artist != null) item.artist!,
                  if (item.views != null) item.views!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.inkMuted,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}