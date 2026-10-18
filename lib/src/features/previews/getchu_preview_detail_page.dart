import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../shared/app_image_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/getchu_preview.dart';
import '../../domain/models/video.dart';
import '../shared/press_scale.dart';
import 'getchu_card.dart';
import 'getchu_detail_hero.dart';
import 'getchu_preview_controller.dart';

const _getchuImageHeaders = kGetchuImageHeaders;

class GetchuPreviewDetailPage extends ConsumerWidget {
  const GetchuPreviewDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final result = ref.watch(getchuPreviewDetailProvider(id));
    return Scaffold(
      body: result.when(
        loading: () => const Center(child: M3EContainedLoadingIndicator()),
        error: (error, _) => Center(
          child: PressScale(
            child: OutlinedButton.icon(
              onPressed: () => ref.invalidate(getchuPreviewDetailProvider(id)),
              icon: const Icon(Symbols.refresh_rounded),
              label: Text(l10n.reload),
            ),
          ),
        ),
        data: (detail) => _DetailContent(detail: detail),
      ),
    );
  }
}

/// 详情页主体：背景层固定在顶部不随滚动，内容层盖在上面滚动。
///
/// 结构与 AniBaka 的番剧详情页一致 —— 根 `Stack` 里放背景，`SafeArea` 里的
/// `NestedScrollView` 依次是标题栏、头部信息块、吸顶的 Tab 栏，最后才是各页签正文。
class _DetailContent extends StatefulWidget {
  const _DetailContent({required this.detail});

  final GetchuPreviewDetail detail;

  @override
  State<_DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends State<_DetailContent> {
  void _playTrailer(int index) {
    final detail = widget.detail;
    final trailer = detail.trailers[index];
    final video = VideoDetail(
      id: 'getchu-${detail.id}-$index',
      title: detail.trailers.length == 1
          ? detail.title
          : '${detail.title} ${index + 1}',
      coverUrl: trailer.posterUrl ?? detail.coverUrl,
      artist: detail.brand,
      uploadDate: detail.releaseDate,
      description: detail.description,
      sources: [
        for (final source in trailer.sources)
          VideoSource(
            quality: source.quality ?? 'Trailer',
            url: source.url,
            type: 'video/mp4',
          ),
      ],
      tags: const [],
      playlist: const [],
      related: const [],
    );
    context.push('/video/${video.id}', extra: video);
  }

  void _openProduct() => launchUrl(
    Uri.parse(widget.detail.productUrl),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final isWide = MediaQuery.sizeOf(context).width > kGetchuWideBreakpoint;
    // 内容卡片的底色。不能用 theme.scaffoldBackgroundColor —— 后者在本应用里是
    // Colors.transparent（底色交给 AppBackdrop 画），拿它当正文底色等于没底，
    // 背景图会直接透到正文和吸顶页签栏底下。
    //
    // 也不能直接用页面画布色（AppPageColors）：两者同色时卡片和画布连成一片，
    // 圆角轮廓完全看不见，看着就是一整面白底。这里比画布亮一档把它们分开。
    final cardSurface = dark ? const Color(0xFF141A26) : Colors.white;
    final titleColor = dark ? Colors.white : Colors.black;
    final subtitleColor = dark ? Colors.white54 : const Color(0xFF8E8E93);
    final dividerColor = dark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .05);
    final cardColor = dark
        ? Colors.white.withValues(alpha: .05)
        : const Color(0xFFF2F2F7);

    final tabs = _buildTabs(
      detail: detail,
      l10n: l10n,
      isWide: isWide,
      isDark: dark,
      titleColor: titleColor,
      subtitleColor: subtitleColor,
      cardColor: cardColor,
      dividerColor: dividerColor,
    );

    final tabBar = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: titleColor,
      unselectedLabelColor: subtitleColor,
      indicatorColor: titleColor,
      indicatorWeight: 3,
      indicatorPadding: const EdgeInsets.only(top: 44),
      labelPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      labelStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      dividerColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      tabs: [for (final tab in tabs) Tab(text: tab.$1)],
    );

    return Stack(
      children: [
        // 背景层留在滚动视图外，滚动时大图不动。
        // 与下方内容同宽同圆角：两者拼起来才像一个容器，两侧露出画布底色。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: isWide ? 560 : 420,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: kGetchuContentMaxWidth,
              ),
              child: GetchuBackdrop(
                // 封面是竖版（500×715，比例 0.7），铺进 1400×560 的横条要放大
                // 2.8 倍、只留中间 28%，角色被裁得只剩一截。图集样张是横版
                // （710×400，比例 1.78），同一块地方能留到 71%，角色是全身构图。
                // 取不到样张时退回封面。
                imageUrl: detail.sampleImages.isNotEmpty
                    ? detail.sampleImages.first
                    : detail.coverUrl,
                fallbackImageUrl: detail.coverUrl,
                height: isWide ? 560 : 420,
                surfaceColor: cardSurface,
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              // 内容区宽度上限。比例子里的 1200 再宽一档，正文行宽才撑得开。
              constraints: const BoxConstraints(
                maxWidth: kGetchuContentMaxWidth,
              ),
              // 裁在卡片圆角内：页签吸顶后正文还在往上滚，不裁的话内容会
              // 从顶部圆角两侧的直角处顶出来，看着像滚动跑出了容器。
              child: ClipRRect(
                borderRadius: kGetchuContentTopRadius,
                child: DefaultTabController(
                  length: tabs.length,
                  child: NestedScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverAppBar(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        pinned: false,
                        foregroundColor: titleColor,
                        title: Text(
                          l10n.getchuPreviewDetail,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -.5,
                            color: titleColor,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        sliver: SliverToBoxAdapter(
                          child: GetchuHeader(
                            detail: detail,
                            onPlayTrailer: detail.trailers.isEmpty
                                ? null
                                : () => _playTrailer(0),
                            onOpenProduct: _openProduct,
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TabBarDelegate(
                          tabBar: tabBar,
                          backgroundColor: cardSurface,
                          borderColor: dividerColor,
                          isWide: isWide,
                        ),
                      ),
                    ],
                    body: Container(
                      color: cardSurface,
                      child: TabBarView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          for (final tab in tabs)
                            Builder(
                              key: PageStorageKey((detail.id, tab.$1)),
                              builder: tab.$2,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 页签按内容有无动态生成：概览总有，图集/系列有内容才加。
  List<(String, WidgetBuilder)> _buildTabs({
    required GetchuPreviewDetail detail,
    required AppLocalizations l10n,
    required bool isWide,
    required bool isDark,
    required Color titleColor,
    required Color subtitleColor,
    required Color cardColor,
    required Color dividerColor,
  }) {
    final sections = detail.sections.isEmpty && detail.description != null
        ? [GetchuPreviewSection(title: '商品紹介', body: detail.description!)]
        : detail.sections;
    final info = _infoEntries(detail, l10n);

    final tabs = <(String, WidgetBuilder)>[
      (
        l10n.overview,
        (_) {
          final summary = _SummarySection(
            sections: sections,
            l10n: l10n,
            titleColor: titleColor,
            isDark: isDark,
          );
          if (!isWide) {
            return _wrapTabContent(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  if (info.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _InfoCard(
                      entries: info,
                      titleColor: titleColor,
                      subtitleColor: subtitleColor,
                      cardColor: cardColor,
                      dividerColor: dividerColor,
                    ),
                  ],
                ],
              ),
            );
          }
          return _wrapTabContent(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: summary),
                if (info.isNotEmpty) ...[
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 1,
                    child: _InfoCard(
                      entries: info,
                      titleColor: titleColor,
                      subtitleColor: subtitleColor,
                      cardColor: cardColor,
                      dividerColor: dividerColor,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ];

    if (detail.trailers.length > 1) {
      tabs.add((
        l10n.trailers,
        (_) => _wrapTabContent(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < detail.trailers.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PressScale(
                    child: OutlinedButton.icon(
                      onPressed: () => _playTrailer(index),
                      icon: const Icon(Symbols.play_circle_rounded),
                      label: Text(l10n.trailerNumber(index + 1)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
    }

    if (detail.sampleImages.isNotEmpty) {
      tabs.add((
        l10n.gallery,
        (_) => _GalleryTab(images: detail.sampleImages, isWide: isWide),
      ));
    }

    if (detail.seriesItems.isNotEmpty) {
      tabs.add((
        l10n.getchuSeries,
        (_) => _wrapTabContent(
          _SeriesGrid(items: detail.seriesItems, isWide: isWide),
        ),
      ));
    }

    return tabs;
  }

  /// 基本信息键值对，空值自动跳过。
  List<(String, String)> _infoEntries(
    GetchuPreviewDetail detail,
    AppLocalizations l10n,
  ) {
    return [
      if (detail.brand != null && detail.brand!.trim().isNotEmpty)
        (l10n.studio, detail.brand!),
      if (detail.releaseDate != null && detail.releaseDate!.trim().isNotEmpty)
        (l10n.releaseDateLabel, detail.releaseDate!),
      if (detail.price != null && detail.price!.trim().isNotEmpty)
        (l10n.priceLabel, detail.price!),
      if (detail.seriesItems.isNotEmpty)
        (l10n.getchuSeries, l10n.seriesItemCount(detail.seriesItems.length)),
      if (detail.sampleImages.isNotEmpty)
        (l10n.gallery, l10n.imageCount(detail.sampleImages.length)),
    ];
  }

  Widget _wrapTabContent(Widget child) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
    child: child,
  );
}

/// 概览左栏：各个文本小节（商品介绍 / 故事 / 制作人员）。
class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.sections,
    required this.l10n,
    required this.titleColor,
    required this.isDark,
  });

  final List<GetchuPreviewSection> sections;
  final AppLocalizations l10n;
  final Color titleColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: .8)
        : const Color(0xFF3A3A3C);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, section) in sections.indexed) ...[
            if (index > 0) const SizedBox(height: 24),
            Text(
              _localizedTitle(section.title),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: titleColor,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              section.body,
              style: TextStyle(
                color: bodyColor,
                fontSize: 15,
                height: 1.65,
                letterSpacing: .2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _localizedTitle(String raw) => switch (raw) {
    final value when value.contains('商品紹介') => l10n.productIntroduction,
    final value when value.contains('ストーリー') => l10n.story,
    final value when value.contains('スタッフ') => l10n.staff,
    final value => value,
  };
}

/// 概览右栏那张基本信息卡片。
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.entries,
    required this.titleColor,
    required this.subtitleColor,
    required this.cardColor,
    required this.dividerColor,
  });

  final List<(String, String)> entries;
  final Color titleColor;
  final Color subtitleColor;
  final Color cardColor;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              l10n.basicInfo,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final (index, entry) in entries.indexed) ...[
                  if (index > 0)
                    Divider(color: dividerColor, height: 1, thickness: .5),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            entry.$1,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            entry.$2,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 图集页签：等宽网格，点开看大图。
class _GalleryTab extends StatelessWidget {
  const _GalleryTab({required this.images, required this.isWide});

  final List<String> images;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .72,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) => PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => _ImageViewer(images: images, initialIndex: index),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: AppCachedNetworkImage(
              imageUrl: images[index],
              httpHeaders: _getchuImageHeaders,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
  }
}

/// 系列商品页签：网格。
class _SeriesGrid extends StatelessWidget {
  const _SeriesGrid({required this.items, required this.isWide});

  final List<GetchuPreviewItem> items;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontal = 20.0;
        const spacing = 12.0;
        final columns = isWide ? 5 : 2;
        final usable = constraints.maxWidth - horizontal * 2;
        final cardWidth = (usable - spacing * (columns - 1)) / columns;
        return GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: 16,
          ),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: spacing,
            mainAxisExtent: getchuCardHeight(cardWidth),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => GetchuCard(item: items[index]),
        );
      },
    );
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late var _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (value) => setState(() => _index = value),
          itemBuilder: (context, index) => InteractiveViewer(
            child: Center(
              child: AppCachedNetworkImage(
                imageUrl: widget.images[index],
                httpHeaders: _getchuImageHeaders,
                fit: BoxFit.contain,
                fadeInDuration: Duration.zero,
              ),
            ),
          ),
        ),
        SafeArea(
          child: PressScale(
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              color: Colors.white,
              icon: const Icon(Symbols.close_rounded),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Text(
            '${_index + 1} / ${widget.images.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

/// 吸顶 Tab 栏：宽屏顶部两个圆角，底下一条细线。
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({
    required this.tabBar,
    required this.backgroundColor,
    required this.borderColor,
    this.isWide = false,
  });

  final TabBar tabBar;
  final Color backgroundColor;
  final Color borderColor;
  final bool isWide;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: isWide
          ? const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))
          : null,
      border: Border(bottom: BorderSide(color: borderColor, width: .5)),
    ),
    child: tabBar,
  );

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar ||
      backgroundColor != oldDelegate.backgroundColor ||
      borderColor != oldDelegate.borderColor ||
      isWide != oldDelegate.isWide;
}
