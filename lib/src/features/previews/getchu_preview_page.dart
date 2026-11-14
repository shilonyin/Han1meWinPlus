import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../shared/press_scale.dart';
import 'getchu_card.dart';
import 'getchu_preview_controller.dart';
import 'preview_grid.dart';

/// 本页统一使用的圆角：卡片、导航条、页码等容器一律走这一档。
const double _kCardRadius = 14.0;

class GetchuPreviewPage extends ConsumerWidget {
  const GetchuPreviewPage({super.key, required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedMonth = GetchuPreviewMonth.parse(month);
    final result = ref.watch(getchuPreviewsProvider(selectedMonth.value));
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackgroundOf(context),
      appBar: _buildAppBar(context, l10n),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              PreviewGridMetrics.horizontalPadding,
              6,
              PreviewGridMetrics.horizontalPadding,
              2,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.getchuPreviews,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PreviewGridMetrics.horizontalPadding,
              4,
              PreviewGridMetrics.horizontalPadding,
              8,
            ),
            child: _MonthNavigation(
              month: selectedMonth,
              onPrevious: () => _replaceMonth(context, selectedMonth.previous),
              onNext: () => _replaceMonth(context, selectedMonth.next),
              onSelect: () => _selectMonth(context, selectedMonth),
            ),
          ),
          Expanded(
            child: result.when(
              loading: () =>
                  const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) => _Unavailable(
                error: error,
                onRetry: () =>
                    ref.invalidate(getchuPreviewsProvider(selectedMonth.value)),
              ),
              data: (feed) => feed.groups.isEmpty
                  ? _Unavailable(
                      onRetry: () => ref.invalidate(
                        getchuPreviewsProvider(selectedMonth.value),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // 一屏至少露出两排海报，所以允许比默认 4 列更多列。
                        // 44 是首个分组标题的高度（它跟着滚动区走，但首屏顶上就有一条）。
                        final metrics = PreviewGridMetrics.of(
                          constraints,
                          // 这里的 coverRatio 是「高 / 宽」，与 kGetchuCoverRatio
                          // 的「宽 / 高」互为倒数。传错会让行高只有实际的一半，
                          // 封面溢到下一排上。
                          coverRatio: 1 / kGetchuCoverRatio,
                          detailsHeight: kGetchuDetailsHeight,
                          minRows: 2,
                          maxColumns: 8,
                          reservedHeight: 44,
                        );
                        return CustomScrollView(
                          slivers: [
                            for (final group in feed.groups) ...[
                              SliverToBoxAdapter(
                                child: _GroupHeader(title: group.releaseDate),
                              ),
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal:
                                      PreviewGridMetrics.horizontalPadding,
                                ),
                                sliver: SliverGrid.builder(
                                  gridDelegate: metrics.delegate,
                                  itemCount: group.items.length,
                                  itemBuilder: (context, index) =>
                                      GetchuCard(item: group.items[index]),
                                ),
                              ),
                            ],
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 24),
                            ),
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

  /// 页头照设计稿：标题 20 Bold、正文色；去掉了 Material 默认的阴影与滚动换色，
  /// 让页面底色一直透上来，顶栏是「平」的一块而不是浮起的灰条。
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    // 影院沉浸式：顶栏透明（只留返回），标题下放到内容区做大标题。
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: PreviewGridMetrics.horizontalPadding,
    );
  }

  Future<void> _selectMonth(
    BuildContext context,
    GetchuPreviewMonth month,
  ) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: month.date,
      firstDate: DateTime(1990),
      lastDate: DateTime(DateTime.now().year + 2, 12),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (selected != null && context.mounted) {
      _replaceMonth(context, GetchuPreviewMonth(selected.year, selected.month));
    }
  }

  void _replaceMonth(BuildContext context, GetchuPreviewMonth month) =>
      context.replace('/previews/getchu/${month.value}');
}

class GetchuPreviewMonth {
  const GetchuPreviewMonth(this.year, this.month);

  final int year;
  final int month;

  factory GetchuPreviewMonth.parse(String value) {
    final now = DateTime.now();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      return GetchuPreviewMonth(now.year, now.month);
    }
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4));
    return year == null || month == null || month < 1 || month > 12
        ? GetchuPreviewMonth(now.year, now.month)
        : GetchuPreviewMonth(year, month);
  }

  DateTime get date => DateTime(year, month);
  String get value => '$year${month.toString().padLeft(2, '0')}';
  GetchuPreviewMonth get previous => _fromDate(DateTime(year, month - 1));
  GetchuPreviewMonth get next => _fromDate(DateTime(year, month + 1));

  static GetchuPreviewMonth _fromDate(DateTime value) =>
      GetchuPreviewMonth(value.year, value.month);
}

/// 月份导航：白色底板 + 一圈描边，取代原来的玻璃面板。
/// 中间是「当前月份」，两侧是描边圆形箭头，整体与下面的卡片同一套圆角。
class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final GetchuPreviewMonth month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: AppDesignTokens.strokeOf(context)),
      ),
      child: Row(
        children: [
          _NavArrow(
            tooltip: l10n.previousMonth,
            icon: Symbols.chevron_left_rounded,
            onTap: onPrevious,
          ),
          Expanded(
            child: PressScale(
              child: TextButton.icon(
                onPressed: onSelect,
                style: TextButton.styleFrom(
                  foregroundColor: AppDesignTokens.accentDeep,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                icon: const Icon(
                  Symbols.calendar_month_rounded,
                  size: 18,
                  color: AppDesignTokens.accent,
                ),
                label: Text(
                  l10n.getchuPreviewMonth(month.value),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.accentDeep,
                  ),
                ),
              ),
            ),
          ),
          _NavArrow(
            tooltip: l10n.nextMonth,
            icon: Symbols.chevron_right_rounded,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

/// 月份导航两侧的箭头：圆形描边按钮，按下有缩放反馈。
class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        child: Material(
          color: AppDesignTokens.fieldFillOf(context),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: AppDesignTokens.inkSubtleOf(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组标题（发售日）：12.5 SemiBold、正文色，左侧一枚 accent 竖条做视觉锚点。
/// 上方留 20、下方留 10，与下面的卡片拉开层次。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PreviewGridMetrics.horizontalPadding,
      20,
      PreviewGridMetrics.horizontalPadding,
      10,
    ),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: AppDesignTokens.accent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.inkOf(context),
              height: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
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
            Icon(
              Symbols.event_busy_rounded,
              size: 56,
              color: AppDesignTokens.inkMutedOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              error == null
                  ? l10n.noGetchuPreviews
                  : l10n.getchuPreviewUnavailable,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.inkOf(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            PressScale(
              child: OutlinedButton.icon(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppDesignTokens.accentDeep,
                  side: BorderSide(color: AppDesignTokens.strokeOf(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Symbols.refresh_rounded, size: 18),
                label: Text(
                  l10n.reload,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
