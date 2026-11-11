import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
import '../../data/local/watch_repository.dart';
import '../shared/app_top_bar.dart';

/// 「统计」：按 v6 设计稿（`1792_stats.png`）排成数据看板。
///
/// 之前这一页是「日历 + 单日明细」。
/// 它和设计稿是两页不同的东西。
/// 现在改成四张概览卡 + 近 30 天观看趋势 + 观看分布 + 观看时段。
/// 所有数字都从 [watchProvider] 的真实记录算出来。
/// 不写设计稿里的演示值（62.4 小时、486 集那些）。
/// 缓存里没有的指标（例如题材分类）不编造。
/// 改成能从记录里算出来的分布。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(watchProvider).valueOrNull ?? const WatchState();
    final stats = _Stats(state);
    return Scaffold(
      appBar: AppTopBar(title: Text(l10n.statistics)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          // 页头副标题「最近 30 天」单独一行；页面标题由 AppTopBar 画，
          // 不在这里重复一遍（之前两层标题叠在一起，比设计稿多一行）。
          const Text(
            '最近 30 天',
            style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted),
          ),
          const SizedBox(height: 16),
          // 四张概览卡：总观看时长 / 已看集数 / 平均完播 / 平均单集。
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              // 最小卡宽随文字缩放，放大后数值与环比不挤在一行。
              // 列数由可用宽度推导，窄窗经 Wrap 折行，不再写死四列。
              final minCardWidth = AppResponsive.scaled(context, 180);
              final cardWidth = AppResponsive.cardWidthFor(
                availableWidth: constraints.maxWidth,
                minCardWidth: minCardWidth,
                gap: gap,
                maxColumns: 4,
              );
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final card in <Widget>[
                    _StatCard(
                      label: '总观看时长',
                      value: stats.totalLabel,
                      unit: '小时',
                      delta: stats.totalDelta,
                    ),
                    _StatCard(
                      label: '已看集数',
                      value: '${stats.count}',
                      unit: '集',
                      delta: stats.countDelta,
                    ),
                    _StatCard(
                      label: '平均完播',
                      value: '${stats.completion}',
                      unit: '%',
                      delta: stats.completionDelta,
                    ),
                    _StatCard(
                      label: '平均单集',
                      value: stats.avgLabel,
                      unit: '分钟',
                      delta: stats.avgDelta,
                    ),
                  ])
                    SizedBox(width: cardWidth, child: card),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // 观看趋势：近 30 天每日观看分钟数的柱状图。
          _TrendCard(days: stats.days),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 20.0;
              // 两张图表卡按可用宽度均分，窄窗折成单列，避免固定两列把柱子压扁。
              final minCardWidth = AppResponsive.scaled(context, 320);
              final cardWidth = AppResponsive.cardWidthFor(
                availableWidth: constraints.maxWidth,
                minCardWidth: minCardWidth,
                gap: gap,
                maxColumns: 2,
              );
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _DistributionCard(rows: stats.distribution),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _HourCard(hours: stats.hours, peak: stats.peakLabel),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 从真实观看记录算出看板需要的全部指标。
///
/// 纯计算、无 IO，方便单独测试。所有派生值都来自 [WatchState] 里已有的字段。
class _Stats {
  _Stats(this.state) {
    final histories = state.histories;
    count = histories.length;
    totalMs = histories.fold(0, (sum, item) => sum + item.watchedMs);
    // 平均完播：continueItems 里有每部片子的最后位置与总时长。
    final progresses = state.continueItems
        .where((item) => item.durationMs > 0)
        .toList();
    completion = progresses.isEmpty
        ? 0
        : (progresses.fold<double>(
                    0,
                    (sum, item) =>
                        sum +
                        (item.positionMs / item.durationMs).clamp(0.0, 1.0),
                  ) /
                  progresses.length *
                  100)
              .round();
    avgMs = count == 0 ? 0 : totalMs ~/ count;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 近 30 天，按天累计分钟数。
    for (var i = 29; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final key = _dateKey(day);
      days.add(
        _DayStat(label: '${day.month}/${day.day}', key: key, minutes: 0),
      );
    }
    final dayIndex = <String, int>{
      for (var i = 0; i < days.length; i++) days[i].key: i,
    };
    final dateCount = <String, int>{};
    for (final item in histories) {
      final idx = dayIndex[item.date];
      if (idx != null) days[idx].minutes += item.watchedMs / 60000.0;
      dateCount[item.date] = (dateCount[item.date] ?? 0) + 1;
      // 观看时段：用 createdAt 的小时。
      final hour = DateTime.fromMillisecondsSinceEpoch(item.createdAt).hour;
      if (hour >= 0 && hour < 24) hours[hour]++;
    }
    // 观看分布：按「今天 / 昨天 / 更早」聚合条数，再补一个本月合计。
    final todayKey = _dateKey(today);
    final yesterdayKey = _dateKey(today.subtract(const Duration(days: 1)));
    var todayCount = 0;
    var yesterdayCount = 0;
    var earlierCount = 0;
    var thisMonthCount = 0;
    for (final entry in dateCount.entries) {
      if (entry.key == todayKey) {
        todayCount += entry.value;
      } else if (entry.key == yesterdayKey) {
        yesterdayCount += entry.value;
      } else {
        earlierCount += entry.value;
      }
      if (entry.key.startsWith(
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
      ))
        thisMonthCount += entry.value;
    }
    final maxCount = math.max(
      1,
      math.max(
        math.max(todayCount, yesterdayCount),
        math.max(earlierCount, thisMonthCount),
      ),
    );
    distribution = [
      _Distribution(
        label: '今天',
        value: todayCount,
        ratio: todayCount / maxCount,
      ),
      _Distribution(
        label: '昨天',
        value: yesterdayCount,
        ratio: yesterdayCount / maxCount,
      ),
      _Distribution(
        label: '更早',
        value: earlierCount,
        ratio: earlierCount / maxCount,
      ),
      _Distribution(
        label: '本月',
        value: thisMonthCount,
        ratio: thisMonthCount / maxCount,
      ),
    ];
    // 环比：最近 15 天 vs 前 15 天，用分钟数算，避免编造一个变化值。
    final recent = days.skip(15).fold<double>(0, (sum, d) => sum + d.minutes);
    final previous = days.take(15).fold<double>(0, (sum, d) => sum + d.minutes);
    final diffHours = (recent - previous) / 60;
    totalDelta =
        '${diffHours >= 0 ? '+' : ''}${diffHours.toStringAsFixed(1)} 小时';
    final recentCount = histories.where((item) {
      final idx = dayIndex[item.date];
      return idx != null && idx >= 15;
    }).length;
    countDelta = '+$recentCount 集 (近 15 天)';
    completionDelta = progresses.isEmpty ? '暂无数据' : '${progresses.length} 部在追';
    avgDelta = '${(avgMs / 60000).toStringAsFixed(1)} 分钟/集';
    var peakHour = 0;
    for (var h = 1; h < 24; h++) {
      if (hours[h] > hours[peakHour]) peakHour = h;
    }
    peakLabel = hours[peakHour] == 0
        ? '暂无观看记录'
        : '高峰 ${peakHour.toString().padLeft(2, '0')}:00 前后';
  }

  final WatchState state;
  late final int count;
  late final int totalMs;
  late final int avgMs;
  late final int completion;
  final List<_DayStat> days = <_DayStat>[];
  final List<int> hours = List<int>.filled(24, 0);
  late final List<_Distribution> distribution;
  late final String totalDelta;
  late final String countDelta;
  late final String completionDelta;
  late final String avgDelta;
  late final String peakLabel;

  String get totalLabel => (totalMs / 3600000).toStringAsFixed(1);

  String get avgLabel => (avgMs / 60000).toStringAsFixed(1);

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _DayStat {
  _DayStat({required this.label, required this.key, required this.minutes});
  final String label;
  final String key;
  double minutes;
}

class _Distribution {
  const _Distribution({
    required this.label,
    required this.value,
    required this.ratio,
  });
  final String label;
  final int value;
  final double ratio;
}

/// 概览卡：标签 + 大号数值 + 单位 + 右下角环比。
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.delta,
  });

  final String label;
  final String value;
  final String unit;
  final String delta;

  @override
  Widget build(BuildContext context) => Container(
    // 基准高随文字缩放，放大后内容不被固定高裁掉，上限取视口高。
    height: AppResponsive.scaled(context, 96).clamp(
      0.0,
      MediaQuery.sizeOf(context).height,
    ),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: BoxDecoration(
      color: AppDesignTokens.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppDesignTokens.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.ink,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.inkSubtle,
                ),
              ),
            ],
          ],
        ),
        const Spacer(),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            delta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppDesignTokens.accentDeep,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 观看趋势：近 30 天柱状图，右上角「视频」分段标签。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.days});

  final List<_DayStat> days;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = days.fold<double>(
      0,
      (max, d) => math.max(max, d.minutes),
    );
    return Container(
      // 基准高随文字缩放，放大后内容不被固定高裁掉，上限取视口高。
      height: AppResponsive.scaled(context, 236).clamp(
        0.0,
        MediaQuery.sizeOf(context).height,
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '观看趋势',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.ink,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '每日观看分钟数',
                style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppDesignTokens.accentDeep,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text(
                  '视频',
                  style: TextStyle(fontSize: 10.5, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FractionallySizedBox(
                        heightFactor: maxMinutes <= 0
                            ? 0.02
                            : (day.minutes / maxMinutes).clamp(0.02, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: day.minutes > 0
                                ? AppDesignTokens.accent
                                : AppDesignTokens.divider,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadius.xs),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                '1',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '5',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '10',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '15',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '20',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '25',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '30',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 观看分布：设计稿左下的进度条列表，数据按真实日期聚合。
class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.rows});

  final List<_Distribution> rows;

  @override
  Widget build(BuildContext context) => Container(
    // 基准高随文字缩放，放大后内容不被固定高裁掉，上限取视口高。
    height: AppResponsive.scaled(context, 300).clamp(
      0.0,
      MediaQuery.sizeOf(context).height,
    ),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    decoration: BoxDecoration(
      color: AppDesignTokens.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '观看分布',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.ink,
          ),
        ),
        const SizedBox(height: 18),
        for (final row in rows) ...[
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  row.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppDesignTokens.inkSubtle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xFFF2F2F6)),
                        ),
                        FractionallySizedBox(
                          widthFactor: row.ratio,
                          child: const ColoredBox(
                            color: AppDesignTokens.accentDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${row.value}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    ),
  );
}

/// 观看时段：00–23 时柱状图 + 高峰说明。
class _HourCard extends StatelessWidget {
  const _HourCard({required this.hours, required this.peak});

  final List<int> hours;
  final String peak;

  @override
  Widget build(BuildContext context) {
    var max = 0;
    for (final value in hours) {
      if (value > max) max = value;
    }
    return Container(
      // 基准高随文字缩放，放大后内容不被固定高裁掉，上限取视口高。
      height: AppResponsive.scaled(context, 300).clamp(
        0.0,
        MediaQuery.sizeOf(context).height,
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '观看时段',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            peak,
            style: const TextStyle(
              fontSize: 11,
              color: AppDesignTokens.inkMuted,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < 24; h++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FractionallySizedBox(
                        heightFactor: max == 0
                            ? 0.02
                            : (hours[h] / max).clamp(0.02, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: hours[h] >= max && max > 0
                                ? AppDesignTokens.accentDeep
                                : AppDesignTokens.accent,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadius.xs),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                '0:00',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '6:00',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '12:00',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '18:00',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
              Text(
                '23:00',
                style: TextStyle(fontSize: 10, color: AppDesignTokens.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
