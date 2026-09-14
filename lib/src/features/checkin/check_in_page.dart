import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/check_in.dart';
import 'check_in_controller.dart';

/// 类型对应的表情（与类型 id 一一对应，便于在日历/明细里一眼区分）。
const Map<String, String> _typeEmoji = {'masturbation': '🤜', 'wetDream': '💤', 'sex': '👫', 'oral': '👅', 'other': '❓'};

String _typeLabel(AppLocalizations l10n, String id) => switch (id) {
      'masturbation' => l10n.checkInTypeMasturbation,
      'wetDream' => l10n.checkInTypeWetDream,
      'sex' => l10n.checkInTypeSex,
      'oral' => l10n.checkInTypeOral,
      _ => l10n.other,
    };

/// 「冲了么」：纯本地的每日打卡日历（今日卡 + 月历热力图 + 月度统计）。
class CheckInPage extends ConsumerWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(checkInProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkIn)),
      body: async.when(
        loading: () => const Center(child: M3EContainedLoadingIndicator()),
        error: (error, _) => Center(child: Text(l10n.loadFailed('$error'))),
        data: (state) => LayoutBuilder(
          builder: (context, constraints) {
            // 默认窗口高度有限：日历吃掉剩余空间（每格高度按行数动态算），保证一屏放得下；
            // 窗口极矮时退化成可滚动，不会溢出。
            final scrollable = constraints.maxHeight < 420;
            final content = Column(
              children: [
                _TodayCard(state: state),
                const SizedBox(height: 10),
                if (scrollable) _MonthCalendar(state: state, cellExtent: 46) else Expanded(child: _MonthCalendar(state: state)),
                const SizedBox(height: 10),
                _StatsRow(state: state),
              ],
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: scrollable ? SingleChildScrollView(padding: const EdgeInsets.all(12), child: content) : Padding(padding: const EdgeInsets.all(12), child: content),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 今日打卡卡：显示今天的状态，并提供「打卡」与「清除」。
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final count = state.todayCount;
    final isMaxed = count >= maxCheckInsPerDay;
    return Card(
      color: count > 0 ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l10n.checkInToday} · ${today.month}/${today.day}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(count > 0 ? l10n.checkInTimes(count) : l10n.checkInNotYet, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (count > 0)
              TextButton.icon(
                onPressed: () => ref.read(checkInProvider.notifier).clearDate(today),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.clear),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isMaxed ? null : () => _addCheckIn(context, ref, today),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.checkInNow),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月历热力图：可翻月，每格显示当天次数，颜色随次数加深。
///
/// 默认（[cellExtent] 为空）会填满父级给的剩余高度并据此反推每格高度，
/// 这样在默认窗口尺寸下日历与统计一屏就能放下；传入 [cellExtent] 时按固定高度使用。
class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar({required this.state, this.cellExtent});

  final CheckInState state;
  final double? cellExtent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final month = state.month;
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstDayOfWeek = material.firstDayOfWeekIndex;
    // DateTime.weekday 是 1..7（周一..周日），换算成「周日=0」的下标后再按语言的一周起始偏移。
    final leading = (firstDay.weekday % 7 - firstDayOfWeek + 7) % 7;
    final rows = ((leading + daysInMonth) / 7).ceil();
    final todayKey = checkInDateKey(DateTime.now());

    Widget grid(double extent) {
      final small = extent < 44;
      return GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: cellExtent != null,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: extent, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: leading + daysInMonth,
        itemBuilder: (context, index) {
          if (index < leading) return const SizedBox.shrink();
          final day = DateTime(month.year, month.month, index - leading + 1);
          final count = state.countFor(checkInDateKey(day));
          final isToday = checkInDateKey(day) == todayKey;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openDay(context, ref, day),
            child: Container(
              decoration: BoxDecoration(
                color: count == 0 ? scheme.surfaceContainerHighest.withValues(alpha: 0.4) : scheme.primaryContainer.withValues(alpha: (0.3 + 0.18 * count).clamp(0.3, 0.95)),
                borderRadius: BorderRadius.circular(8),
                border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${day.day}', style: TextStyle(fontSize: small ? 11 : 13, height: 1.1, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
                  if (count > 0) Text('x$count', style: TextStyle(fontSize: small ? 9 : 11, height: 1.1, color: scheme.onPrimaryContainer)),
                ],
              ),
            ),
          );
        },
      );
    }

    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('${month.year} / ${month.month}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => ref.read(checkInProvider.notifier).previousMonth(), visualDensity: VisualDensity.compact, iconSize: 20, icon: const Icon(Icons.chevron_left)),
                IconButton(onPressed: () => ref.read(checkInProvider.notifier).nextMonth(), visualDensity: VisualDensity.compact, iconSize: 20, icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Row(children: [for (var i = 0; i < 7; i++) Expanded(child: Center(child: Text(material.narrowWeekdays[(firstDayOfWeek + i) % 7], style: Theme.of(context).textTheme.labelSmall)))]),
            const SizedBox(height: 4),
            if (cellExtent case final extent?) grid(extent) else Expanded(child: LayoutBuilder(builder: (context, cell) => grid(((cell.maxHeight - 4 * (rows - 1)) / rows).clamp(24.0, 64.0)))),
          ],
        ),
      ),
    );
  }
}

/// 本月统计：打卡天数 / 总次数 / 最佳连续。
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(child: _StatCard(icon: Icons.calendar_month_outlined, value: '${state.monthDays}', label: l10n.checkInMonthDays)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(icon: Icons.repeat_outlined, value: '${state.monthTotal}', label: l10n.checkInMonthTotal)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(icon: Icons.local_fire_department_outlined, value: '${state.bestStreak}', label: l10n.checkInBestStreak)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      );
}

/// 选择类型后写入一条记录（今天或补记某天）。
Future<void> _addCheckIn(BuildContext context, WidgetRef ref, DateTime date) async {
  final l10n = AppLocalizations.of(context)!;
  final type = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.checkInType),
      children: [
        for (final id in checkInTypeIds)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, id),
            child: Row(children: [Text(_typeEmoji[id] ?? ''), const SizedBox(width: 12), Text(_typeLabel(l10n, id))]),
          ),
      ],
    ),
  );
  if (type == null) return;
  await ref.read(checkInProvider.notifier).addFor(date, type);
}

/// 单日详情：明细 + 补记 + 清除。
Future<void> _openDay(BuildContext context, WidgetRef ref, DateTime date) async {
  final l10n = AppLocalizations.of(context)!;
  final state = ref.read(checkInProvider).valueOrNull;
  if (state == null) return;
  final dateKey = checkInDateKey(date);
  final count = state.countFor(dateKey);
  final grouped = <String, int>{};
  for (final record in state.records.where((record) => record.date == dateKey)) {
    grouped[record.type] = (grouped[record.type] ?? 0) + 1;
  }
  final isToday = dateKey == checkInDateKey(DateTime.now());
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isToday ? '${l10n.checkInToday} · ${date.month}/${date.day}' : '${date.month}/${date.day}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count == 0 ? l10n.checkInNotYet : l10n.checkInTimes(count)),
          if (grouped.isNotEmpty) const SizedBox(height: 12),
          for (final entry in grouped.entries) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${_typeEmoji[entry.key] ?? ''} ${_typeLabel(l10n, entry.key)} × ${entry.value}')),
        ],
      ),
      actions: [
        if (count > 0) TextButton(onPressed: () => Navigator.pop(context, 'clear'), child: Text(l10n.clear)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        if (count < maxCheckInsPerDay)
          FilledButton(onPressed: () => Navigator.pop(context, 'add'), child: Text(l10n.checkInNow)),
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
