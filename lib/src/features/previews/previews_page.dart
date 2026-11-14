import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_radius.dart';
import '../shared/app_image_cache.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../shared/app_toast.dart';
import '../shared/hover_zoom.dart';
import '../shared/press_scale.dart';
import '../video/play_window.dart';
import 'preview_grid.dart';
import '../shared/app_top_bar.dart';

final previewsProvider = FutureProvider.autoDispose.family<PreviewFeed, String>(
  (ref, month) async {
    ref.keepAlive();
    final settings = await ref.watch(settingsProvider.future);
    return ref
        .watch(han1meRepositoryProvider)
        .previews(settings.resolvedBaseUrl, month);
  },
);

/// 默认站点的预告表经常整页 500（服务端问题，不是客户端能修的）。
///
/// 这个 provider 只在「自动 / 默认站点」模式下被读取：页面会先看它的结果，
/// 失败就换 Getchu。所以这里**把 500 转成空结果**，让页面走「没有数据 → 切源」
/// 这条路，而不是把异常抛到 Riverpod 之外变成一条「未捕获异常」——
/// 日志里那两行 `DioException [unknown]: Request failed: HTTP 500` 就是这么来的，
/// 用户那边则会看到一张报错页再加一条红色异常记录。
///
/// 只吞服务端的 5xx / 连接失败：其它异常（解析崩了、状态码 4xx 说明参数有问题）
/// 照常上抛，别拿「站点挂了」遮住真正需要修的 bug。
final defaultPreviewSourceProvider = FutureProvider.autoDispose
    .family<PreviewFeed?, String>((ref, month) async {
      final settings = await ref.watch(settingsProvider.future);
      try {
        return await ref
            .watch(han1meRepositoryProvider)
            .previews(settings.resolvedBaseUrl, month);
      } catch (error) {
        if (_isServerSideFailure(error)) {
          debugPrint('[previews] 默认站点预告不可用（$error），交给调用方切源');
          return null;
        }
        rethrow;
      }
    });

/// 判断这个异常是不是「站点那边的问题」——5xx 或连接层失败。
///
/// 这两种情况下换源有意义；4xx 或解析错误换源也没用，应该让用户看到真实原因。
bool _isServerSideFailure(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null && status >= 500) return true;
    // 连接类错误（超时、握手失败、被重置）没有状态码。
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };
  }
  return false;
}

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
      showAppToast(
        context,
        AppLocalizations.of(context)!.previewSourceSwitched,
      );
      context.replace('/previews/getchu/${widget.month}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedMonth = _PreviewMonth.parse(widget.month);
    // 用 `defaultPreviewSourceProvider` 而不是 `previewsProvider`：前者把「站点 5xx」
    // 收敛成 null（见其说明），页面据此走「切到 Getchu」这条路，不会再把
    // `HTTP 500` 抛成一条未捕获异常。真实的数据结构错误仍会以 error 状态进来。
    final result = ref.watch(defaultPreviewSourceProvider(widget.month));
    final auto =
        (ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto') ==
        'auto';
    return Scaffold(
      appBar: AppTopBar(
        // 影院沉浸式：顶栏透明，标题下放到内容区做大标题。
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          PressScale(
            child: IconButton(
              tooltip: l10n.getchuPreviews,
              onPressed: () => context.push('/previews/getchu/${widget.month}'),
              icon: const Icon(Symbols.calendar_month_rounded),
            ),
          ),
          PressScale(
            child: IconButton(
              tooltip: l10n.comments,
              onPressed: () => context.push(
                '/comments/preview/${widget.month}',
                extra: l10n.previews,
              ),
              icon: const Icon(Symbols.forum_rounded),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.previews,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
            ),
          ),
          _MonthNavigation(
            month: selectedMonth,
            onPrevious: () => _replaceMonth(context, selectedMonth.previous),
            onNext: selectedMonth.isCurrentOrFuture
                ? null
                : () => _replaceMonth(context, selectedMonth.next),
            onSelect: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: selectedMonth.date,
                firstDate: DateTime(1990),
                lastDate: _PreviewMonth.current.date,
                initialDatePickerMode: DatePickerMode.year,
              );
              if (selected != null && context.mounted) {
                _replaceMonth(
                  context,
                  _PreviewMonth(selected.year, selected.month),
                );
              }
            },
          ),
          Expanded(
            child: result.when(
              loading: () =>
                  const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) {
                if (auto) {
                  _scheduleGetchuFallback();
                  // 这里不能只给转圈：默认站点失败后要等 Getchu 那边响应，
                  // 遇到慢响应（实测月份页 3.8s）用户分不清是在加载还是已经失败。
                  return _SwitchingSource(error: error);
                }
                return _PreviewUnavailable(
                  title: l10n.previewUnavailable,
                  description: l10n.previewUnavailableDescription,
                  onPrevious: () =>
                      _replaceMonth(context, selectedMonth.previous),
                  onRetry: () => ref.invalidate(
                    defaultPreviewSourceProvider(widget.month),
                  ),
                );
              },
              data: (feed) {
                // feed 为 null：默认站点整页 5xx（provider 已把它收敛成 null）。
                // 自动模式下直接切 Getchu；用户显式选了「默认站点」时说明他想用这个源，
                // 这时给一张「源不可用」的页面让能手动重试或换月份，而不是硬切走。
                if (feed == null) {
                  if (auto) {
                    _scheduleGetchuFallback();
                    return const _SwitchingSource(detail: '默认站点的预告表暂时不可用');
                  }
                  return _PreviewUnavailable(
                    title: l10n.previewUnavailable,
                    description: l10n.previewUnavailableDescription,
                    onPrevious: () =>
                        _replaceMonth(context, selectedMonth.previous),
                    onRetry: () => ref.invalidate(
                      defaultPreviewSourceProvider(widget.month),
                    ),
                  );
                }
                if (feed.items.isEmpty && auto) {
                  _scheduleGetchuFallback();
                  return _SwitchingSource(detail: l10n.previewNoItems);
                }
                return feed.items.isEmpty
                    ? _PreviewUnavailable(
                        title: l10n.noPreviews,
                        description: l10n.noPreviewsDescription,
                        onPrevious: () =>
                            _replaceMonth(context, selectedMonth.previous),
                        onRetry: () => ref.invalidate(
                          defaultPreviewSourceProvider(widget.month),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // 横向卡片：高度固定（封面 84 + 上下内边距），列数只按宽度算，
                          // 不再按高度反推 —— 横向卡本来就矮，一屏能放下好几排。
                          final gridDelegate = _previewGridDelegate(
                            constraints,
                          );
                          return CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: _PreviewHeader(feed: feed),
                              ),
                              ..._groupedPreviewSlivers(
                                context,
                                feed.items,
                                gridDelegate,
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 24),
                              ),
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

  void _replaceMonth(BuildContext context, _PreviewMonth month) =>
      context.replace('/previews/${month.value}');
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
    return year == null || month == null || month < 1 || month > 12
        ? current
        : _PreviewMonth(year, month);
  }

  DateTime get date => DateTime(year, month);
  String get value => '$year${month.toString().padLeft(2, '0')}';
  String get label => '$year${month.toString().padLeft(2, '0')}';
  _PreviewMonth get previous => _fromDate(DateTime(year, month - 1));
  _PreviewMonth get next => _fromDate(DateTime(year, month + 1));
  bool get isCurrentOrFuture => date.compareTo(current.date) >= 0;

  static _PreviewMonth _fromDate(DateTime value) =>
      _PreviewMonth(value.year, value.month);
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final _PreviewMonth month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppDesignTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppDesignTokens.strokeOf(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              PressScale(
                child: IconButton(
                  tooltip: l10n.previousMonth,
                  onPressed: onPrevious,
                  icon: Icon(
                    Symbols.chevron_left_rounded,
                    color: AppDesignTokens.inkSubtleOf(context),
                  ),
                ),
              ),
              Expanded(
                child: PressScale(
                  child: TextButton.icon(
                    onPressed: onSelect,
                    style: TextButton.styleFrom(
                      foregroundColor: AppDesignTokens.accentDeep,
                    ),
                    icon: const Icon(Symbols.calendar_month_rounded, size: 18),
                    label: Text(
                      l10n.previewMonth(month.label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.inkOf(context),
                      ),
                    ),
                  ),
                ),
              ),
              PressScale(
                child: IconButton(
                  tooltip: l10n.nextMonth,
                  onPressed: onNext,
                  icon: Icon(
                    Symbols.chevron_right_rounded,
                    color: onNext == null
                        ? AppDesignTokens.inkMutedOf(context)
                        : AppDesignTokens.inkSubtleOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 默认站点取不到预告、正要换用 Getchu 时的等待界面。
///
/// 它和纯转圈的区别是把「为什么在等」写出来：默认站点失败后还要等 Getchu
/// 整页响应（实测月份页 3.8 秒），只给一个转圈的话，用户分不清是在加载
/// 还是已经失败了。
class _SwitchingSource extends StatelessWidget {
  const _SwitchingSource({this.error, this.detail});

  /// 默认站点这次的失败原因，有就一并显示。
  final Object? error;

  /// 没有异常对象时的说明（例如接口通了但一条都没返回）。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final reason = detail ?? _describe(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const M3EContainedLoadingIndicator(),
            const SizedBox(height: 20),
            Text(
              l10n.previewSwitchingSource,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.previewSwitchingSourceDetail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (reason != null) ...[
              const SizedBox(height: 12),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 把异常压成一行人话。CF 硬拦和普通超时要能分开看 —— 前者换网络才有救，
  /// 后者重试就行，混成一句「加载失败」用户没法判断该怎么办。
  static String? _describe(Object? error) {
    if (error == null) return null;
    if (error is CloudflareChallengeException) {
      return error.blocked ? 'Cloudflare 拒绝了当前网络的出口 IP' : '需要先通过 Cloudflare 验证';
    }
    final text = error.toString();
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }
}

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({
    required this.title,
    required this.description,
    required this.onPrevious,
    required this.onRetry,
  });

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
            const Icon(Symbols.event_busy_rounded, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                PressScale(
                  child: FilledButton.tonalIcon(
                    onPressed: onPrevious,
                    icon: const Icon(Symbols.chevron_left_rounded),
                    label: Text(l10n.previousMonth),
                  ),
                ),
                PressScale(
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Symbols.refresh_rounded),
                    label: Text(l10n.reload),
                  ),
                ),
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
          child: AppCachedNetworkImage(
            imageUrl: feed.coverUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 960,
            faceFocus: true,
            fadeInDuration: Duration.zero,
            errorWidget: (context, url, error) => ColoredBox(
              color: AppDesignTokens.fieldFillOf(context),
              child: Icon(
                Symbols.image_rounded,
                size: 32,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          feed.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.inkOf(context),
            height: 1.3,
          ),
        ),
      ),
      if (feed.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            feed.description,
            style: TextStyle(
              fontSize: 12,
              color: AppDesignTokens.inkSubtleOf(context),
              height: 1.5,
            ),
          ),
        ),
    ],
  );
}

/// 单张预告卡：设计稿是「左方图 + 右信息列」的横向卡片。
///
/// 左封面 84×84 方图、圆角；右侧自上而下是标题（13 Bold ink）、作者（11 inkSubtle）、
/// 「预订中」粉色胶囊 + 日期（11 inkMuted）。白底 surface、圆角 12、1px stroke 描边、
/// 不加重阴影。数据模型里没有价格字段，所以设计稿那一行 ¥ 价不做（不编造数据）。
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.item});

  final PreviewItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = item.brand ?? item.videoTitle ?? '';
    return CardHover(
      builder: (context, hovered) => PressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => openVideo(context, ref, item.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ZoomOnHover(
                          hovered: hovered,
                          child: AppCachedNetworkImage(
                            imageUrl: item.coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            faceFocus: true,
                            fadeInDuration: Duration.zero,
                            errorWidget: (context, url, error) => ColoredBox(
                              color: AppDesignTokens.fieldFillOf(context),
                              child: Icon(Symbols.image_rounded,
                                  size: 28,
                                  color: AppDesignTokens.inkMutedOf(context)),
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 8,
                          top: 8,
                          child: _PreviewBadge(text: '预订中'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.inkOf(context),
                    height: 1.25,
                  ),
                ),
                if (author.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppDesignTokens.inkSubtleOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「预订中」胶囊：淡粉底 + [AppDesignTokens.accent] 文字。
class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppDesignTokens.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppDesignTokens.accentDeep,
          height: 1.2,
        ),
      ),
    ),
  );
}

/// 横向预告卡的网格：卡片高度固定，列数按可用宽度取（最窄 260，最多 4 列）。
SliverGridDelegate _previewGridDelegate(BoxConstraints constraints) {
  const padding = PreviewGridMetrics.horizontalPadding;
  const spacing = PreviewGridMetrics.spacing;
  const minCardWidth = 180.0;
  final usable = (constraints.maxWidth - padding * 2).clamp(0.0, double.infinity);
  final rawColumns = ((usable + spacing) / (minCardWidth + spacing)).floor();
  final columns = rawColumns < 1 ? 1 : (rawColumns > 6 ? 6 : rawColumns);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: 18,
    crossAxisSpacing: 14,
    childAspectRatio: 0.56,
  );
}

/// 按上映日期把预告片分组，每组一个小标题 + 网格（v6 设计稿的分组版式）。
List<Widget> _groupedPreviewSlivers(
  BuildContext context,
  List<PreviewItem> items,
  SliverGridDelegate gridDelegate,
) {
  final groups = <String, List<PreviewItem>>{};
  for (final item in items) {
    final key = (item.releaseDate ?? '').trim();
    groups.putIfAbsent(key, () => <PreviewItem>[]).add(item);
  }
  final slivers = <Widget>[];
  for (final entry in groups.entries) {
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppDesignTokens.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.key.isEmpty ? '其他' : entry.key,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.inkOf(context),
                  height: 1.3,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${entry.value.length} 部新作',
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.inkMutedOf(context),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.symmetric(
          horizontal: PreviewGridMetrics.horizontalPadding,
        ),
        sliver: SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemCount: entry.value.length,
          itemBuilder: (context, index) =>
              _PreviewCard(item: entry.value[index]),
        ),
      ),
    );
  }
  return slivers;
}
