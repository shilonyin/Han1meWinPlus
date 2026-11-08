import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../domain/models/check_in.dart';
import '../shared/press_scale.dart';
import 'check_in_controller.dart';
import '../../core/app_dialog.dart';
import '../shared/app_top_bar.dart';

/// 类型对应的表情（与类型 id 一一对应，便于在日历/明细里一眼区分）。
const Map<String, String> _typeEmoji = {
  'masturbation': '🤜',
  'wetDream': '💤',
  'sex': '👫',
  'oral': '👅',
  'other': '❓',
};

String _typeLabel(AppLocalizations l10n, String id) => switch (id) {
  'masturbation' => l10n.checkInTypeMasturbation,
  'wetDream' => l10n.checkInTypeWetDream,
  'sex' => l10n.checkInTypeSex,
  'oral' => l10n.checkInTypeOral,
  _ => l10n.other,
};

/// 文字灰只有三档（ink / inkSubtle / inkMuted），这里集中成两条快捷样式，
/// 避免各处再随手写第四种灰。
const TextStyle _tSubtle = TextStyle(color: AppDesignTokens.inkSubtle);

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
        title: Text(
          l10n.checkIn,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.ink,
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: M3EContainedLoadingIndicator()),
        error: (error, _) =>
            Center(child: Text(l10n.loadFailed('$error'), style: _tSubtle)),
        data: (state) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          // 设计稿是**单列**：横幅 → 月历，日历占满内容宽度。
          //
          // 原来是「左栏日历 + 右栏 30x0 的统计卡」两栏，日历被挤窄、统计卡又孤零零
          // 挂在右边。设计稿把三个统计数字直接放进横幅右侧（12 天 / 86 天 / 486），
          // 下面是通栏的月历 —— 视觉重心集中在打卡这件事上。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroBanner(state: state),
              const SizedBox(height: 16),
              _MonthCalendar(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部连续签到横幅：品红渐变底 + 左侧「连续签到 N 天」+ 右侧三列统计 + 「今日已签到」按钮。
class _HeroBanner extends ConsumerWidget {
  const _HeroBanner({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final today = DateTime.now();
    final count = state.todayCount;
    final isMaxed = count >= maxCheckInsPerDay;
    final streak = _currentStreak(state);
    final daysInMonth = DateTime(
      state.month.year,
      state.month.month + 1,
      0,
    ).day;
    // 积分只是给横幅加点设计稿的味道：一条记录 5 分，纯展示、不落库。
    final points = state.monthTotal * 5;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppDesignTokens.accentDeep, AppDesignTokens.accent],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '连续签到 $streak 天',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '本月已签到 ${state.monthDays} / $daysInMonth 天，继续保持',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroStat(value: '$streak', unit: '天', label: '连续'),
                  _HeroStat(
                    value: '${state.monthTotal}',
                    unit: '天',
                    label: '累计',
                  ),
                  _HeroStat(value: '$points', unit: '', label: '积分'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (count > 0)
                PressScale(
                  child: _HeroGhostButton(
                    icon: Symbols.delete_rounded,
                    label: l10n.clear,
                    onTap: () =>
                        ref.read(checkInProvider.notifier).clearDate(today),
                  ),
                )
              else
                PressScale(
                  child: _HeroButton(
                    icon: Symbols.check_rounded,
                    label: l10n.checkInNow,
                    enabled: !isMaxed,
                    onTap: () => _addCheckIn(context, ref, today),
                  ),
                ),
              if (count > 0) ...[
                const SizedBox(width: 12),
                PressScale(
                  child: _HeroButton(
                    icon: Symbols.add_rounded,
                    label: l10n.checkInNow,
                    enabled: !isMaxed,
                    onTap: () => _addCheckIn(context, ref, today),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    '今日获得 ${count * 5} 积分 · 累计 $points',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ] else
                const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }
}

/// 横幅上的「连续签到」——本月最早的连续段长度（纯展示用，不改任何数据）。
int _currentStreak(CheckInState state) {
  final days =
      state.records
          .where((r) => r.date.startsWith(state.monthKey))
          .map((r) => r.date)
          .toSet()
          .map(DateTime.parse)
          .toList()
        ..sort();
  var best = 0;
  var streak = 0;
  DateTime? previous;
  for (final day in days) {
    streak = previous != null && day.difference(previous).inDays == 1
        ? streak + 1
        : 1;
    if (streak > best) best = streak;
    previous = day;
  }
  return best;
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.unit,
    required this.label,
  });

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    ),
  );
}

/// 横幅主按钮：白底品红字（设计稿「今日已签到」那枚白药丸）。
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.5,
    child: Material(
      color: AppDesignTokens.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: AppDesignTokens.accentDeep),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.accentDeep,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 横幅次的透明描边按钮（清除用），白字白框压在品红底上。
class _HeroGhostButton extends StatelessWidget {
  const _HeroGhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: StadiumBorder(
      side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
    ),
    child: PressScale(
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 月历热力图：可翻月，每格显示当天次数，颜色随次数加深。
///
/// 设计稿：白卡 + 圆角16，格子里「日期数字 + 小对勾」，已打卡的格子浅粉填充、
/// 今天用 accentDeep 实色底 + 白字。默认按父级剩余高度自动推格子高度，跟随窗口一屏放下。
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
    final todayKey = checkInDateKey(DateTime.now());

    Widget grid(double extent) {
      final small = extent < 44;
      return GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: extent,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: leading + daysInMonth,
        itemBuilder: (context, index) {
          if (index < leading) return const SizedBox.shrink();
          final day = DateTime(month.year, month.month, index - leading + 1);
          final count = state.countFor(checkInDateKey(day));
          final isToday = checkInDateKey(day) == todayKey;
          final done = count > 0;
          // 三档底色：今天 = accentDeep 实色；已打卡 = 极淡粉；未打卡 = 透明（白卡上留白）。
          final Color bg;
          final Color fg;
          final Color subFg;
          if (isToday) {
            bg = AppDesignTokens.accentDeep;
            fg = Colors.white;
            subFg = Colors.white.withValues(alpha: 0.9);
          } else if (done) {
            bg = AppDesignTokens.accent.withValues(alpha: 0.12);
            fg = AppDesignTokens.accentDeep;
            subFg = AppDesignTokens.accent;
          } else {
            bg = Colors.transparent;
            fg = AppDesignTokens.ink;
            subFg = AppDesignTokens.inkMuted;
          }
          return PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _openDay(context, ref, day),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: small ? 12 : 13.5,
                        height: 1.15,
                        fontWeight: isToday || done
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (done)
                      Icon(
                        Symbols.check_rounded,
                        size: small ? 9 : 11,
                        color: subFg,
                      )
                    else
                      SizedBox(height: small ? 9 : 11),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            // 月标题行：左边「年月 + 已签天数」，右边翻月按钮。
            Row(
              children: [
                Text(
                  '${month.year} 年 ${month.month} 月',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$daysInMonth 天 / 已签 ${state.monthDays} 天',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkMuted,
                  ),
                ),
                const Spacer(),
                _NavIconButton(
                  icon: Symbols.chevron_left_rounded,
                  onTap: () =>
                      ref.read(checkInProvider.notifier).previousMonth(),
                ),
                const SizedBox(width: 6),
                _NavIconButton(
                  icon: Symbols.chevron_right_rounded,
                  onTap: () => ref.read(checkInProvider.notifier).nextMonth(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        material.narrowWeekdays[(firstDayOfWeek + i) % 7],
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.inkMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, cell) => grid(
                  ((cell.maxHeight - 6 * (rows - 1)) / rows).clamp(24.0, 64.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日历翻月的圆形小按钮：浅灰底 + 灰字，和设计稿右侧那两枚一致。
class _NavIconButton extends StatelessWidget {
  const _NavIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppDesignTokens.pageBackground,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 18, color: AppDesignTokens.inkSubtle),
        ),
      ),
    ),
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
                Text(_typeEmoji[id] ?? ''),
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
              child: Text(
                '${_typeEmoji[entry.key] ?? ''} ${_typeLabel(l10n, entry.key)} × ${entry.value}',
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
