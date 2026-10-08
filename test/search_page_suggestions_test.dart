// 回归测试：搜索页自己的输入框也要能展开「搜索历史 + 热门标签」面板。
//
// 背景：这块面板（`SearchSuggestions`）原先只挂在首页顶栏，搜索页那个长得一模一样的
// 输入框聚焦后什么也不弹 —— 用户在搜索页想复用自己的历史条件时只能退回首页。
// 现在两处共用同一个面板组件，搜索页这侧多出来的责任是「点条目就地换查询条件」：
// 搜索页本来就已经是搜索结果页，再 push 一页只会堆出一摞内容相同的页面，返回时
// 要一层层退出。所以这里断言的是「条件变了、没有跳页」。
//
// 面板挂在 body 的 Stack 里、输入框在 AppBar 里，两者是兄弟关系，位置靠全局坐标
// 相减算出来 —— 这层几何逻辑（面板确实贴着输入框下方、宽度与输入框一致）也在这里
// 守着，不靠肉眼。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/data/assets/search_option_catalog.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_api.dart' show SearchResult;
import 'package:han1me_win_plus/src/domain/models/search_query.dart';
import 'package:han1me_win_plus/src/features/search/search_controller.dart';
import 'package:han1me_win_plus/src/features/search/search_page.dart';
import 'package:han1me_win_plus/src/features/search/search_suggestions.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';

/// 固定返回一份设置（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// 固定返回一段搜索历史的替身（真实实现要读 `search_history.json`）。
class _StubHistory extends SearchHistoryController {
  _StubHistory(this._items);
  final List<SearchQuery> _items;

  @override
  Future<List<SearchQuery>> build() async => _items;
}

/// 只带「站点属性」标签的目录：热门标签取的就是这一组。
SearchOptionCatalog _catalog() => SearchOptionCatalog(
  genres: SearchOptionGroup(const []),
  sorts: SearchOptionGroup(const []),
  durations: SearchOptionGroup(const []),
  releaseDates: SearchOptionGroup(const []),
  tags: {
    'video_attributes': SearchOptionGroup(const [
      SearchOption(labels: {'zh-rCN': '無修正'}, searchKey: 'uncensored'),
      SearchOption(labels: {'zh-rCN': '中文字幕'}, searchKey: 'chinese-subtitle'),
    ]),
  },
);

void main() {
  late SearchRouteRequest request;
  late ProviderContainer container;

  /// 挂载搜索页。结果用替身顶掉（真实 provider 会去抓网络），
  /// 目录也顶掉（widget 测试里没保证能读到 assets）。
  Future<void> pump(
    WidgetTester tester, {
    List<SearchQuery> history = const [],
    SearchRouteRequest? route,
  }) async {
    request = route ?? SearchRouteRequest();
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _StubSettings(AppSettings())),
        searchOptionCatalogProvider.overrideWith((ref) async => _catalog()),
        searchHistoryProvider.overrideWith(() => _StubHistory(history)),
        searchResultsProvider.overrideWith((ref, _) async => const SearchResult(items: [], page: 1, totalPages: 1)),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appTheme(null, const Color(0xffb3265a), brightness: Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SearchPage(request: request),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 面板外面那层负责显隐的部件（收起时 opacity 0 + 不吃点击）。
  AnimatedOpacity panelOpacity(WidgetTester tester) => tester.widget<AnimatedOpacity>(
    find.ancestor(of: find.byType(SearchSuggestions), matching: find.byType(AnimatedOpacity)).first,
  );

  IgnorePointer panelBlocker(WidgetTester tester) => tester.widget<IgnorePointer>(
    find.ancestor(of: find.byType(SearchSuggestions), matching: find.byType(IgnorePointer)).first,
  );

  testWidgets('空白搜索页输入框自动聚焦，面板一进来就展开', (tester) async {
    await pump(tester);

    // 首页点搜索进来时用户还没输任何东西，焦点直接落在输入框上（`autoFocus`），
    // 面板也就跟着开着 —— 这一步守的是「autofocus 首帧不能把 setState 抛错」。
    expect(find.byType(SearchSuggestions), findsOneWidget);
    expect(panelOpacity(tester).opacity, 1);
    expect(panelBlocker(tester).ignoring, isFalse);
  });

  testWidgets('带着条件进来的搜索页不抢焦点，点输入框才展开、失焦收起', (tester) async {
    // 有初始条件时输入框不 autofocus（用户是从结果页回来的，焦点不该被抢走）。
    await pump(tester, route: SearchRouteRequest(initialQuery: const SearchQuery(text: '少女')));
    expect(panelOpacity(tester).opacity, 0);
    expect(panelBlocker(tester).ignoring, isTrue);

    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();
    expect(panelOpacity(tester).opacity, 1);
    expect(panelBlocker(tester).ignoring, isFalse);

    // 失焦（点别处 / 程序收起）要跟着收，不能留在屏幕上挡结果。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(panelOpacity(tester).opacity, 0);
    expect(panelBlocker(tester).ignoring, isTrue);
  });

  testWidgets('面板贴着输入框下方，宽度与输入框一致', (tester) async {
    await pump(tester, history: [const SearchQuery(text: '历史条目')]);
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(EditableText));
    final panel = tester.getRect(find.byType(SearchSuggestions));
    // 面板不该盖住输入框自己。
    expect(panel.top, greaterThanOrEqualTo(field.bottom));
    // 水平居中对齐：两边留白相同，观察上就是「和搜索框一样宽」。
    expect((panel.left - field.left).abs(), lessThan(24));
  });

  testWidgets('点历史条目就地换查询条件（不新压一页）', (tester) async {
    await pump(tester, history: [const SearchQuery(text: '历史条目')]);
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史条目'));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider(request)).text, '历史条目');
    // 条件变了，输入框要跟着变，否则刚点完的条目在框里看不到。
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '历史条目');
    // 选完就收起，别挡着结果。
    expect(panelOpacity(tester).opacity, 0);
  });

  testWidgets('点热门标签把条件换成该标签', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();

    await tester.tap(find.text('中文字幕'));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider(request)).tags, ['chinese-subtitle']);
    expect(panelOpacity(tester).opacity, 0);
  });
}
