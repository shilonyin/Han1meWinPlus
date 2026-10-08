// 回归测试：网络设置页「投屏接收端」必须有卡片皮肤。
//
// 这是用户报的那条现象的直接断言 —— 不是组件层复刻，而是**渲染真实页面**
// （NetworkSettingsPage）再检查那一行落在 GlassPanel 子树里。
//
// 之所以要单独一条：组件层的 settings_card_list_test.dart 证明的是通则，
// 而这里证明的是「生产页面确实按通则接上了」—— 有人把投屏那项再包一层
// 别的 builder、或者把它挪出 SettingsCardList，这条就会红。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/features/settings/network_settings_page.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_panel.dart';

class _StubSettings extends SettingsController {
  _StubSettings(this.initial);
  final AppSettings initial;
  @override
  Future<AppSettings> build() async => initial;
}

void main() {
  testWidgets('投屏接收端那一行落在玻璃卡片里，与同页其他条目一致', (tester) async {
    // 页面是 ListView，投屏分组在「常规」那一大段之后。默认 800x600 的测试视口
    // 装不下，ListView 不会构建视口外的条目，断言会扑空 —— 所以先把视口放大。
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => _StubSettings(const AppSettings())),
        ],
        child: MaterialApp(
          theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NetworkSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 投屏条目在纯文本 app 语言下标题取自 l10n.dlnaReceiver；测试环境是英文，
    // 所以按 key 的英文值找，避免把断言绑死在中文字面量上。
    final castTitle = find.text('Cast receiver');
    expect(castTitle, findsOneWidget, reason: '投屏接收端这一行应当渲染出来（Windows/桌面才显示）');

    final inCard = find
        .ancestor(of: castTitle, matching: find.byType(GlassPanel))
        .evaluate()
        .isNotEmpty;
    expect(inCard, isTrue, reason: '这一行必须和其它设置项一样有卡片皮肤，否则就是用户看到的「不统一」');

    // 分组标题与条目标题不能是同一个词（此前两者共用 dlnaReceiver，
    // 因为条目掉出卡片分支、分组标题一起没渲染，重复才没显形）。
    expect(find.text('Cast to Device'), findsOneWidget, reason: '分组标题应当是分类名');

    // 对照：同页「常规」分组里的条目也在卡片里 —— 证明卡片确实是本页常态。
    final siteTitle = find.text('Site');
    expect(siteTitle, findsOneWidget);
    expect(
      find.ancestor(of: siteTitle, matching: find.byType(GlassPanel)).evaluate(),
      isNotEmpty,
      reason: '对照项本身要在卡片里，否则这条测试说明不了问题',
    );
  });
}
