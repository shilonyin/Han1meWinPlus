import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import 'video_actions.dart';
import 'video_comments.dart';
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(
            video: video,
            onBack: widget.onBack,
            onPlay: () => setState(() => _playing = true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Container(
              decoration: BoxDecoration(
                color: AppDesignTokens.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
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
        ],
      ),
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
        return SizedBox(
          height: 520,
          child: VideoCommentsView(video: video),
        );
      case 2:
        return _InfoTab(video: video);
      case 3:
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
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
        final wide = viewport.maxWidth >= 900;
        return SizedBox(
          height: 380,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：封面模糊放大，但**压到半透明**再叠两层渐变——
              // 一层水平（右侧渐渐透出页底白）、一层垂直（底部淡出接白色面板）。
              // Baka 那种渐变显示的通透感来自这里：不是一整块不透明的模糊图。
              if (cover != null && cover.isNotEmpty)
                Opacity(
                  opacity: 0.55,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
                    child: AppCachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      width: viewport.maxWidth,
                      height: 380,
                      errorWidget: (context, url, error) =>
                          const _HeroFallback(),
                    ),
                  ),
                )
              else
                const _HeroFallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xCC1B1B28),
                      Color(0x801B1B28),
                      Color(0x33F4F4F7),
                      Color(0xCCF4F4F7),
                    ],
                    stops: [0.0, 0.35, 0.75, 1.0],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xB3F4F4F7),
                      Color(0xFFF4F4F7),
                    ],
                    stops: [0.0, 0.42, 0.78, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PressScale(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            onTap: onBack,
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Symbols.arrow_back_rounded,
                                size: 22,
                                color: Colors.white,
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
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 竖版海报
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: SizedBox(
                              width: 220,
                              height: 308,
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
                          const SizedBox(width: 28),
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
                                    color: Colors.white,
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
                                    color: Color(0xD9FFFFFF),
                                  ),
                                ),
                                const Spacer(),
                                if (video.tags.isNotEmpty)
                                  _HeroTags(tags: video.tags),
                                const SizedBox(height: 16),
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
        colors: [Color(0xFF202238), Color(0xFF4A4C6E), Color(0xFF8E90AE)],
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
    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
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
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
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
                      width: 100,
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

/// 相关 Tab：缩略图 + 标题 + 播放量的行卡片。
class _RelatedTab extends StatelessWidget {
  const _RelatedTab({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        for (final item in video.related)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PressScale(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: item.id.isEmpty
                    ? null
                    : () => context.push('/video/${item.id}'),
                child: Container(
                  height: 72,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppDesignTokens.stroke),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(
                          width: 108,
                          height: 60,
                          child: AppCachedNetworkImage(
                            imageUrl: item.coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                const ColoredBox(color: Color(0xFF3D3540)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                      const Icon(
                        Symbols.chevron_right_rounded,
                        size: 18,
                        color: AppDesignTokens.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}