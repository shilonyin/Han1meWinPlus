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
import 'getchu_preview_controller.dart';
import 'getchu_detail_hero.dart';

const _getchuImageHeaders = {'Referer': 'https://www.getchu.com/', 'Cookie': 'getchu_adalt_flag=getchu.com; gc=gc'};

class GetchuPreviewDetailPage extends ConsumerWidget {
  const GetchuPreviewDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final result = ref.watch(getchuPreviewDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.getchuPreviewDetail)),
      body: result.when(
        loading: () => const Center(child: M3EContainedLoadingIndicator()),
        error: (error, _) => Center(child: PressScale(child: OutlinedButton.icon(onPressed: () => ref.invalidate(getchuPreviewDetailProvider(id)), icon: const Icon(Symbols.refresh_rounded), label: Text(l10n.reload)))),
        data: (detail) => _DetailContent(detail: detail),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.detail});

  final GetchuPreviewDetail detail;

  @override
  Widget build(BuildContext context) {
    final sections = detail.sections.isEmpty && detail.description != null
        ? [GetchuPreviewSection(title: '商品紹介', body: detail.description!)]
        : detail.sections;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _DetailHero(detail: detail),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _InfoRow(detail: detail),
        ),
        for (final section in sections) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TextSection(section: section),
          ),
        ],
        if (detail.sampleImages.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SampleImages(images: detail.sampleImages),
        ],
        if (detail.seriesItems.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SeriesItems(items: detail.seriesItems),
        ],
      ],
    );
  }
}

/// 顶部：整宽背景图 + 浮在上面的竖版封面、标题与按钮。
///
/// 侧栏 / 窄窗口下横排放不下，自动改成封面在上、文字在下。
class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.detail});

  final GetchuPreviewDetail detail;

  static const double _backdropHeight = 220;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final coverWidth = width >= 420 ? 132.0 : 96.0;
        // 扣掉左右内边距与封面、间距后，文字区至少要留 180
        final horizontal = width - 32 - coverWidth - 16 >= 180;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(detail.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (detail.trailers.isNotEmpty)
                  PressScale(child: FilledButton.icon(onPressed: () => _play(context, detail, 0), icon: const Icon(Symbols.play_arrow_rounded), label: Text(l10n.playTrailer))),
                PressScale(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(detail.productUrl), mode: LaunchMode.externalApplication), icon: const Icon(Symbols.open_in_new_rounded), label: Text(l10n.openGetchu))),
              ],
            ),
            if (detail.trailers.length > 1) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (var index = 1; index < detail.trailers.length; index++)
                    PressScale(child: TextButton.icon(onPressed: () => _play(context, detail, index), icon: const Icon(Symbols.play_circle_rounded), label: Text(l10n.trailerNumber(index + 1)))),
                ],
              ),
            ],
          ],
        );
        final cover = GetchuCover(imageUrl: detail.coverUrl, width: coverWidth, httpHeaders: _getchuImageHeaders);
        return Stack(
          children: [
            GetchuBackdrop(imageUrl: detail.coverUrl, height: _backdropHeight, httpHeaders: _getchuImageHeaders),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
                child: horizontal
                    ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [cover, const SizedBox(width: 16), Expanded(child: text)])
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [cover, const SizedBox(height: 12), text]),
              ),
            ),
          ],
        );
      },
    );
  }

  void _play(BuildContext context, GetchuPreviewDetail detail, int index) {
    final trailer = detail.trailers[index];
    final video = VideoDetail(
      id: 'getchu-${detail.id}-$index',
      title: detail.trailers.length == 1 ? detail.title : '${detail.title} ${index + 1}',
      coverUrl: trailer.posterUrl ?? detail.coverUrl,
      artist: detail.brand,
      uploadDate: detail.releaseDate,
      description: detail.description,
      sources: [for (final source in trailer.sources) VideoSource(quality: source.quality ?? 'Trailer', url: source.url, type: 'video/mp4')],
      tags: const [],
      playlist: const [],
      related: const [],
    );
    context.push('/video/${video.id}', extra: video);
  }
}

/// 标题下面那行元信息：厂商 · 发售日 · 价格
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.detail});

  final GetchuPreviewDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [detail.brand, detail.releaseDate, detail.price].whereType<String>().where((value) => value.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) Text('·', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          Text(item, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({required this.section});

  final GetchuPreviewSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = switch (section.title) {
      final value when value.contains('商品紹介') => l10n.productIntroduction,
      final value when value.contains('ストーリー') => l10n.story,
      final value when value.contains('スタッフ') => l10n.staff,
      final value => value,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SelectionArea(child: Text(section.body, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    );
  }
}

class _SampleImages extends StatelessWidget {
  const _SampleImages({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.previewImages(images.length), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => PressScale(child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              onTap: () => showDialog<void>(context: context, barrierColor: Colors.black87, builder: (_) => _ImageViewer(images: images, initialIndex: index)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: AppCachedNetworkImage(imageUrl: images[index], httpHeaders: _getchuImageHeaders, width: 200, fit: BoxFit.cover, fadeInDuration: Duration.zero),
              ),
            )),
          ),
        ),
      ],
    );
  }
}

class _SeriesItems extends StatelessWidget {
  const _SeriesItems({required this.items});

  final List<GetchuPreviewItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.getchuSeries, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _SeriesCard(item: items[index]),
          ),
        ),
      ],
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.item});

  final GetchuPreviewItem item;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 160,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: PressScale(child: InkWell(
            onTap: () => context.push('/previews/getchu/detail/${item.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: item.coverUrl == null
                      ? const ColoredBox(color: Colors.black12, child: Icon(Symbols.image_not_supported_rounded))
                      : AppCachedNetworkImage(imageUrl: item.coverUrl!, httpHeaders: _getchuImageHeaders, fit: BoxFit.cover, fadeInDuration: Duration.zero),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                      if (item.price != null) ...[const SizedBox(height: 4), Text(item.price!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)],
                    ],
                  ),
                ),
              ],
            ),
          )),
        ),
      );
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
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
              itemBuilder: (context, index) => InteractiveViewer(child: Center(child: AppCachedNetworkImage(imageUrl: widget.images[index], httpHeaders: _getchuImageHeaders, fit: BoxFit.contain, fadeInDuration: Duration.zero))),
            ),
            SafeArea(child: PressScale(child: IconButton(onPressed: () => Navigator.pop(context), color: Colors.white, icon: const Icon(Symbols.close_rounded)))),
            Positioned(left: 0, right: 0, bottom: 24, child: Text('${_index + 1} / ${widget.images.length}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
          ],
        ),
      );
}
