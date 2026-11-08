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

  /// 开发用：`--preview=<应用内路由>` 启动时直接落到该页面（例如
  /// `han1me_win_plus.exe --preview=/settings/theme`）。
  ///
  /// 这是**给逐页截图比对设计稿**用的：应用启动只能落在首页，而设置、详情这些页
  /// 要一路点过去，每改一次样式就得重走一遍，没法自动化。有了它，
  /// `flutter build` + 一条命令就能把任意页面截成图。
  ///
  /// 只认以 `/` 开头的应用内路径，不接受完整 URL —— 避免它变成第二个深链入口。
  static const previewFlag = '--preview=';

  /// 从命令行参数里挑出预览路由（没有则返回 null）。
  static Uri? previewFromArguments(List<String> arguments) {
    for (final argument in arguments) {
      if (!argument.startsWith(previewFlag)) continue;
      final route = argument.substring(previewFlag.length);
      if (!route.startsWith('/')) continue;
      return Uri.parse(route);
    }
    return null;
  }

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
      case 'login':
        return '/login';
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

  /// 跳到预览路由（`--preview=` 用）。
  ///
  /// 与 [open] 的区别：这里给的就是应用内路径，**不做 scheme 校验**；
  /// 带查询串时（如 `/search?genre=里番`）原样带上，否则只取 path。
  static void openPreview(Uri route, GlobalKey<NavigatorState> navigatorKey) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    context.pushReplacement(route.hasQuery ? route.toString() : route.path);
  }
}
