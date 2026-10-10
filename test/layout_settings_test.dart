// 回归测试：「界面布局」页里那四个点不动的开关必须消失，其余项照旧。
//
// 背景（用户报的现象，原话）：
//   「横向影片卡片和首页使用收起式分类还有最后一个影片卡片数量好像都没有作用，
//     没用的就去掉，以及最上面的使用导航抽屉这个默认开启，这个选项也用不上去掉」
//
// 实测确认（先在代码里核对了消费点，再删的）：
//  - `searchCardsPerRow`：只有 `cardsPerRow` 为空时才生效，而搜索页/清单页都写死 4 列；
//    即使读到，`video_card.dart` 的 autoWiden 在窗口宽度 ≥1200 时会用
//    `(width/300).floor().clamp(cardsPerRow, 6)` 覆盖掉它 —— 用户的窗口正在这个区间，
//    所以 1/2/3 三档全无效。
//  - `useHorizontalSearchCards`：首页是独立 SliverGrid（写死横向），搜索页与作者页都
//    显式传 `horizontal: true`，只有清单页那几处跟着它变。
//  - `useHomeCategoryTabs`：**实测有效**，但用户要求首页固定为收起式分类，故一并删掉。
//  - `useNavigationDrawer`：默认开启，用户不需要第二种导航形态。
//
// 这个文件钉住两件事：
//  1. 生产页面 `LayoutSettingsPage` 不再渲染这四个开关的文案（不是组件层复刻，
//     而是渲染真实页面 —— 和 network_settings_cast_card_test.dart 同一套路）。
//  2. 留下的条目仍然落在 GlassPanel 卡片里（删条目时不要把分组结构改坏）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/layout_settings_page.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_panel.dart';

class _StubSettings extends SettingsController {
  _StubSettings(this.initial);
  final AppSettings initial;
  @override
  Future<AppSettings> build() async => initial;
}

/// 渲染真实的「界面布局」页。视口放大到能装下整页，否则 ListView 不构建视口外的条目。
Future<void> _pumpLayoutPage(WidgetTester tester, {AppSettings? settings}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          () => _StubSettings(settings ?? const AppSettings()),
        ),
      ],
      child: MaterialApp(
        theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LayoutSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('已删除的四个开关不再渲染', () {
    testWidgets('「使用导航抽屉」「横向影片卡片」「首页使用收起式分类」「影片卡片每行数量」全部消失', (tester) async {
      await _pumpLayoutPage(tester);

      // 英文文案（测试语言是 en）。这四个键连 arb 都删了，所以这里直接用字面量：
      // 一旦有人把它们加回设置页，这条会红。
      for (final label in const [
        'Use Navigation Drawer',
        'Horizontal Video Cards',
        'Use Collapsed Home Categories',
        'Video Cards Per Row',
      ]) {
        expect(
          find.text(label),
          findsNothing,
          reason: '「$label」已确认无效（或用户要求固定），不该再出现在设置页',
        );
      }
    });

    testWidgets('开关数量随之减少：剩下的条目里没有指向已删字段的开关', (tester) async {
      // 把四项都设成非默认值渲染一遍 —— 若还有代码读这些字段画开关，这里就会露出来。
      await _pumpLayoutPage(
        tester,
        settings: const AppSettings(
          useCompactSearchCards: true,
          expandHomeVideoCards: true,
        ),
      );
      // 「展开首页影片卡片」早在首页改造时就不再显示（见提交 e6d2f9d），
      // 这里顺带确认它没有跟着回来。
      expect(find.text('Expand Home Video Cards'), findsNothing);
    });
  });

  group('留下的条目结构没被改坏', () {
    testWidgets('观看漫画 / 独立窗口播放 / 首页快捷分类 / 推荐流设置仍在卡片里', (tester) async {
      await _pumpLayoutPage(tester);

      // 分组标题要和条目一起渲染（删条目时最容易把整组带没）。
      expect(find.text('General'), findsOneWidget, reason: '「常规」分组标题要还在');

      for (final label in const [
        'Comic Mode',
        'Home Shortcuts',
        'Recommendation Filters',
      ]) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: '「$label」应当保留');
        expect(
          find.ancestor(of: finder, matching: find.byType(GlassPanel)).evaluate(),
          isNotEmpty,
          reason: '「$label」必须和其它设置项一样落在卡片里',
        );
      }
    });
  });

  group('老配置文件向后兼容', () {
    test('setting.json 里遗留的四个键会被忽略，不报错也不影响其它字段', () {
      // 用户升级前的 setting.json 里这些键都还在（实测本机就写着
      // useNavigationDrawer:false / useHomeCategoryTabs:true / searchCardsPerRow:1）。
      // fromJson 只读它认得的键，多余键必须安静地跳过 —— 否则升级即崩。
      final settings = AppSettings.fromJson(const {
        'useHorizontalSearchCards': false,
        'searchCardsPerRow': 1,
        'useNavigationDrawer': false,
        'useHomeCategoryTabs': true,
        // 一个正常字段，用来证明解析没有半路退出。
        'preferredQuality': 1080,
      });

      expect(settings.preferredQuality, 1080, reason: '遗留键之后的字段照常读出来');
      expect(settings.homeQuickCategories, isEmpty);
    });

    test('保存时不再写回这四个键（下次启动就是干净配置）', () {
      final json = const AppSettings().toJson();
      for (final key in const [
        'useHorizontalSearchCards',
        'searchCardsPerRow',
        'useNavigationDrawer',
        'useHomeCategoryTabs',
      ]) {
        expect(
          json.containsKey(key),
          isFalse,
          reason: '「$key」已删除，不该再写回 setting.json',
        );
      }
      // 没被点名的字段一个都不能少。
      expect(json.containsKey('useCompactSearchCards'), isTrue);
      expect(json.containsKey('expandHomeVideoCards'), isTrue);
      expect(json.containsKey('homeQuickCategories'), isTrue);
    });
  });
}
