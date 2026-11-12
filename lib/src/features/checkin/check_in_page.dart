import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
import '../../core/app_design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../domain/models/check_in.dart';
import '../shared/press_scale.dart';
import 'check_in_controller.dart';
import '../../core/app_dialog.dart';
import '../shared/app_top_bar.dart';
import '../shared/fade_slide_in.dart';

/// 类型对应的线性图标。
///
/// 原来这里用 emoji 当图标：和全项目统一的
/// `material_symbols_icons` 混在一套界面里，既不是同一套笔画粗细，也没法
/// 跟随文字颜色。换成一套 18px 的单色线性图标，与设置行、日历里的图标一致。
const Map<String, IconData> _typeIcon = {
  'masturbation': Symbols.front_hand_rounded,
  'wetDream': Symbols.bedtime_rounded,
  'sex': Symbols.group_rounded,
  'oral': Symbols.sentiment_satisfied_rounded,
  'other': Symbols.help_outline_rounded,
};

String _typeLabel(AppLocalizations l10n, String id) => switch (id) {
  'masturbation' => l10n.checkInTypeMasturbation,
  'wetDream' => l10n.checkInTypeWetDream,
  'sex' => l10n.checkInTypeSex,
  'oral' => l10n.checkInTypeOral,
  _ => l10n.other,
};

/// 「冲了么」：纯本地的每日打卡日历（连续签到横幅 + 月历热力图 + 侧栏统计）。
///
/// 视觉按 p_checkin.png 设计稿重做，全部颜色取自 [AppDesignTokens]。
/// 逻辑、数据、路由与原有交互均未改动。
class CheckInPage extends ConsumerWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(checkInProvider);
    return Scaffold(
      // AppBar 主题本身是透明的（页面底色由 AppShell 的 #F4F4F7 提供），
      // 这里沿用同一个 AppBar，标题字号压到设计稿的 19-20 Bold。
      appBar: AppTopBar(
        automaticallyImplyLeading: false,
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '冲了么',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
              TextSpan(
                text: '   每日打卡 · 纯本地记录',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppDesignTokens.inkMutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: M3EContainedLoadingIndicator()),
        error: (error, _) =>
            Center(
          child: Text(
            l10n.loadFailed('$error'),
            style: TextStyle(color: AppDesignTokens.inkSubtleOf(context)),
          ),
        ),
        data: (state) => LayoutBuilder(
          builder: (context, constraints) {
            final viewHeight = MediaQuery.sizeOf(context).height;
            // 单列时日历靠父高度摊开格子，高度随文字缩放，避免放大后格子被压扁。
            // 上限取视口高，窗口变矮时不让单块内容高过一屏。
            final mainHeight = AppResponsive.scaled(context, 620).clamp(0.0, viewHeight);
            final statsHeight = AppResponsive.scaled(context, 600).clamp(0.0, viewHeight);
            // 侧栏基准宽随文字缩放，放大后统计文字不被挤窄。
            // 主区用 Expanded 吃掉剩余，窗口变宽时不会把侧栏一起拉宽。
            final statsWidth = AppResponsive.scaled(context, 300);
            final main = Column(
              children: [
                FadeSlideIn(
                  order: 0,
                  child: _TodayCard(state: state),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  order: 1,
                  child: _MonthCalendar(state: state),
                ),
              ],
            );
            if (constraints.maxWidth < 900) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  children: [
                    SizedBox(height: mainHeight, child: main),
                    const SizedBox(height: 16),
                    SizedBox(height: statsHeight, child: _StatsColumn(state: state)),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: main),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: statsWidth,
                    child: FadeSlideIn(
                      order: 2,
                      child: _StatsColumn(state: state),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 今日打卡条使用浅粉底，与下方白色日历形成两个层级。
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final today = DateTime.now();
    final count = state.todayCount;
    final isMaxed = count >= maxCheckInsPerDay;
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppDesignTokens.accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日 · ${today.month}/${today.day}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.accentDeep,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '今天已打卡 $count 次',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppDesignTokens.accentDeep,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            PressScale(
              child: TextButton(
                onPressed: () =>
                    ref.read(checkInProvider.notifier).clearDate(today),
                child: const Text(
                  '清除',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppDesignTokens.accentDeep,
                  ),
                ),
              ),
            ),
          PressScale(
            child: FilledButton(
              onPressed: isMaxed
                  ? null
                  : () => _addCheckIn(context, ref, today),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.accentDeep,
                foregroundColor: Colors.white,
                minimumSize: const Size(104, 34),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(l10n.checkInNow),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大日历卡片包含月份导航、星期和日期。
/// 日期格铺满七列，打卡次数直接显示在日期下方。
/// 两次及以上使用品红底，一次使用浅粉底。
class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = MaterialLocalizations.of(context);
    final month = state.month;
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstDayOfWeek = material.firstDayOfWeekIndex;
    // DateTime.weekday 是 1..7（周一..周日），换算成「周日=0」的下标后再按语言的一周起始偏移。
    final leading = (firstDay.weekday % 7 - firstDayOfWeek + 7) % 7;
    final rows = ((leading + daysInMonth) / 7).ceil();
    final totalCells = rows * 7;
    final todayKey = checkInDateKey(DateTime.now());

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppDesignTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          children: [
            SizedBox(
              height: 26,
              child: Row(
                children: [
                  Text(
                    '${month.year} / ${month.month.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.inkOf(context),
                    ),
                  ),
                  const Spacer(),
                  _NavIconButton(
                    icon: Symbols.chevron_left_rounded,
                    onTap: () =>
                        ref.read(checkInProvider.notifier).previousMonth(),
                  ),
                  const SizedBox(width: 12),
                  _NavIconButton(
                    icon: Symbols.chevron_right_rounded,
                    onTap: () => ref.read(checkInProvider.notifier).nextMonth(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        material.narrowWeekdays[(firstDayOfWeek + i) % 7],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: i >= 5
                              ? AppDesignTokens.accentDeep
                              : AppDesignTokens.inkSubtleOf(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, cell) => GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: (cell.maxHeight - 12 * (rows - 1)) / rows,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    final day = DateTime(
                      month.year,
                      month.month,
                      index - leading + 1,
                    );
                    final inMonth = day.month == month.month;
                    final count = state.countFor(checkInDateKey(day));
                    final isToday = checkInDateKey(day) == todayKey;
                    final intense = count >= 2 || (isToday && count > 0);
                    final bg = !inMonth
                        ? Colors.transparent
                        : intense
                        ? AppDesignTokens.accentDeep
                        : count == 1
                        ? AppDesignTokens.accent.withValues(alpha: .42)
                        : AppDesignTokens.pageBackgroundOf(context);
                    final fg = !inMonth
                        ? AppDesignTokens.inkMutedOf(context).withValues(alpha: .55)
                        : count > 0
                        ? Colors.white
                        : AppDesignTokens.inkSubtleOf(context);
                    return PressScale(
                      child: Material(
                        color: bg,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => _openDay(context, ref, day),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: fg,
                                ),
                              ),
                              if (count > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'x$count',
                                  style: TextStyle(
                                    fontSize: 9,
                                    height: 1,
                                    color: fg.withValues(alpha: .85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月份箭头只保留图标，与日历标题右对齐。
class _NavIconButton extends StatelessWidget {
  const _NavIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 20,
        height: 28,
        child: Icon(icon, size: 14, color: AppDesignTokens.inkMutedOf(context)),
      ),
    ),
  );
}

/// 右栏统计与图例，数据全部由本地记录派生。
class _StatsColumn extends StatelessWidget {
  const _StatsColumn({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context) {
    final totalDays = state.records.map((r) => r.date).toSet().length;
    final counts = <String, int>{for (final id in checkInTypeIds) id: 0};
    for (final record in state.records.where(
      (r) => r.date.startsWith(state.monthKey),
    )) {
      counts[record.type] = (counts[record.type] ?? 0) + 1;
    }
    final maxType = counts.values.fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        _SideCard(
          title: '本月统计',
          child: Column(
            children: [
              _StatRow(label: '打卡天数', value: '${state.monthDays} 天'),
              const SizedBox(height: 18),
              _StatRow(label: '总次数', value: '${state.monthTotal} 次'),
              const SizedBox(height: 18),
              _StatRow(label: '最佳连续', value: '${state.bestStreak} 天'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SideCard(
          title: '累计',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalDays',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '天 · 全部记录',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppDesignTokens.inkMutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${state.records.length} 次',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.inkOf(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '累计打卡次数',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppDesignTokens.inkMutedOf(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        _SideCard(
          title: '颜色说明',
          child: Column(
            children: [
              _LegendRow(color: AppDesignTokens.accentDeep, label: '打卡 2 次以上'),
              SizedBox(height: 12),
              _LegendRow(color: Color(0xFFC986A1), label: '打卡 1 次'),
              SizedBox(height: 12),
              _LegendRow(
                color: AppDesignTokens.pageBackgroundOf(context),
                label: '未打卡',
                muted: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SideCard(
            title: '本月类型分布',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final id in checkInTypeIds)
                  _TypeDistributionRow(
                    icon: _typeIcon[id] ?? Symbols.help_outline_rounded,
                    label: _typeLabel(AppLocalizations.of(context)!, id),
                    count: counts[id] ?? 0,
                    fraction: (counts[id] ?? 0) / maxType,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
    decoration: BoxDecoration(
      color: AppDesignTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.inkOf(context),
          ),
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 11, color: AppDesignTokens.inkSubtleOf(context)),
      ),
      const Spacer(),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppDesignTokens.accentDeep,
        ),
      ),
    ],
  );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    this.muted = false,
  });

  final Color color;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: muted ? AppDesignTokens.inkMutedOf(context) : AppDesignTokens.inkSubtleOf(context),
        ),
      ),
    ],
  );
}

class _TypeDistributionRow extends StatelessWidget {
  const _TypeDistributionRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.fraction,
  });

  final IconData icon;
  final String label;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppDesignTokens.inkMutedOf(context)),
      const SizedBox(width: 10),
      SizedBox(
        width: 44,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: AppDesignTokens.inkSubtleOf(context),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: count == 0 ? 0 : fraction,
            minHeight: 7,
            backgroundColor: AppDesignTokens.fieldFillOf(context),
            valueColor: const AlwaysStoppedAnimation(
              AppDesignTokens.accentDeep,
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        '$count 次',
        style: const TextStyle(fontSize: 12, color: AppDesignTokens.accentDeep),
      ),
    ],
  );
}

/// 选择类型后写入一条记录（今天或补记某天）。
Future<void> _addCheckIn(
  BuildContext context,
  WidgetRef ref,
  DateTime date,
) async {
  final l10n = AppLocalizations.of(context)!;
  final type = await showAppDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.checkInType),
      children: [
        for (final id in checkInTypeIds)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, id),
            child: Row(
              children: [
                Icon(
                  _typeIcon[id] ?? Symbols.help_outline_rounded,
                  size: 18,
                  color: AppDesignTokens.inkSubtleOf(context),
                ),
                const SizedBox(width: 12),
                Text(_typeLabel(l10n, id)),
              ],
            ),
          ),
      ],
    ),
  );
  if (type == null) return;
  await ref.read(checkInProvider.notifier).addFor(date, type);
}

/// 单日详情：明细 + 补记 + 清除。
Future<void> _openDay(
  BuildContext context,
  WidgetRef ref,
  DateTime date,
) async {
  final l10n = AppLocalizations.of(context)!;
  final state = ref.read(checkInProvider).valueOrNull;
  if (state == null) return;
  final dateKey = checkInDateKey(date);
  final count = state.countFor(dateKey);
  final grouped = <String, int>{};
  for (final record in state.records.where(
    (record) => record.date == dateKey,
  )) {
    grouped[record.type] = (grouped[record.type] ?? 0) + 1;
  }
  final isToday = dateKey == checkInDateKey(DateTime.now());
  final action = await showAppDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        isToday
            ? '${l10n.checkInToday} · ${date.month}/${date.day}'
            : '${date.month}/${date.day}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count == 0 ? l10n.checkInNotYet : l10n.checkInTimes(count)),
          if (grouped.isNotEmpty) const SizedBox(height: 12),
          for (final entry in grouped.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _typeIcon[entry.key] ?? Symbols.help_outline_rounded,
                    size: 16,
                    color: AppDesignTokens.inkSubtleOf(context),
                  ),
                  const SizedBox(width: 8),
                  Text('${_typeLabel(l10n, entry.key)} × ${entry.value}'),
                ],
              ),
            ),
        ],
      ),
      actions: [
        if (count > 0)
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context, 'clear'),
              child: Text(l10n.clear),
            ),
          ),
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        if (count < maxCheckInsPerDay)
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, 'add'),
              child: Text(l10n.checkInNow),
            ),
          ),
      ],
    ),
  );
  if (action == 'add') {
    if (!context.mounted) return;
    await _addCheckIn(context, ref, date);
  } else if (action == 'clear') {
    await ref.read(checkInProvider.notifier).clearDate(date);
  }
}
