import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../domain/models/video.dart';
import '../han1me_api.dart';
import '../han1me_http_client.dart';
import '../webview_page_fetcher.dart';
import 'dean_edwards.dart';
import 'jav_site.dart';
import 'xhamster_cipher.dart';

/// AV 视频源（JAV 站点）的解析实现。
///
/// 各站点的页面结构互不相同，但形状一致：「列表页 → 卡片」「详情页 → 元数据 +
/// 播放地址」。所以差异收在少数几个按 [JavSiteKind] 分支的函数里
/// （[_itemSelector] / [_card] / [_detail] / [_sources]），其余部分（分页地址、
/// 翻页、清晰度整理）都是共用的。
///
/// 注意：这些站点**没有** hanime1 那套账号/评论接口，调用方（`Han1meRepository`）
/// 会对 AV 源屏蔽掉那些能力。
class JavApi {
  JavApi(this._http, [this._webView]);

  final Han1meHttpClient _http;

  /// 真实 Chromium（WebView2）代取页面的兼容层，见 [WebViewPageFetcher]。
  ///
  /// 部分站点的 Cloudflare 是按 TLS 指纹拦 Dart 的，这个兜底在 Dart 被拦时换成
  /// 浏览器去取；不需要它的场景（测试等）可以传 null。
  final WebViewPageFetcher? _webView;

  /// 已确认「Dart 取不到、必须走 WebView」的主机，命中后不再白白试一次 Dart。
  final _webViewHosts = <String>{};

  /// 已解析出的 KVS 规范详情路径（`host:id` → `/video/<id>/<slug>/`）。
  final _canonicalPaths = <String, String>{};

  /// 抓这些站点固定用桌面版 Chrome 的 UA。
  ///
  /// 两个原因：① 它们对移动 UA 可能返回精简页（Getchu 上踩过同样的坑）；
  /// ② Cloudflare 的 `cf_clearance` 与 UA 绑定，所以应用内的验证页与
  /// WebView 代取都必须用同一串 UA（取值同 [WebViewPageFetcher.userAgent]）。
  static const userAgent = WebViewPageFetcher.userAgent;

  /// 首页：把 [JavSite.sections] 里的列表页并行抓一遍。
  ///
  /// 单个分区失败（多半是被 Cloudflare 拦下、或该分区临时改版）不该把整页拖垮：
  /// 这里逐块兜住，只要有任意一个分区拿到内容就能出首页。**全都失败**时才把
  /// 第一个错误抛出去，界面据此弹验证入口。
  /// 首页：抓第一个分区，其余分区只占位、等被选中时再抓（见 `_HomeSectionState`）。
  ///
  /// 这样做的原因有两个：① 这些站点每个分区都是一次完整页面请求（还要过 Cloudflare、
  /// 走代理），一次发十几个分区既慢又容易被站点限流（实测 jable 会直接 1015）；
  /// ② 首页真正被看到的只有当前选中的那个分区，其余的抓了也白抓。
  Future<HomeFeed> home(JavSite site) async {
    Object? firstError;
    StackTrace? firstStack;
    final sections = await Future.wait(site.sections.map((section) async {
      final path = '${site.baseUrl}${section.path}';
      // 分区翻页走同一条列表路径，所以「更多」链接把路径塞进 `genre` 交给
      // `Han1meRepository.search`（见那里的说明）。
      final moreUrl = '$path?genre=${Uri.encodeComponent(section.path)}';
      if (section != site.sections.first) {
        return HomeSection(title: section.titleKey, moreUrl: moreUrl, videos: const []);
      }
      try {
        final result = await _list(site, path, 1, keyword: null);
        return HomeSection(title: section.titleKey, moreUrl: moreUrl, videos: result.items);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        return HomeSection(title: section.titleKey, moreUrl: moreUrl, videos: const []);
      }
    }));
    final usable = sections.where((section) => section.videos.isNotEmpty).toList(growable: false);
    if (usable.isEmpty) {
      final error = firstError;
      if (error != null) Error.throwWithStackTrace(error, firstStack ?? StackTrace.current);
      // 分区「成功但 0 条」基本只可能是站点在限流/改版（jable 被 Cloudflare 限流时
      // 返回的是一张错误页，解析出来就是空的）。给界面一个明确的失败，而不是白屏。
      Error.throwWithStackTrace(StateError('${site.label} 暂时没有可用内容（可能被站点限流）'), StackTrace.current);
    }
    return HomeFeed(sections: sections);
  }

  /// 搜索。
  ///
  /// 两种用法共用一个入口：
  /// * [keyword] 非空 = 关键词搜索（走站点的搜索路径）；
  /// * [keyword] 为空、[genre] 是列表路径 = 首页分区的「加载更多」（沿着列表路径翻页）。
  Future<SearchResult> search(JavSite site, {required String keyword, required String genre, required int page}) async {
    final text = keyword.trim();
    if (text.isEmpty && genre.startsWith('/')) return _list(site, '${site.baseUrl}$genre', page, keyword: null);
    if (text.isEmpty) return const SearchResult(items: [], page: 1, totalPages: 1);
    return _list(site, _searchUrl(site, text), page, keyword: text);
  }

  /// 详情：元数据 + 播放地址。
  Future<VideoDetail> video(JavSite site, String id) async {
    final document = switch (site.kind) {
      JavSiteKind.kissjav => await _kvsDocument(site, id),
      _ => await _document(_detailUrl(site, id), referer: '${site.baseUrl}/'),
    };
    // 站点被限流（jable 的 Cloudflare Error 1015）或作品已下架时，返回的是一张
    // 「错误页」：它的 og: 标签全是站点默认值。照常解析会把站点 logo 当封面、把
    // `Page not Found` 当标题缓存下来 —— 卡片就集体变成同一张占位图。
    if (_isErrorPage(document)) {
      Error.throwWithStackTrace(StateError('${site.label} 作品页不可用：$id'), StackTrace.current);
    }
    // xhamster 的标题/时长/观看数/播放地址都在页面内联的 `window.initials` 里。
    final initials = site.kind == JavSiteKind.xhamster ? _windowInitials(document) : null;
    final sources = await _sources(site, document, id, initials: initials);
    return _detail(site, document, id, sources, initials: initials);
  }

  /// 取 `window.initials = {...}` 里的 JSON。
  ///
  /// 这段有 100 KB 以上，而且字符串里也含 `}`，所以不能拿正则数括号：这里从
  /// 第一个 `{` 开始手扫，遇到引号就跳过（支持反斜杠转义），括号配平后交给
  /// jsonDecode。
  static Map<String, dynamic>? _windowInitials(dom.Document document) {
    for (final script in document.querySelectorAll('script:not([src])')) {
      final text = script.text;
      final marker = text.indexOf('window.initials');
      if (marker < 0) continue;
      final open = text.indexOf('{', marker);
      if (open < 0) continue;
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var index = open; index < text.length; index++) {
        final char = text[index];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == '\\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth > 0) continue;
          try {
            final decoded = jsonDecode(text.substring(open, index + 1));
            return decoded is Map<String, dynamic> ? decoded : null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 详情页是不是站点自己的错误页（限流 / 已下架）。
  ///
  /// 只认强特征：正常作品页的标题是番号 + 作品名，不会出现这些说法。
  bool _isErrorPage(dom.Document document) {
    final title = (_meta(document, 'og:title') ?? document.querySelector('title')?.text ?? '').trim();
    if (title.isEmpty) return false;
    return RegExp(r'page not found|not found|rate limited|access denied|forbidden', caseSensitive: false).hasMatch(title);
  }

  /// 相关推荐：这些站点要么由前端脚本渲染、要么压根没有，统一返回空，
  /// 详情页的「相关推荐」区块就会自动隐藏。
  Future<List<VideoCard>> related(JavSite site, String id) async => const <VideoCard>[];

  // ---------------------------------------------------------------- 列表页

  String _searchUrl(JavSite site, String keyword) {
    final encoded = Uri.encodeComponent(keyword);
    return switch (site.kind) {
      JavSiteKind.missav => '${site.localizedBaseUrl}/search/$encoded',
      // KVS 的搜索页路径式与 query 式都能出结果，但**只有路径式**能翻页
      // （`/search/<词>/2/`）；所以统一用路径式。
      JavSiteKind.jable || JavSiteKind.kissjav => '${site.baseUrl}/search/$encoded/',
      JavSiteKind.supjav => '${site.baseUrl}/?s=$encoded',
      JavSiteKind.xhamster => '${site.localizedBaseUrl}/search/$encoded',
    };
  }

  /// 抓一个列表页（首页分区、分类翻页、搜索结果都走这里）。
  Future<SearchResult> _list(JavSite site, String url, int page, {required String? keyword}) async {
    final target = _pagedUrl(site, url, page, keyword: keyword);
    final document = await _document(target, referer: '${site.baseUrl}/');
    // xhamster 的列表页只给首屏几张卡片渲染 `<img>`（其余靠前端脚本补图），直接解析
    // DOM 会得到一堆没封面的卡片，所以它单独走 [_xhamsterCards]。
    final items = <VideoCard>[];
    if (site.kind == JavSiteKind.xhamster) {
      items.addAll(_xhamsterCards(site, document));
    } else {
      for (final element in document.querySelectorAll(_itemSelector(site))) {
        final card = _card(site, element);
        if (card != null) items.add(card);
      }
    }
    final totalPages = _totalPages(document, target);
    return SearchResult(items: items, page: page, totalPages: totalPages < page ? page : totalPages);
  }

  /// 拼分页地址。四种形态：`?page=N`（missav / xhamster 搜索页）、`/page/N`（supjav）、
  /// `/path/N/`（KVS）、`/path/N`（xhamster 列表页）。
  String _pagedUrl(JavSite site, String url, int page, {required String? keyword}) {
    if (page <= 1) return url;
    final search = keyword == null ? null : Uri.encodeComponent(keyword);
    return switch (site.kind) {
      JavSiteKind.missav => '$url?page=$page',
      // xhamster 两种分页形式并存：列表页是路径式（站点分页器给的就是 `/newest/2`，
      // 实测 `?page=2` 会被忽略、返回的还是第一页），搜索页才是 `?page=N`。
      JavSiteKind.xhamster => search == null ? '${_trimSlash(url)}/$page' : '${site.baseUrl}/search/$search?page=$page',
      JavSiteKind.supjav => search == null ? '${_trimSlash(url)}/page/$page' : '${site.baseUrl}/page/$page?s=$search',
      JavSiteKind.jable || JavSiteKind.kissjav => search == null ? '${_trimSlash(url)}/$page/' : '${site.baseUrl}/search/$search/$page/',
    };
  }

  static String _trimSlash(String value) => value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  /// 从页面底部的分页器里取最大页码；取不到就认为没有下一页。
  int _totalPages(dom.Document document, String url) {
    final base = Uri.parse(url);
    final current = _trimSlash(base.path);
    var total = 1;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final resolved = base.resolve(href);
      final candidates = <int>[
        int.tryParse(resolved.queryParameters['page'] ?? '') ?? 0,
        int.tryParse(RegExp(r'/page/(\d+)').firstMatch(resolved.path)?.group(1) ?? '') ?? 0,
      ];
      final trailing = RegExp(r'^(.*?)/(\d+)/?$').firstMatch(_trimSlash(resolved.path));
      if (trailing != null && _trimSlash(trailing.group(1)!) == current) candidates.add(int.tryParse(trailing.group(2)!) ?? 0);
      for (final value in candidates) {
        if (value > total) total = value;
      }
    }
    return total;
  }

  String _itemSelector(JavSite site) => switch (site.kind) {
        JavSiteKind.missav => 'div.thumbnail.group',
        JavSiteKind.jable => 'div.video-img-box',
        JavSiteKind.supjav => 'div.post',
        JavSiteKind.kissjav => 'div.thumb_rel.item',
        JavSiteKind.xhamster => 'div.thumb-list__item',
      };

  VideoCard? _card(JavSite site, dom.Element element) {
    final link = _videoAnchor(site, element);
    if (link == null) return null;
    final id = _idFromAnchor(site, link);
    if (id.isEmpty) return null;
    final image = element.querySelector('img');
    final cover = _absolute(site.baseUrl, image?.attributes['data-src'] ?? image?.attributes['data-original'] ?? image?.attributes['src']);
    final title = _title(site, element, link, image);
    if (title.isEmpty) return null;
    return VideoCard(
      id: id,
      title: title,
      coverUrl: cover,
      duration: _cleanDuration(site, _pickText(element, _durationSelectors(site))),
      views: _pickText(element, _viewsSelectors(site)),
      uploadTime: _pickText(element, _dateSelectors(site)),
    );
  }

  /// xhamster 的卡片：**用 DOM 决定「有哪些可播的视频」，用内联 JSON 补全字段**。
  ///
  /// * 列表页只给首屏几张卡片渲染 `<img>`（`thumbsWithoutLazyLoadCount`），其余的
  ///   靠前端脚本补图，直接解析 DOM 只能拿到没封面的卡片；
  /// * 被地区限制的视频（当前出口在日区时会遇到）在 DOM 里是“在 日本 不可用”这种
  ///   没有链接的占位卡片，而内联 JSON 里**照样有**它，所以不能拿 JSON 当列表用，
  ///   否则会给出一堆点进去没有播放地址的卡片。
  ///
  /// 内联 JSON 的位置：`window.initials.layoutPage.videoListProps.videoThumbProps`，
  /// 每项带 `pageURL` / `title` / `imageURL` / `duration`(秒) / `created`(时间戳)。
  List<VideoCard> _xhamsterCards(JavSite site, dom.Document document) {
    final models = <String, Map<String, dynamic>>{};
    for (final item in _xhamsterThumbProps(document)) {
      final link = _asText(item['pageURL']);
      if (link == null) continue;
      final id = _idFromHref(site, link);
      if (id.isNotEmpty) models[id] = item;
    }
    final cards = <VideoCard>[];
    for (final element in document.querySelectorAll(_itemSelector(site))) {
      final anchor = _videoAnchor(site, element);
      if (anchor == null) continue;
      final id = _idFromAnchor(site, anchor);
      if (id.isEmpty) continue;
      final model = models[id];
      final title = _asText(model?['title']) ?? _title(site, element, anchor, element.querySelector('img'));
      if (title.isEmpty) continue;
      final views = int.tryParse('${model?['views'] ?? ''}') ?? 0;
      cards.add(VideoCard(
        id: id,
        title: title,
        coverUrl: _asText(model?['imageURL']) ?? _asText(model?['thumbURL']) ?? _asText(model?['previewThumbURL']) ?? _asText(model?['spriteURL']) ?? _absolute(site.baseUrl, element.querySelector('img')?.attributes['src']),
        duration: _cleanDuration(site, _formatDuration(_asInt(model?['duration'])) ?? _pickText(element, _durationSelectors(site))),
        views: views > 0 ? _asText(model?['views']) : null,
        uploadTime: _xhamsterDate(model?['created']) ?? _pickText(element, _dateSelectors(site)),
      ));
    }
    return cards;
  }

  /// 取列表页里的那个「视频数组」。
  ///
  /// 位置随页面类型变：首页/搜索页在 `layoutPage.videoListProps.videoThumbProps`，
  /// 分类页在 `pagesCategoryComponent.trendingVideoListProps.videoThumbProps`。
  /// 与其一个个枚举（站点每次改版都要跟着改），这里按「键名带 videoThumbProps」递归找；
  /// 都找不到时退回「元素里同时有 `pageURL` 与 `imageURL` 的数组」。
  static List<Map<String, dynamic>> _xhamsterThumbProps(dom.Document document) {
    final initials = _windowInitials(document);
    if (initials == null) return const [];
    final named = <List<Map<String, dynamic>>>[];
    final fallback = <List<Map<String, dynamic>>>[];
    void walk(Object? value, int depth) {
      if (value == null || depth > 4) return;
      if (value is List) {
        if (value.isEmpty) return;
        final items = value.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList(growable: false);
        if (items.isNotEmpty && items.first.containsKey('pageURL') && items.first.containsKey('imageURL')) fallback.add(items);
        return;
      }
      if (value is Map) {
        for (final entry in value.entries) {
          if ('${entry.key}'.contains('videoThumbProps') && entry.value is List) {
            final items = (entry.value as List).whereType<Map>().map((item) => item.cast<String, dynamic>()).toList(growable: false);
            if (items.isNotEmpty) named.add(items);
            continue;
          }
          walk(entry.value, depth + 1);
        }
      }
    }

    walk(initials, 0);
    if (named.isNotEmpty) return named.first;
    return fallback.isEmpty ? const [] : fallback.first;
  }

  /// `created` 是 Unix 秒；卡片的日期统一跟 jable 一样用 `yyyy-MM-dd`。
  static String? _xhamsterDate(Object? value) {
    final seconds = _asInt(value);
    if (seconds == null || seconds <= 0) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${time.year}-${pad(time.month)}-${pad(time.day)}';
  }

  /// 卡片上的视频链接。KVS 系的卡片里还有收藏/稍后观看按钮，所以要按 href 的
  /// 形态挑，而不是取第一个 `a`。
  dom.Element? _videoAnchor(JavSite site, dom.Element element) {
    for (final anchor in element.querySelectorAll('a[href]')) {
      if (_isVideoHref(site, anchor.attributes['href'] ?? '')) return anchor;
    }
    return null;
  }

  bool _isVideoHref(JavSite site, String href) {
    final path = Uri.tryParse(href)?.path ?? href;
    return switch (site.kind) {
      JavSiteKind.missav => _missavSegment(path).isNotEmpty,
      JavSiteKind.jable => RegExp(r'^/videos/[^/]+/?$').hasMatch(path),
      JavSiteKind.supjav => RegExp(r'^/\d+\.html$').hasMatch(path),
      JavSiteKind.kissjav => RegExp(r'^/video/\d+/').hasMatch(path),
      JavSiteKind.xhamster => RegExp(r'^/videos/[^/]+/?$').hasMatch(path),
    };
  }

  String _idFromAnchor(JavSite site, dom.Element anchor) {
    // missav 的封面链接上带 `alt="<番号>"`，比自己从路径里猜可靠（它同时存在
    // `/<番号>` 与 `/zh/<番号>` 两种形态）。
    final alt = anchor.attributes['alt']?.trim() ?? '';
    if (site.kind == JavSiteKind.missav && alt.isNotEmpty) return alt;
    return _idFromHref(site, anchor.attributes['href'] ?? '');
  }

  /// missav 的视频路径可能是 `/zh/fns-233` 也可能（带语言 cookie 时）是 `/fns-233`。
  /// 判据用「末段含数字且不是 `dm123` 这类站点前缀」，足以把 `vip` / `actresses`
  /// / `uncensored-leak` 这些导航项排除掉。
  static String _missavSegment(String path) {
    final segment = path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
    if (segment.isEmpty || !RegExp(r'^[a-z0-9\-]+$').hasMatch(segment)) return '';
    if (!segment.contains(RegExp(r'\d')) || RegExp(r'^dm\d+$').hasMatch(segment)) return '';
    return segment;
  }

  String _title(JavSite site, dom.Element element, dom.Element link, dom.Element? image) {
    final attribute = link.attributes['title']?.trim();
    if (attribute != null && attribute.isNotEmpty) return attribute;
    if (site.kind == JavSiteKind.xhamster) {
      // 卡片链接上没有 `title`，标题在 `aria-label` / `img[alt]` 上，而且带多余空格。
      final label = _normalize(link.attributes['aria-label'] ?? image?.attributes['alt']);
      if (label.isNotEmpty) return label;
    }
    final selectors = switch (site.kind) {
      JavSiteKind.missav => const ['div.my-2 a', 'a.text-secondary'],
      JavSiteKind.jable => const ['h6.title a', '.detail h6 a'],
      JavSiteKind.supjav => const ['h3 a'],
      JavSiteKind.kissjav => const ['.title', 'h6.title'],
      // 标题在卡片链接的 `aria-label` / `img[alt]` 上，上面已经取过了。
      JavSiteKind.xhamster => const <String>[],
    };
    return _pickText(element, selectors) ?? image?.attributes['alt']?.trim() ?? '';
  }

  /// 折掉连续空白并去掉首尾空格（xhamster 的 `img[alt]` 里标题会有双空格）。
  static String _normalize(String? value) => value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  /// 把 JSON 里的值统一成非空字符串（null / 空串都返回 null）。
  static String? _asText(Object? value) {
    final text = _normalize(value?.toString());
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) => value is int ? value : int.tryParse('${value ?? ''}');

  List<String> _durationSelectors(JavSite site) => switch (site.kind) {
        JavSiteKind.missav => const ['span.absolute.bottom-1'],
        JavSiteKind.jable => const ['span.label'],
        JavSiteKind.supjav => const [],
        JavSiteKind.kissjav => const ['.time', '.item-time'],
        // xhamster 卡片上时长就是封面链接自己的文本（如 `13:36`）。
        JavSiteKind.xhamster => const ['a.video-thumb__image-container'],
      };

  /// 卡片上的时长：xhamster 会在时长前加 `4k` / `hd` 角标，只取时间部分。
  static String? _cleanDuration(JavSite site, String? text) {
    if (text == null || site.kind != JavSiteKind.xhamster) return text;
    return RegExp(r'\d{1,2}:\d{2}(?::\d{2})?').firstMatch(text)?.group(0) ?? text;
  }

  List<String> _viewsSelectors(JavSite site) => switch (site.kind) {
        JavSiteKind.missav => const [],
        JavSiteKind.jable => const ['.sub-title'],
        JavSiteKind.supjav => const ['.meta'],
        JavSiteKind.kissjav => const ['div.thumb-item'],
        JavSiteKind.xhamster => const [],
      };

  List<String> _dateSelectors(JavSite site) => switch (site.kind) {
        JavSiteKind.missav || JavSiteKind.jable => const [],
        JavSiteKind.supjav => const ['.meta'],
        JavSiteKind.kissjav => const ['.thumb-item-date'],
        JavSiteKind.xhamster => const ['div.video-thumb__date-added'],
      };

  String? _pickText(dom.Element? element, List<String> selectors) {
    if (element == null) return null;
    for (final selector in selectors) {
      final text = element.querySelector(selector)?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  // ------------------------------------------------------------------ 详情

  String _detailUrl(JavSite site, String id) => switch (site.kind) {
        JavSiteKind.missav => '${site.localizedBaseUrl}/$id',
        JavSiteKind.jable => '${site.baseUrl}/videos/$id/',
        JavSiteKind.supjav => '${site.baseUrl}/$id.html',
        // KVS 的 `/video/<id>/` 会 404，必须带 slug；占位串会拿到一个 301，
        // 真正取页面走 [_kvsDocument]。
        JavSiteKind.kissjav => '${site.baseUrl}/video/$id/x/',
        // xhamster 的 id 就是地址末段（`<slug>-xh<ID>`）。
        JavSiteKind.xhamster => '${site.baseUrl}/videos/$id',
      };

  /// KVS 详情页：`/video/<id>/x/` 只会给一个 301，目标里带着真正的 slug。
  ///
  /// 不能直接让 HttpClient 自动跟随：kissjav 的 slug 是韩文/日文，站点把**原始
  /// UTF-8 字节**写进 `Location`，而 HTTP 头按规范是 Latin-1，Dart 解出来是乱码，
  /// 拿乱码再请求又会拿到同一个 301，最后抛 `Redirect loop detected`。
  /// 所以这里自己取一次 Location、把编码修回来，并把结果按 id 记下来
  /// （同一个视频只会多花这一次请求）。
  Future<dom.Document> _kvsDocument(JavSite site, String id) async {
    final key = '${site.host}:$id';
    final cached = _canonicalPaths[key];
    if (cached != null) return _document('${site.baseUrl}$cached', referer: '${site.baseUrl}/');
    final placeholder = '${site.baseUrl}/video/$id/x/';
    // 走真实浏览器时不需要自己解 301：Chromium 认得那个带非 ASCII 字符的
    // Location，而 Dart 会把它按 Latin-1 解成乱码。
    if (usesWebView(site.baseUrl)) return _document(placeholder, referer: '${site.baseUrl}/');
    final probe = await _fetch(placeholder, referer: '${site.baseUrl}/', followRedirects: false);
    final location = probe.headers['location']?.firstOrNull ?? probe.headers['Location']?.firstOrNull;
    if (location == null || location.isEmpty) return _document(placeholder, referer: '${site.baseUrl}/');
    final resolved = _fixLocationEncoding(site.baseUrl, location);
    _canonicalPaths[key] = Uri.parse(resolved).path;
    return _document(resolved, referer: '${site.baseUrl}/');
  }

  /// 把 `Location` 里被 Latin-1 解错的原生 UTF-8 还原并对路径做百分号编码。
  static String _fixLocationEncoding(String baseUrl, String location) {
    final absolute = Uri.parse(location).hasScheme ? location : '$baseUrl$location';
    try {
      final decoded = utf8.decode(latin1.encode(location));
      if (decoded == location) return absolute;
      final uri = Uri.parse(decoded);
      return uri.replace(pathSegments: uri.pathSegments.map(Uri.encodeComponent)).toString();
    } catch (_) {
      return absolute;
    }
  }

  String _idFromHref(JavSite site, String href) {
    final path = Uri.tryParse(href)?.path ?? href;
    return switch (site.kind) {
      JavSiteKind.missav => _missavSegment(path),
      JavSiteKind.jable => RegExp(r'^/videos/([^/]+)/?$').firstMatch(path)?.group(1) ?? '',
      JavSiteKind.supjav => RegExp(r'^/(\d+)\.html$').firstMatch(path)?.group(1) ?? '',
      JavSiteKind.kissjav => RegExp(r'^/video/(\d+)/').firstMatch(path)?.group(1) ?? '',
      // xhamster 的地址是 `<slug>-xh<ID>`，纯数字 ID 会 404，所以把整段末段当 id。
      JavSiteKind.xhamster => RegExp(r'^/videos/([^/]+)/?$').firstMatch(path)?.group(1) ?? '',
    };
  }

  VideoDetail _detail(JavSite site, dom.Document document, String id, List<VideoSource> sources, {Map<String, dynamic>? initials}) {
    if (site.kind == JavSiteKind.xhamster) return _xhamsterDetail(site, document, id, sources, initials);
    final root = document.documentElement;
    final title = _firstNonEmpty([_meta(document, 'og:title'), textOf(document.querySelector('h1')), textOf(document.querySelector('title'))]);
    return VideoDetail(
      id: id,
      title: title ?? 'Untitled',
      coverUrl: _absolute(site.baseUrl, _coverPath(site, document)),
      duration: _formatDuration(int.tryParse(RegExp(r'\d+').firstMatch(_meta(document, 'og:video:duration') ?? '')?.group(0) ?? '')) ?? _pickText(root, _durationSelectors(site)),
      artist: _artist(site, document) ?? _meta(document, 'og:video:actor'),
      genre: _pickText(root, _genreSelectors(site)),
      views: _views(site, document) ?? _meta(document, 'og:video:view_count'),
      uploadDate: _uploadDate(site, document) ?? _meta(document, 'og:video:release_date'),
      description: _firstNonEmpty([_meta(document, 'og:description'), _meta(document, 'description')]),
      tags: _tags(site, document),
      sources: sources,
      playlist: const [],
      related: const [],
    );
  }

  /// xhamster 的元数据全在 `window.initials.videoModel` 里：页面上反而缺
  /// `og:video:duration` / `og:video:view_count`，`og:title` 还带着
  /// 「... HD 色情视频 | xHamster」这类尾巴，所以这里以 model 为准。
  VideoDetail _xhamsterDetail(JavSite site, dom.Document document, String id, List<VideoSource> sources, Map<String, dynamic>? initials) {
    final model = (initials?['videoModel'] as Map?)?.cast<String, dynamic>();
    final title = _normalize(model?['title']?.toString());
    return VideoDetail(
      id: id,
      title: title.isNotEmpty ? title : (textOf(document.querySelector('h1')) ?? 'Untitled'),
      coverUrl: _absolute(site.baseUrl, _asText(model?['thumbURL']) ?? _coverPath(site, document)),
      duration: _formatDuration(_asInt(model?['duration'])),
      artist: _asText((model?['author'] as Map?)?['name']),
      genre: null,
      views: _asText(model?['views']),
      uploadDate: _xhamsterDate(model?['created']) ?? _firstNonEmpty([_asText(model?['createdAt']), _asText(model?['uploadDate'])]),
      description: _asText(model?['description']) ?? _firstNonEmpty([_meta(document, 'og:description'), _meta(document, 'description')]),
      tags: _xhamsterTags(document),
      sources: sources,
      playlist: const [],
      related: const [],
    );
  }

  /// xhamster 详情页不给标签链接，标签只出现在 `document.title` 的尾巴上：
  /// `标题 主演: 演员 — 标签1, 标签2 HD 色情视频 | xHamster`。
  List<VideoTag> _xhamsterTags(dom.Document document) {
    final title = textOf(document.querySelector('title')) ?? '';
    final parts = title.split('—');
    if (parts.length < 2) return const [];
    var tail = parts.last;
    for (final noise in const ['| xHamster', 'HD 色情视频', '色情视频', 'HD Porn', 'HD Video', 'HD']) {
      tail = tail.replaceAll(noise, '');
    }
    final names = <String>[];
    for (final name in tail.split(RegExp(r'[,，]'))) {
      final value = _normalize(name);
      if (value.isEmpty || value.length > 24 || value.contains('|') || names.contains(value)) continue;
      names.add(value);
    }
    return names.take(20).map((name) => VideoTag(name: name)).toList(growable: false);
  }

  /// 详情页封面：优先 og:image，其次详情区块里的图（KVS 常用 `data-original` 懒加载）。
  ///
  /// supjav 没有 og:image，而页面上第一张 `img[data-original]` 是「相关影片」的缩略图，
  /// 所以它单独走 `img.img`（详情大图就是这个 class）。
  String? _coverPath(JavSite site, dom.Document document) {
    final meta = _meta(document, 'og:image');
    if (meta != null && meta.isNotEmpty) return meta;
    if (site.kind == JavSiteKind.supjav) return document.querySelector('img.img')?.attributes['src'];
    final image = document.querySelector('.video-info img, .info-holder img, img[data-original]') ?? document.querySelector('img');
    return image?.attributes['data-original'] ?? image?.attributes['data-src'] ?? image?.attributes['src'];
  }

  List<String> _genreSelectors(JavSite site) => switch (site.kind) {
        JavSiteKind.jable => const ['h5.tags', '.tags.h6-md'],
        _ => const [],
      };

  List<VideoTag> _tags(JavSite site, dom.Document document) {
    final anchors = switch (site.kind) {
      JavSiteKind.missav => document.querySelectorAll('a[href*="/genres/"]'),
      JavSiteKind.jable => document.querySelectorAll('.tags a[href*="/tags/"]'),
      JavSiteKind.supjav => document.querySelectorAll('a[href*="/tag/"]'),
      JavSiteKind.kissjav => document.querySelectorAll('a.tags-link'),
      // xhamster 不走这条通用路径（见 [_xhamsterDetail]），标签另有来源。
      JavSiteKind.xhamster => const <dom.Element>[],
    };
    final names = <String>[];
    void add(String name) {
      final value = name.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isNotEmpty && value.length <= 24 && !names.contains(value)) names.add(value);
    }

    for (final anchor in anchors) {
      add(anchor.text);
    }
    // kissjav 的详情页不给标签链接，分类只存在于 flashvars 里。
    if (site.kind == JavSiteKind.kissjav) {
      final fields = _scriptFields(document);
      for (final key in const ['video_tags', 'video_categories']) {
        for (final name in (fields[key] ?? '').split(',')) {
          add(name);
        }
      }
    }
    for (final keyword in (_meta(document, 'keywords') ?? '').split(',')) {
      add(keyword);
    }
    return names.take(20).map((name) => VideoTag(name: name)).toList(growable: false);
  }

  String? _artist(JavSite site, dom.Document document) {
    final anchor = switch (site.kind) {
      JavSiteKind.jable => document.querySelector('.models a.model'),
      JavSiteKind.supjav => document.querySelector('a[href*="/cast/"][rel="tag"], a[href*="/cast/"]'),
      _ => null,
    };
    if (anchor == null) return null;
    // jable 把名字放在链接内的 span 上（链接本身只有首字）；supjav 没有名字属性。
    final title = anchor.attributes['title']?.trim() ?? anchor.querySelector('[title]')?.attributes['title']?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final text = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  String? _views(JavSite site, dom.Document document) {
    switch (site.kind) {
      case JavSiteKind.jable:
        // `section.video-info h6` 里前面是时间、后面是观看数，再后面还有演员缩略图，
        // 所以只认「纯数字 + 空格」的那个 span。
        for (final span in document.querySelectorAll('section.video-info h6 span')) {
          final text = span.text.trim();
          if (text.isNotEmpty && RegExp(r'^[\d\s,.]+$').hasMatch(text)) return text;
        }
        return null;
      case JavSiteKind.supjav:
        // `.meta` 里日期和观看数是连在一起的（`2026/09/2042655 Views`），只取观看数。
        final meta = textOf(document.querySelector('.meta'));
        return meta == null ? null : RegExp(r'([\d,.]+\s*Views)', caseSensitive: false).firstMatch(meta)?.group(1)?.trim();
      default:
        return null;
    }
  }

  String? _uploadDate(JavSite site, dom.Document document) => switch (site.kind) {
        JavSiteKind.jable => RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(document.querySelector('section.video-info .inactive-color')?.text ?? '')?.group(0),
        JavSiteKind.kissjav => textOf(document.querySelector('.thumb-item-date')),
        JavSiteKind.supjav => RegExp(r'\d{4}/\d{2}/\d{2}').firstMatch(document.querySelector('.meta')?.text ?? '')?.group(0),
        _ => null,
      };

  /// 取 `<meta property|name="<key>">` 的 content。
  String? _meta(dom.Document document, String key) {
    final content = document.querySelector('meta[property="$key"]')?.attributes['content'] ?? document.querySelector('meta[name="$key"]')?.attributes['content'];
    final value = content?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String? textOf(dom.Element? element) {
    final text = element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return text.isEmpty ? null : text;
  }

  // ---------------------------------------------------------------- 播放源

  Future<List<VideoSource>> _sources(JavSite site, dom.Document document, String id, {Map<String, dynamic>? initials}) {
    final headers = {'Referer': '${site.baseUrl}/', 'User-Agent': userAgent, 'Origin': site.baseUrl};
    return switch (site.kind) {
      JavSiteKind.missav => Future.value(_sourcesFromPacker(document, headers)),
      JavSiteKind.jable => Future.value(_sourcesFromHlsUrl(document, headers)),
      JavSiteKind.supjav => _sourcesFromSupjav(document, headers),
      JavSiteKind.kissjav => Future.value(_sourcesFromFlashvars(document, headers)),
      JavSiteKind.xhamster => Future.value(_sourcesFromInitials(document, initials, headers)),
    };
  }

  /// xhamster：播放地址在 `window.initials.xplayerSettings.sources` 里，而且被
  /// 混淆过（十六进制串，解密见 [xhamsterDecipher]）。
  ///
  /// 两组地址：`standard` 是按画质分档的 MP4 直链，`hls` 是带 `_TPL_` 占位的 HLS
  /// 主列表。这里**只用 HLS**，两个原因：
  /// * MP4 直链带 IP 绑定签名（路径上是 `data=<请求方 IP>-dvp`），换个出口/重解析就
  ///   403，实测在这个环境里拉不动；
  /// * 直接把主列表交给 libmpv 会被反复重读、变体永远开不出来（卡在打开阶段），
  ///   而把 `_TPL_` 换成具体档位（如 `720p`）得到的**变体列表**是正常的 VOD 列表，
  ///   实测能直接播。
  List<VideoSource> _sourcesFromInitials(dom.Document document, Map<String, dynamic>? initials, Map<String, String> headers) {
    final groups = ((initials?['xplayerSettings'] as Map?)?['sources'] as Map?)?.cast<String, dynamic>();
    if (groups == null) return const [];
    final standard = (groups['standard'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final master = _xhamsterMaster(document, groups);
    final sources = <VideoSource>[];
    if (master != null && master.contains('_TPL_')) {
      // 主列表自己声明了有哪些档位（`multi=256x144:144p,426x240:240p,...`），
      // 没声明就退回 `standard` 里的档位。按从高到低给出，播放器默认拿最高档。
      final heights = <String>[];
      final declared = RegExp(r'multi=([^/]+)').firstMatch(master)?.group(1);
      if (declared != null) {
        for (final part in declared.split(',')) {
          final height = RegExp(r'\d+p').firstMatch(part)?.group(0);
          if (height != null && !heights.contains(height)) heights.add(height);
        }
      }
      if (heights.isEmpty) {
        for (final list in standard.values) {
          for (final item in (list as List?) ?? const []) {
            final quality = _normalize((item as Map?)?['quality'] as String?);
            if (quality.isEmpty || quality == 'auto' || heights.contains(quality)) continue;
            heights.add(quality);
          }
        }
      }
      for (final height in heights.reversed) {
        sources.add(VideoSource(quality: height, url: master.replaceAll('_TPL_', height), type: 'application/x-mpegURL', headers: headers));
      }
    }
    if (sources.isNotEmpty) return sources;
    // 没 HLS 主列表（少数短视频）时只好用 MP4 直链，能播就播。
    for (final list in standard.values) {
      for (final item in (list as List?) ?? const []) {
        final map = (item as Map?)?.cast<String, dynamic>();
        final url = xhamsterDecipher(map?['url'] as String?) ?? xhamsterDecipher(map?['fallback'] as String?);
        if (url == null) continue;
        final quality = _normalize(map?['quality'] as String?);
        sources.add(VideoSource(quality: quality.isEmpty || quality == 'auto' ? 'Auto' : quality, url: url, type: 'video/mp4', headers: headers));
      }
    }
    return sources;
  }

  /// 挑一条**能播**的 HLS 主列表。
  ///
  /// 同一个视频站点会给两条：一条带额外签名（`…/key=…,end=…/data=<请求方 IP>-dvp/referer=/…`），
  /// 实测 mpv/ffmpeg 拉不起来（一直停在打开阶段，界面就是无限转圈）；另一条是
  /// `https://video-nss-h.xhcdn.com/<token>,<过期时间>/media=hls4/…`，直接能播。
  /// **哪条在 `url`、哪条在 `fallback` 会随视频互换**（实测同一站点两个视频正好相反），
  /// 所以不能按字段名取，改按「不含 `data=`」挑；两条都带签名时才退回第一条。
  String? _xhamsterMaster(dom.Document document, Map<String, dynamic> groups) {
    final candidates = <String>[];
    void add(String? value) {
      if (value != null && value.contains('_TPL_') && !candidates.contains(value)) candidates.add(value);
    }

    // 解一下所有编码的 hls 项（目前是 h264，将来可能是 av1）。
    for (final codec in ((groups['hls'] as Map?) ?? const <String, Object>{}).values) {
      final item = (codec as Map?)?.cast<String, dynamic>();
      add(xhamsterDecipher(item?['url'] as String?));
      add(xhamsterDecipher(item?['fallback'] as String?));
    }
    add(_plainTemplateUrl(document));
    for (final candidate in candidates) {
      if (!candidate.contains('data=')) return candidate;
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  /// 兜底：`xplayerSettings` 被混淆失效时，页面里往往还留着一条**未加密**的
  /// `…_TPL_.h264.mp4.m3u8`（同类开源提取器就是直接拿它当播放地址的），拿来用即可。
  static String? _plainTemplateUrl(dom.Document document) {
    final html = document.documentElement?.outerHtml ?? '';
    final match = RegExp(r'https?:(?:\\?/){2}[^"\s]+?_TPL_\.(?:h264|av1)\.mp4\.m3u8').firstMatch(html);
    return match?.group(0)?.replaceAll(r'\/', '/');
  }

  /// missav：播放地址是一段 Dean Edwards packer 打包过的脚本，解开后是
  /// `source`（主列表，里面带 360p/480p/720p/1080p 四档）与 `source842`/
  /// `source1280` 两个分档变量。
  ///
  /// 注意变量名里的数字**不是**真实档位：实测 `source842` 与 `source1280` 都指向
  /// 同一个 `720p/video.m3u8`，按变量名标成 842p/1280p 会让「按首选画质选档」挑错。
  List<VideoSource> _sourcesFromPacker(dom.Document document, Map<String, String> headers) {
    final unpacked = unpackDeanEdwards(_inlineScripts(document));
    if (unpacked == null) return const [];
    final sources = <VideoSource>[];
    for (final match in RegExp(r'''(\w+)\s*=\s*['"](https?://[^'"]+\.m3u8[^'"]*)['"]''').allMatches(unpacked)) {
      final name = match.group(1)!;
      final url = match.group(2)!;
      if (sources.any((source) => source.url == url)) continue;
      sources.add(VideoSource(quality: _qualityLabel(name, url), url: url, type: 'application/x-mpegURL', headers: headers));
    }
    return sources;
  }

  /// 主列表（`playlist.m3u8`）交给内核自己选档，标成 Auto；其余以 URL 里的档位目录
  /// 为准（形如 `/720p/video.m3u8`），认不出来时才退回变量名里的数字。
  static String _qualityLabel(String name, String url) {
    final fromUrl = RegExp(r'/(\d{3,4})p/').firstMatch(url)?.group(1);
    if (fromUrl != null) return '${fromUrl}p';
    if (name == 'source' || url.contains('playlist.m3u8')) return 'Auto';
    final height = int.tryParse(RegExp(r'\d+').firstMatch(name)?.group(0) ?? '');
    return height == null ? 'Default' : '${height}p';
  }

  /// jable：详情页内联 `var hlsUrl = '...'`（AES-128 的媒体列表，只有一档）。
  List<VideoSource> _sourcesFromHlsUrl(dom.Document document, Map<String, String> headers) {
    final scripts = _inlineScripts(document);
    final url = RegExp(r'''["']?(?:hlsUrl|source|video_url)["']?\s*[:=]\s*['"]([^'"]+\.m3u8[^'"]*)['"]''').firstMatch(scripts)?.group(1) ?? _mediaUrlPattern.firstMatch(scripts)?.group(0);
    if (url == null || url.isEmpty) return const [];
    return [VideoSource(quality: 'Default', url: url, type: 'application/x-mpegURL', headers: headers)];
  }

  /// supjav：详情页给一组 `data-link="<token>">服务器名</a>`，取 TV 那一路的 token
  /// 反转后去换真正的播放地址（沿用 supjavd 的做法，2026-09-20 实测仍可用：
  /// 那一步会 302 到播放器页，主播放列表地址就写在该页脚本里）。
  Future<List<VideoSource>> _sourcesFromSupjav(dom.Document document, Map<String, String> headers) async {
    final token = document
        .querySelectorAll('a[data-link]')
        .where((anchor) => anchor.text.replaceAll(RegExp(r'\s+'), '') == 'TV')
        .map((anchor) => anchor.attributes['data-link']?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (token.isEmpty) return const [];
    final reversed = token.split('').reversed.join();
    // 这一步是跳域的（先 302 到播放器页，地址写在该页脚本里）。用 [_fetch] 的好处是
    // 该域名如果同样拦 Dart，也会自动改用 WebView —— 浏览器跟随跳转不受 CORS 限制。
    final response = await _fetch('https://lk1.supremejav.com/supjav.php?c=$reversed', referer: 'https://supjav.com/');
    final url = RegExp(r'''urlPlay[^\n]{0,200}?(https?://[^\s"'<>]+\.m3u8[^\s"'<>]*)''').firstMatch(response.body)?.group(1) ?? _mediaUrlPattern.firstMatch(response.body)?.group(0);
    if (url == null || url.isEmpty) return const [];
    return [VideoSource(quality: 'Default', url: url, type: 'application/x-mpegURL', headers: headers)];
  }

  /// kissjav：KVS 的 `flashvars` 里直接给多档地址，且是 base64（页面里用 `atob` 解）。
  List<VideoSource> _sourcesFromFlashvars(dom.Document document, Map<String, String> headers) {
    final fields = _scriptFields(document);
    final sources = <VideoSource>[];
    void add(String key, String labelKey, String fallback) {
      final url = _decodedMedia(fields[key]);
      if (url == null || sources.any((source) => source.url == url)) return;
      final label = fields[labelKey]?.trim() ?? '';
      sources.add(VideoSource(quality: label.isEmpty ? fallback : label, url: url, headers: headers));
    }

    add('video_url_hd', 'video_url_hd_text', 'HD');
    add('video_url', 'video_url_text', 'Default');
    return sources;
  }

  /// `flashvars` 里的直链可能是 base64（kissjav 用 `atob` 解一次再交给播放器）。
  String? _decodedMedia(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.startsWith('http')) return text;
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      return decoded.startsWith('http') ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _inlineScripts(dom.Document document) => document.querySelectorAll('script').map((script) => script.text).join('\n');

  /// 页面内联脚本里 `key: 'value'` 形式的字段（KVS 的 flashvars 就是这种写法）。
  Map<String, String> _scriptFields(dom.Document document) {
    final fields = <String, String>{};
    for (final match in RegExp(r'''(\w+)\s*:\s*['"]([^'"]*)['"]''').allMatches(_inlineScripts(document))) {
      fields[match.group(1)!] = match.group(2)!;
    }
    return fields;
  }

  /// 页面里任意一个 m3u8 直链（各站点的兜底手段）。
  static final _mediaUrlPattern = RegExp(r'''https?://[^\s"'<>]+\.m3u8[^\s"'<>]*''');

  // ------------------------------------------------------------------ 通用

  Future<dom.Document> _document(String url, {String? referer}) async => html_parser.parse((await _fetch(url, referer: referer)).body);

  /// 取一个页面。先用 Dart 的 HttpClient（快），被 Cloudflare 拦下时改用真实 Chromium。
  ///
  /// 「被拦」有两种形态：响应体是挑战页（要过验证），以及按 TLS/HTTP2 指纹硬拦
  /// —— 后者无法在 Dart 侧绕过（同样的请求头，curl 与浏览器都正常），所以只能换成
  /// 真的浏览器去取，见 [WebViewPageFetcher]。
  Future<Han1meHttpResponse> _fetch(String url, {String? referer, bool followRedirects = true}) async {
    final host = Uri.parse(url).host;
    if (_webViewHosts.contains(host)) {
      final cached = await _fetchViaWebView(url);
      if (cached == null) _challenge(url);
      return cached;
    }
    final response = await _http.get(url, followRedirects: followRedirects, headers: {
      'User-Agent': userAgent,
      'Referer': referer ?? '${Uri.parse(url).origin}/',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7',
    });
    final challenged = _isChallenge(response.statusCode, response.headers, response.body);
    if (!challenged && response.statusCode < 400) return response;
    final viaWebView = await _fetchViaWebView(url);
    if (viaWebView != null) {
      _webViewHosts.add(host);
      return viaWebView;
    }
    _challenge(url);
  }

  /// 用无界面 WebView（真实 Chromium）取页面；失败或仍停在验证页时返回 null。
  Future<Han1meHttpResponse?> _fetchViaWebView(String url) async {
    final fetcher = _webView;
    if (fetcher == null) return null;
    final html = await fetcher.html(url);
    if (html == null || html.isEmpty || WebViewPageFetcher.isChallengeBody(html)) return null;
    return Han1meHttpResponse(statusCode: 200, body: html, headers: const {}, url: url);
  }

  /// 该站点是否已确认需要走真实浏览器。
  bool usesWebView(String baseUrl) => _webViewHosts.contains(Uri.tryParse(baseUrl)?.host ?? '');

  /// 抛「需要人机验证」：界面会据此给出「完成验证」入口（在可见的 WebView 里
  /// 手动过一次，cookie 会留在同一个 WebView2 配置里，之后代取就能直接用）。
  Never _challenge(String url) => throw CloudflareChallengeException(url);

  /// [Han1meApi.isCloudflareResponse] 只认 403；这些站点被拦时也可能给 503，
  /// 所以再补一层「响应体里带挑战页特征」的判断。
  static bool _isChallenge(int? statusCode, Map<String, List<String>> headers, String body) {
    if (Han1meApi.isCloudflareResponse(statusCode, headers, body)) return true;
    return (statusCode == 403 || statusCode == 503) && RegExp(r'Just a moment|cf-chl-|challenge-platform|__cf_chl', caseSensitive: false).hasMatch(body);
  }

  String _absolute(String baseUrl, String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    return Uri.parse(baseUrl).resolve(value).toString();
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remaining = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0 ? '${duration.inHours}:$minutes:$remaining' : '$minutes:$remaining';
  }
}
