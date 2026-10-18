import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;

/// 图片缓存索引文件的路径（`<应用数据目录>/han1me_images.json`）。
///
/// 必须显式给：`flutter_cache_manager` 内部用 `getApplicationSupportDirectory()` 决定
/// 索引位置，而那条路径在 Windows 上由 exe 的 VERSIONINFO（`CompanyName\ProductName`）
/// 拼出来，指向 `%APPDATA%\Han1meWinPlus\Han1meWinPlus\` —— 与应用真正在用的
/// `%APPDATA%\han1me_win_plus\` 是两个目录。后果实测过：索引写进了那个历史目录，
/// 而图片本体在 `%TEMP%`，两边对不上账，清缓存清不干净、索引还时不时写失败
/// （`PathAccessException: 拒绝访问`）。详见 platform_paths.dart 的说明。
///
/// 惰性求值：`APPDATA` 要等进程起来才读得到，所以先给个 null，首次用到时再算。
String? _imageCacheIndexPath;

/// 封面图的磁盘缓存。
///
/// 图片站点（CDN77）的单张响应实测在 0.3–5s 之间抖（服务端回源慢），偶尔还会握手失败，
/// 客户端能做的就是别重复下载：`CacheManager` 默认只留 200 个对象，首页翻两屏就被挤掉。
/// 这里放宽到 2000 个（单张缩略图只有 20–50KB）、保留 30 天。
final appImageCacheManager = CacheManager(
  Config(
    'han1me_images',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 2000,
    // 索引落到应用自己的数据目录，别让它跟着 VERSIONINFO 跑。
    repo: JsonCacheInfoRepository(
      path: _imageCacheIndexPath ??= _resolveImageCacheIndexPath(),
    ),
  ),
);

String _resolveImageCacheIndexPath() {
  final appData = Platform.environment['APPDATA'];
  final base = (appData != null && appData.isNotEmpty)
      ? Directory(path.join(appData, 'han1me_win_plus'))
      : Directory.systemTemp;
  return path.join(base.path, 'han1me_images.json');
}

/// 易变参数：这些值由服务端按请求现算，不能进缓存 key。
///
/// `secure` 的形态是 `<签名>,<过期时间戳>`，后半段是**服务器处理该请求时**生成的
/// （实测三条记录的过期时间戳彼此只差几秒，而它们的抓取时间差了几百秒）。所以同一个
/// 视频每次抓页面拿到的封面 URL 都不同。
///
/// 后果实测过：缓存目录里 167 个文件只有 113 份唯一内容，**54 组是同一张图存了两份**，
/// 两组之间相隔约 23 分钟（两次启动各下载了一遍）。也就是说每次打开应用都要把首屏
/// 封面重新下一遍 —— 这正是「图片加载慢」里客户端能修的那部分。
///
/// 路径部分（如 `/image/thumbnail/406505h.jpg`）已经唯一标识了图片内容，用它做 key
/// 就够了；请求时仍然带上完整 URL（含签名），否则服务端会 403。
///
/// 名单刻意收窄：只列语义明确的签名参数，不用 `st`/`e`/`exp` 这类短名 —— 它们也可能
/// 是尺寸或画质参数，误去掉会让不同的图共用一个 key。目前数据里出现的只有 `secure`
/// （56/56 个 URL），其余是为将来接入其它源预留的。
const _volatileQueryParameters = {
  'secure',
  'token',
  'sign',
  'signature',
  'expires',
  'authkey',
};

/// 去掉易变参数后的 URL，用作缓存 key。
///
/// 解析失败时原样返回：宁可退化成「按完整 URL 缓存」，也不要用一个错误的 key
/// 让不同的图互相覆盖。
String imageCacheKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.queryParameters.isEmpty) return url;
  final kept = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    if (!_volatileQueryParameters.contains(key.toLowerCase())) kept[key] = value;
  });
  // 按字符串切出「不含查询串」的基址，而不是走 Uri.replace —— 后者几次三番
  // 留下孤立的 `?` 或 `#`（replace 把 null 当「不变」，传空串又会留下分隔符）。
  final withoutQuery = url.split('?').first.split('#').first;
  if (kept.isEmpty) return withoutQuery;
  // 保留的参数用 Uri 编码回查询串，保证与请求时一致。
  final query = Uri(queryParameters: kept).query;
  return '$withoutQuery?$query';
}

/// 头像这类网络图片也走同一个缓存，避免每次启动都重新下载一遍。
///
/// [cacheKey] 显式指定，不走默认的「整个 URL」：见 [imageCacheKey] 的说明。
ImageProvider appNetworkImage(String url) => CachedNetworkImageProvider(
      url,
      cacheKey: imageCacheKey(url),
      cacheManager: appImageCacheManager,
    );

/// 需要额外参数（解码尺寸等）时用这个，别直接 `new CachedNetworkImageProvider`。
///
/// 直接构造会退回默认的「按完整 URL 缓存」，于是带 `secure` 的封面每次都会重新下载 ——
/// 这正是 [imageCacheKey] 要解决的问题。所有加载网络图的地方都该走这里或
/// [appNetworkImage]，两个入口共享同一个 [appImageCacheManager]。
ImageProvider appCachedImage(
  String url, {
  int? maxWidth,
  int? maxHeight,
}) =>
    CachedNetworkImageProvider(
      url,
      cacheKey: imageCacheKey(url),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      cacheManager: appImageCacheManager,
    );

/// [CachedNetworkImage] 的替代品：自动带上稳定的 [cacheKey]。
///
/// 各处加载封面都该用它，别直接 `CachedNetworkImage(...)` —— 后者默认按完整 URL
/// 缓存，带 `secure` 的封面于是每次启动都重新下载一遍（见 [imageCacheKey]）。
/// 这里把 [cacheManager] 也固定住，少一处可以写错的地方。
class AppCachedNetworkImage extends StatelessWidget {
  const AppCachedNetworkImage({
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.memCacheWidth,
    this.alignment = Alignment.center,
    this.httpHeaders,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
    super.key,
  });

  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final Alignment alignment;
  final Map<String, String>? httpHeaders;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// 自定义图片层。加载完成后才会被调用，所以可以用它把「图到齐了」这件事
  /// 转告外层的其它内容（例如让标题和价格跟封面同时出现）。
  final ImageWidgetBuilder? imageBuilder;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
        imageUrl: imageUrl,
        cacheKey: imageCacheKey(imageUrl),
        cacheManager: appImageCacheManager,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        alignment: alignment,
        httpHeaders: httpHeaders,
        placeholder: placeholder,
        errorWidget: errorWidget,
        imageBuilder: imageBuilder,
        fadeInDuration: fadeInDuration,
        fadeOutDuration: fadeOutDuration,
      );
}
