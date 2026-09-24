import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../shared/app_image_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/getchu_preview.dart';
import 'getchu_preview_controller.dart';
import 'preview_grid.dart';

class GetchuPreviewPage extends ConsumerWidget {
  const GetchuPreviewPage({super.key, required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedMonth = GetchuPreviewMonth.parse(month);
    final result = ref.watch(getchuPreviewsProvider(selectedMonth.value));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.getchuPreviews)),
      body: Column(
        children: [
          _MonthNavigation(
            month: selectedMonth,
            onPrevious: () => _replaceMonth(context, selectedMonth.previous),
            onNext: () => _replaceMonth(context, selectedMonth.next),
            onSelect: () => _selectMonth(context, selectedMonth),
          ),
          Expanded(
            child: result.when(
              loading: () => const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) => _Unavailable(error: error, onRetry: () => ref.invalidate(getchuPreviewsProvider(selectedMonth.value))),
              data: (feed) => feed.groups.isEmpty
                  ? _Unavailable(onRetry: () => ref.invalidate(getchuPreviewsProvider(selectedMonth.value)))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final metrics = PreviewGridMetrics.of(constraints, coverRatio: 4 / 3, detailsHeight: 60);
                        return CustomScrollView(
                          slivers: [
                            for (final group in feed.groups) ...[
                              SliverToBoxAdapter(child: _GroupHeader(title: group.releaseDate)),
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(horizontal: PreviewGridMetrics.horizontalPadding),
                                sliver: SliverGrid.builder(
                                  gridDelegate: metrics.delegate,
                                  itemCount: group.items.length,
                                  itemBuilder: (context, index) => _PreviewCard(item: group.items[index]),
                                ),
                              ),
                            ],
                            const SliverToBoxAdapter(child: SizedBox(height: 24)),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectMonth(BuildContext context, GetchuPreviewMonth month) async {
    final selected = await showDatePicker(context: context, initialDate: month.date, firstDate: DateTime(1990), lastDate: DateTime(DateTime.now().year + 2, 12), initialDatePickerMode: DatePickerMode.year);
    if (selected != null && context.mounted) _replaceMonth(context, GetchuPreviewMonth(selected.year, selected.month));
  }

  void _replaceMonth(BuildContext context, GetchuPreviewMonth month) => context.replace('/previews/getchu/${month.value}');
}

class GetchuPreviewMonth {
  const GetchuPreviewMonth(this.year, this.month);

  final int year;
  final int month;

  factory GetchuPreviewMonth.parse(String value) {
    final now = DateTime.now();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return GetchuPreviewMonth(now.year, now.month);
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4));
    return year == null || month == null || month < 1 || month > 12 ? GetchuPreviewMonth(now.year, now.month) : GetchuPreviewMonth(year, month);
  }

  DateTime get date => DateTime(year, month);
  String get value => '$year${month.toString().padLeft(2, '0')}';
  GetchuPreviewMonth get previous => _fromDate(DateTime(year, month - 1));
  GetchuPreviewMonth get next => _fromDate(DateTime(year, month + 1));

  static GetchuPreviewMonth _fromDate(DateTime value) => GetchuPreviewMonth(value.year, value.month);
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({required this.month, required this.onPrevious, required this.onNext, required this.onSelect});

  final GetchuPreviewMonth month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(tooltip: l10n.previousMonth, onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
            Expanded(child: TextButton.icon(onPressed: onSelect, icon: const Icon(Icons.calendar_month_outlined, size: 18), label: Text(l10n.getchuPreviewMonth(month.value)))),
            IconButton(tooltip: l10n.nextMonth, onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.item});

  final GetchuPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/previews/getchu/detail/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.coverUrl == null)
                    ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.image_not_supported_outlined))
                  else
                    CachedNetworkImage(
                      imageUrl: item.coverUrl!,
                      cacheManager: appImageCacheManager,
                      httpHeaders: const {'Referer': 'https://www.getchu.com/', 'Cookie': 'getchu_adalt_flag=getchu.com; gc=gc'},
                      fit: BoxFit.cover,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                    ),
                  // 只在标题所占的底部区域做深色底：原来从 45% 就开始淡淡压暗，
                  // 到底部也只有 70% 黑 —— 海报上半部分被洗淡、标题压在亮色画面上仍不清楚。
                  // 现在把渐变收短、末尾加深，上半张画完全不受影响。
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000), Color(0xE6000000)],
                        stops: [0.62, 0.86, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1))],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.brand ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  if (item.price != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.price!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry, this.error});

  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 56),
            const SizedBox(height: 16),
            Text(error == null ? l10n.noGetchuPreviews : l10n.getchuPreviewUnavailable, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l10n.reload)),
          ],
        ),
      ),
    );
  }
}
