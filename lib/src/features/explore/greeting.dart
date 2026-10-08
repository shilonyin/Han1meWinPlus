import 'dart:math';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// 一天里的问候档位。抄的是 BiliDesk `HomeViewModel.RefreshGreeting` 的五档切法，
/// 连分界点都一样：5 点算早上、11 点算中午、13 点算下午、18 点算晚上，
/// 23:00–04:59 单独归到「夜深了」—— 那会儿说「晚上好」明显不对。
enum GreetingPeriod { morning, noon, afternoon, evening, lateNight }

/// 把 0–23 的小时映射到问候档位。抽成纯函数是为了能直接断言边界，
/// 不必去挂一个 widget 再读文案。
GreetingPeriod greetingPeriodFor(int hour) {
  if (hour >= 5 && hour < 11) return GreetingPeriod.morning;
  if (hour >= 11 && hour < 13) return GreetingPeriod.noon;
  if (hour >= 13 && hour < 18) return GreetingPeriod.afternoon;
  if (hour >= 18 && hour < 23) return GreetingPeriod.evening;
  return GreetingPeriod.lateNight;
}

/// 档位对应的问候文案。l10n 里没有「按枚举取字符串」的入口，
/// 这里的 switch 就是那层映射，加档位时编译器会提醒补齐。
String greetingText(AppLocalizations l10n, GreetingPeriod period) => switch (period) {
  GreetingPeriod.morning => l10n.greetingMorning,
  GreetingPeriod.noon => l10n.greetingNoon,
  GreetingPeriod.afternoon => l10n.greetingAfternoon,
  GreetingPeriod.evening => l10n.greetingEvening,
  GreetingPeriod.lateNight => l10n.greetingLateNight,
};

/// 每档三个颜文字，每次进首页随机挑一个 —— 固定一个会看腻，全随机又会串味
/// （大半夜配个精神抖擞的脸很怪）。同样取自 BiliDesk。
const Map<GreetingPeriod, List<String>> greetingFaces = {
  GreetingPeriod.morning: ['(｡･ω･｡)', '(￣▽￣)', '(๑•̀ㅂ•́)و'],
  GreetingPeriod.noon: ['(￣﹃￣)', '( ˘▽˘)っ', 'ヾ(≧▽≦*)o'],
  GreetingPeriod.afternoon: ['(￣▽￣)~*', '(๑´ㅂ`๑)', 'ヽ(・∀・)ﾉ'],
  GreetingPeriod.evening: ['(￣o￣) . z Z', '(´-ω-`)', '(*/ω＼*)'],
  GreetingPeriod.lateNight: ['(。-ω-)zzz', '( ˘ω˘ )', '(っ˘ω˘ς )'],
};

/// 首页顶部的问候行。
///
/// 为什么是 StatefulWidget 而不是直接算一次：这个 App 是常驻窗口，跨零点不重启
/// 很常见，所以除了挂载时算一次，还要在窗口重新回到前台（`resumed`）时重算 ——
/// 否则睡一夜回来还是昨晚那句「晚上好」。[clock] 只为测试注入时间。
class HomeGreeting extends StatefulWidget {
  const HomeGreeting({super.key, this.clock});

  /// 取当前时间的入口，默认 [DateTime.now]。
  final DateTime Function()? clock;

  @override
  State<HomeGreeting> createState() => _HomeGreetingState();
}

class _HomeGreetingState extends State<HomeGreeting> {
  final _random = Random();

  late GreetingPeriod _period;
  late String _face;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _refresh();
    _lifecycle = AppLifecycleListener(onStateChange: _handleStateChange);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _handleStateChange(AppLifecycleState state) {
    // 只在回到前台时重算：`inactive` 在 Windows 上点一下别的窗口就会来一次，
    // 那时候换颜文字会显得没来由地跳。
    if (state == AppLifecycleState.resumed) {
      setState(_refresh);
    }
  }

  void _refresh() {
    _period = greetingPeriodFor((widget.clock ?? DateTime.now)().hour);
    final faces = greetingFaces[_period]!;
    _face = faces[_random.nextInt(faces.length)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      // 左对齐到网格的 16，和下面的卡片一致；底边留小一点，别把推荐位推下去。
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: greetingText(l10n, _period)),
            // 颜文字单独上强调色：它是装饰，不该抢问候语本身的视觉重量。
            TextSpan(text: '  $_face', style: TextStyle(color: theme.colorScheme.primary)),
          ],
        ),
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}