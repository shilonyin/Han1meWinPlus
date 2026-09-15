import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 封面图的磁盘缓存。
///
/// 图片站点（CDN77）的单张响应实测在 0.3–5s 之间抖（服务端回源慢），偶尔还会握手失败，
/// 客户端能做的就是别重复下载：`CacheManager` 默认只留 200 个对象，首页翻两屏就被挤掉。
/// 这里放宽到 2000 个（单张缩略图只有 20–50KB）、保留 30 天。
final appImageCacheManager = CacheManager(
  Config('han1me_images', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 2000),
);

/// 头像这类网络图片也走同一个缓存，避免每次启动都重新下载一遍。
ImageProvider appNetworkImage(String url) => CachedNetworkImageProvider(url, cacheManager: appImageCacheManager);
