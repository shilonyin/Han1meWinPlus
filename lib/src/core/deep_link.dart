import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// `han1me://` 自定义 URL scheme 的解析与落地路由。
///
/// Windows 上 scheme 唤起是系统把链接作为命令行参数递给进程的（runner 已把
/// argv 转交给 Dart），所以不需要额外插件，直接解析参数即可。
///
/// 支持两种链接：
/// - `han1me://video/{id}` → 打开视频
/// - `han1me://search?q=关键字` → 打开搜索结果
class DeepLink {
  DeepLink._();

  static const scheme = 'han1me';

  /// 从命令行参数里挑出第一个 `han1me://` 链接。
  static Uri? fromArguments(List<String> arguments) {
    for (final argument in arguments) {
      final uri = Uri.tryParse(argument);
      if (uri != null && uri.scheme == scheme) return uri;
    }
    return null;
  }

  /// 把链接翻译成应用内路由；不认识的链接返回 null（交给默认首页）。
  static String? routeFor(Uri uri) {
    if (uri.scheme != scheme) return null;
    // 兼容 `han1me://video/123` 与 `han1me:///video/123`（后者 host 为空）。
    final segments = <String>[...uri.pathSegments];
    if (segments.isEmpty) return null;
    switch (segments.first) {
      case 'video':
        if (segments.length < 2 || segments[1].isEmpty) return null;
        return '/video/${segments[1]}';
      case 'search':
        final query = uri.queryParameters['q'] ?? '';
        if (query.isEmpty) return '/search';
        return '/search?q=${Uri.encodeComponent(query)}';
      default:
        return null;
    }
  }

  /// 应用启动后跳转：替换掉默认首页，直接落在链接指向的页面。
  static void open(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    final route = routeFor(uri);
    if (route == null) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    context.pushReplacement(route);
  }
}
