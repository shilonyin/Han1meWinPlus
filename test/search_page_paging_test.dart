// 回归测试：搜索页的「翻页」是瀑布流式的往下接，而不是换掉整屏。
//
// 背景：结果区原先底部挂着一根分页条（`1 / 73` + 左右箭头），点一次换一屏；结果
// 列表本来就是滚动的，滚到底还得回头去点箭头。现在改成滚到底自动接下一页，分页条
// 整个删掉。这里守两件事：
//   1. 首屏之外多出来的页是**追加**在后面的（前面的卡片还在原位，不跳不回顶）；
//   2. 已经翻到最后一页时不再继续请求（否则滚到底会一直打站点）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/data/assets/search_option_catalog.dart';
import 'package:han1me_win_plus/src/data/local/json_store.dart';
import 'package:han1me_win_plus/src/data/local/video_meta_cache.dart';
import 'package:han1me_win_plus/src/data/han1me_repository.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_api.dart' show Han1meApi, SearchResult;
import 'package:han1me_win_plus/src/data/remote/han1me_http_client.dart';
import 'package:han1me_win_plus/src/data/remote/jav/jav_api.dart';
import 'package:han1me_win_plus/src/domain/models/search_query.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/search/search_page.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/shared/video_card.dart';

/// 固定返回一份设置（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// 只覆写 [`Han1meRepository.search`] 的替身：分页逻辑之外的部分（详情页补全等）
/// 在测试里也用不到，所以内部那两个 API 用默认实现凑上即可，永远不会被调用。
class _StubRepository extends Han1meRepository {
  _StubRepository(this.onSearch) : super(Han1meApi(Han1meHttpClient()), JavApi(Han1meHttpClient()));

  final Future<SearchResult> Function(int page) onSearch;

  @override
  Future<SearchResult> search({
    required String baseUrl,
    required String query,
    required String genre,
    required String sort,
    required String date,
    required String duration,
    required List<String> tags,
    required bool broad,
    required String type,
    required int page,
  }) => onSearch(page);
}

VideoCard _card(String id, String title) => VideoCard(id: id, title: title, coverUrl: '');

SearchOptionCatalog _catalog() => SearchOptionCatalog(
  genres: SearchOptionGroup(const [
    SearchOption(labels: {'zh-rCN': '全部'}, searchKey: null),
    SearchOption(labels: {'zh-rCN': '里番', 'zh-rTW': '裏番', 'en': 'Hentai'}, searchKey: '裏番'),
    SearchOption(labels: {'zh-rCN': '泡面番', 'zh-rTW': '泡麵番', 'en': 'Short Anime'}, searchKey: '泡麵番'),
    SearchOption(labels: {'zh-rCN': '3D动画', 'zh-rTW': '3D動畫'}, searchKey: '3DCG'),
  ]),
  sorts: SearchOptionGroup(const []),
  durations: SearchOptionGroup(const []),
  releaseDates: SearchOptionGroup(const []),
  tags: const {},
);

void main() {
  late SearchRouteRequest request;
  late ProviderContainer container;
  late List<int> requestedPages;

  /// 站点给两页内容（第 1 页 `a/b`，之后都是 `c/d`），够拿来观察「接页」行为。
  Future<SearchResult> fakeSearch(int page) async {
    requestedPages.add(page);
    final items = page <= 1 ? [_card('a', '第一页甲'), _card('b', '第一页乙')] : [_card('c', '第二页甲'), _card('d', '第二页乙')];
    return SearchResult(items: items, page: page.clamp(1, 2), totalPages: 2);
  }

  Future<void> pump(WidgetTester tester, {String genre = ''}) async {
    request = SearchRouteRequest(initialQuery: SearchQuery(text: '少女', genre: genre));
    requestedPages = [];
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _StubSettings(AppSettings())),
        searchOptionCatalogProvider.overrideWith((ref) async => _catalog()),
        // 两条搜索 provider 都走真实实现，只把仓库层换成替身 —— 这样「首屏 + 往下
        // 接页」整条链路都被测到（含页码推进、追加合并、到最后一页就停）。
        han1meRepositoryProvider.overrideWithValue(_StubRepository(fakeSearch)),
        videoMetaCacheProvider.overrideWithValue(VideoMetaCache(_MemoryStore())),
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

  testWidgets('滚到底自动接下一页，第一页的卡片留在原位', (tester) async {
    await pump(tester);
    // 首屏两张卡。
    expect(find.text('第一页甲'), findsOneWidget);

    // 第 2 张卡被建出来（进入缓存区）时会去要下一页 —— 内容不够长、没得滚也一样。
    await tester.pumpAndSettle();

    // 探针确实去要了第 2 页。
    expect(requestedPages, contains(2));

    // 新页是追加的：第一页的卡片没有被换掉。
    final grid = tester.widget<VideoCardGrid>(find.byType(VideoCardGrid));
    expect(grid.videos.map((video) => video.id), ['a', 'b', 'c', 'd']);
  });

  testWidgets('滚到最后一页后不再继续请求', (tester) async {
    await pump(tester);
    // 反复滚到底：第 2 页拿到之后 `totalPages` 已经到顶，探针不该再发请求。
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(GridView), const Offset(0, -1200));
      await tester.pumpAndSettle();
    }
    expect(requestedPages.where((page) => page > 2), isEmpty);
  });

  /// 里番 / 泡麵番：竖版海报排版（一排六个、封面按 3:4 留高，整张封面可见）。
  testWidgets('里番 走海报排版：一排六个、封面按 3:4', (tester) async {
    await pump(tester, genre: '裏番');
    final grid = tester.widget<VideoCardGrid>(find.byType(VideoCardGrid));
    expect(grid.cardsPerRow, 6);
    expect(grid.coverAspectRatio, closeTo(3 / 4, 1e-9));
  });

  testWidgets('泡麵番 走海报排版：一排六个、封面按 3:4', (tester) async {
    await pump(tester, genre: '泡麵番');
    final grid = tester.widget<VideoCardGrid>(find.byType(VideoCardGrid));
    expect(grid.cardsPerRow, 6);
    expect(grid.coverAspectRatio, closeTo(3 / 4, 1e-9));
  });

  /// 界面文案也要能匹配上：不同语言下这一项显示的是「里番 / 裏番 / Hentai」，
  /// 落到 `query.genre` 的都可能是文案而不是站点键，归一之后必须仍然判成海报排版。
  testWidgets('分类文案「里番」也能归一到海报排版', (tester) async {
    await pump(tester, genre: '里番');
    final grid = tester.widget<VideoCardGrid>(find.byType(VideoCardGrid));
    expect(grid.cardsPerRow, 6);
    expect(grid.coverAspectRatio, closeTo(3 / 4, 1e-9));
  });

  /// 其他分类维持原样：一排四个 + 16:9。
  testWidgets('其他分类不变：一排四个、封面仍按 16:9', (tester) async {
    await pump(tester, genre: '3DCG');
    final grid = tester.widget<VideoCardGrid>(find.byType(VideoCardGrid));
    expect(grid.cardsPerRow, 4);
    expect(grid.coverAspectRatio, isNull);
  });

  testWidgets('全部（未选分类）也不变：一排四个、封面仍按 16:9', (tester) async {
    await pump(tester);
    final grid = tester.widget<VideoCardGrid>(find.byType(VideoCardGrid));
    expect(grid.cardsPerRow, 4);
    expect(grid.coverAspectRatio, isNull);
  });
}

/// 内存版存储：测试里不需要落盘。
class _MemoryStore extends JsonStore {
  final _data = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>> read(String fileName) async => _data[fileName] ?? const {};

  @override
  Future<void> write(String fileName, Map<String, dynamic> value) async => _data[fileName] = value;
}
