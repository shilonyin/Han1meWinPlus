import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/features/explore/greeting.dart';

/// 包一层最小 MaterialApp：问候语要读 `AppLocalizations` 和 `Theme`。
Widget _host(Widget child, {Locale locale = const Locale('zh')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('greetingPeriodFor 分档边界', () {
    test('五档的分界点', () {
      expect(greetingPeriodFor(5), GreetingPeriod.morning);
      expect(greetingPeriodFor(10), GreetingPeriod.morning);
      expect(greetingPeriodFor(11), GreetingPeriod.noon);
      expect(greetingPeriodFor(12), GreetingPeriod.noon);
      expect(greetingPeriodFor(13), GreetingPeriod.afternoon);
      expect(greetingPeriodFor(17), GreetingPeriod.afternoon);
      expect(greetingPeriodFor(18), GreetingPeriod.evening);
      expect(greetingPeriodFor(22), GreetingPeriod.evening);
      expect(greetingPeriodFor(23), GreetingPeriod.lateNight);
    });

    test('凌晨整段都归到夜深了', () {
      expect(greetingPeriodFor(0), GreetingPeriod.lateNight);
      expect(greetingPeriodFor(1), GreetingPeriod.lateNight);
      expect(greetingPeriodFor(4), GreetingPeriod.lateNight);
    });
  });

  group('greetingText 三语文案', () {
    test('简体', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(greetingText(l10n, GreetingPeriod.morning), '早上好');
      expect(greetingText(l10n, GreetingPeriod.noon), '中午好');
      expect(greetingText(l10n, GreetingPeriod.afternoon), '下午好');
      expect(greetingText(l10n, GreetingPeriod.evening), '晚上好');
      expect(greetingText(l10n, GreetingPeriod.lateNight), '夜深了');
    });

    test('繁中', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh', 'TW'));
      expect(greetingText(l10n, GreetingPeriod.morning), '早安');
      expect(greetingText(l10n, GreetingPeriod.noon), '午安');
      expect(greetingText(l10n, GreetingPeriod.lateNight), '夜深了');
    });

    test('英文', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(greetingText(l10n, GreetingPeriod.morning), 'Good morning');
      expect(greetingText(l10n, GreetingPeriod.lateNight), 'Still up?');
    });
  });

  group('每档都有颜文字', () {
    test('每档三个且互不相同', () {
      for (final period in GreetingPeriod.values) {
        final faces = greetingFaces[period];
        expect(faces, isNotNull, reason: '$period 缺颜文字');
        expect(faces!.length, 3);
        expect(faces.toSet().length, 3, reason: '$period 颜文字重复');
      }
    });
  });

  group('HomeGreeting', () {
    testWidgets('按注入的时间显示对应问候语和颜文字', (tester) async {
      await tester.pumpWidget(
        _host(HomeGreeting(clock: () => DateTime(2026, 10, 8, 7))),
      );
      final text = tester.widget<RichText>(find.byType(RichText).last);
      final rendered = text.text.toPlainText();
      expect(rendered, contains('早上好'));
      // 颜文字是装饰，挂在同一个 TextSpan 里，跟着主色走。
      expect(
        greetingFaces[GreetingPeriod.morning]!.any(rendered.contains),
        isTrue,
        reason: '没渲染出本档的颜文字：$rendered',
      );
    });

    testWidgets('回到前台后重算：早上挂载，晚上唤醒要改成晚上好', (tester) async {
      var now = DateTime(2026, 10, 8, 7);
      await tester.pumpWidget(_host(HomeGreeting(clock: () => now)));
      expect(
        tester.widget<RichText>(find.byType(RichText).last).text.toPlainText(),
        contains('早上好'),
      );

      now = DateTime(2026, 10, 8, 20);
      // 从非 resumed 起步，避免被 AppLifecycleListener 的同态去重吃掉。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(
        tester.widget<RichText>(find.byType(RichText).last).text.toPlainText(),
        contains('晚上好'),
      );
    });
  });
}