import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../shared/app_image_cache.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/han1me_repository.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../shared/app_toast.dart';
import 'preview_grid.dart';

final previewsProvider = FutureProvider.autoDispose.family<PreviewFeed, String>((ref, month) async {
  ref.keepAlive();
  final settings = await ref.watch(settingsProvider.future);
  return ref.watch(han1meRepositoryProvider).previews(settings.resolvedBaseUrl, month);
});

class PreviewsPage extends ConsumerStatefulWidget {
  const PreviewsPage({super.key, required this.month});

  final String month;

  @override
  ConsumerState<PreviewsPage> createState() => _PreviewsPageState();
}

class _PreviewsPageState extends ConsumerState<PreviewsPage> {
  var _fallbackScheduled = false;

  /// 默认站点的预告表常年返回 500；「自动」模式下不要把它变成一张死页面，
  /// 直接换到 Getchu 的当月预告，并用一条居中提示告诉用户发生了什么。
  void _scheduleGetchuFallback() {
    if (_fallbackScheduled) return;
    _fallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAppToast(context, AppLocalizations.of(context)!.previewSourceSwitched);
      context.replace('/previews/getchu/${widget.month}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedMonth = _PreviewMonth.parse(widget.month);
    final result = ref.watch(previewsProvider(widget.month));
    final auto = (ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto') == 'auto';
    const fallbackPlaceholder = Center(child: M3EContainedLoadingIndicator());
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.previews),
        actions: [
          IconButton(
            tooltip: l10n.getchuPreviews,
            onPressed: () => context.push('/previews/getchu/${widget.month}'),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: l10n.comments,
            onPressed: () => context.push('/comments/preview/${widget.month}', extra: l10n.previews),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _MonthNavigation(
            month: selectedMonth,
            onPrevious: () => _replaceMonth(context, selectedMonth.previous),
            onNext: selectedMonth.isCurrentOrFuture ? null : () => _replaceMonth(context, selectedMonth.next),
            onSelect: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: selectedMonth.date,
                firstDate: DateTime(1990),
                lastDate: _PreviewMonth.current.date,
                initialDatePickerMode: DatePickerMode.year,
              );
              if (selected != null && context.mounted) _replaceMonth(context, _PreviewMonth(selected.year, selected.month));
            },
          ),
          Expanded(
            child: result.when(
              loading: () => const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) {
                if (auto) {
                  _scheduleGetchuFallback();
                  return fallbackPlaceholder;
                }
                return _PreviewUnavailable(
                  title: l10n.previewUnavailable,
                  description: l10n.previewUnavailableDescription,
                  onPrevious: () => _replaceMonth(context, selectedMonth.previous),
                  onRetry: () => ref.invalidate(previewsProvider(widget.month)),
                );
              },
              data: (feed) {
                if (feed.items.isEmpty && auto) {
                  _scheduleGetchuFallback();
                  return fallbackPlaceholder;
                }
                return feed.items.isEmpty
                    ? _PreviewUnavailable(
                        title: l10n.noPreviews,
                        description: l10n.noPreviewsDescription,
                        onPrevious: () => _replaceMonth(context, selectedMonth.previous),
                        onRetry: () => ref.invalidate(previewsProvider(widget.month)),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final metrics = PreviewGridMetrics.of(constraints, coverRatio: 16 / 9, detailsHeight: 40);
                          return CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(child: _PreviewHeader(feed: feed)),
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(horizontal: PreviewGridMetrics.horizontalPadding),
                                sliver: SliverGrid.builder(
                                  gridDelegate: metrics.delegate,
                                  itemCount: feed.items.length,
                                  itemBuilder: (context, index) => _PreviewCard(item: feed.items[index]),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                            ],
                          );
                        },
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _replaceMonth(BuildContext context, _PreviewMonth month) => context.replace('/previews/${month.value}');
}

class _PreviewMonth {
  const _PreviewMonth(this.year, this.month);

  final int year;
  final int month;

  static _PreviewMonth get current {
    final now = DateTime.now();
    return _PreviewMonth(now.year, now.month);
  }

  factory _PreviewMonth.parse(String value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return current;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    return year == null || month == null || month < 1 || month > 12 ? current : _PreviewMonth(year, month);
  }

  DateTime get date => DateTime(year, month);
  String get value => '$year${month.toString().padLeft(2, '0')}';
  String get label => '$year${month.toString().padLeft(2, '0')}';
  _PreviewMonth get previous => _fromDate(DateTime(year, month - 1));
  _PreviewMonth get next => _fromDate(DateTime(year, month + 1));
  bool get isCurrentOrFuture => date.compareTo(current.date) >= 0;

  static _PreviewMonth _fromDate(DateTime value) => _PreviewMonth(value.year, value.month);
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({required this.month, required this.onPrevious, required this.onNext, required this.onSelect});

  final _PreviewMonth month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
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
            Expanded(
              child: TextButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(l10n.previewMonth(month.label)),
              ),
            ),
            IconButton(tooltip: l10n.nextMonth, onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({required this.title, required this.description, required this.onPrevious, required this.onRetry});

  final String title;
  final String description;
  final VoidCallback onPrevious;
  final VoidCallback onRetry;

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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(onPressed: onPrevious, icon: const Icon(Icons.chevron_left), label: Text(l10n.previousMonth)),
                OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l10n.reload)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.feed});

  final PreviewFeed feed;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (feed.coverUrl != null && feed.coverUrl!.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 8,
              child: CachedNetworkImage(imageUrl: feed.coverUrl!, cacheManager: appImageCacheManager, fit: BoxFit.cover, memCacheWidth: 960, fadeInDuration: Duration.zero),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(feed.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (feed.description.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(feed.description)),
        ],
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.item});

  final PreviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/video/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(imageUrl: item.coverUrl, cacheManager: appImageCacheManager, fit: BoxFit.cover, memCacheWidth: 480, fadeInDuration: Duration.zero),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                        stops: [0.45, 1],
                      ),
                    ),
                  ),
                  if (item.releaseDate != null) Positioned(top: 8, right: 8, child: _PreviewBadge(text: item.releaseDate!)),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600, height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(child: Text(item.videoTitle ?? item.brand ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))),
                  if (item.previewImages.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.collections_outlined, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 2),
                    Text('${item.previewImages.length}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}

