import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../core/dlna_media_renderer.dart';
import '../core/route_observer.dart';
import '../domain/models/comic.dart';
import '../domain/models/search_query.dart';
import '../domain/models/video.dart';
import '../features/account/account_web_page.dart';
import '../features/account/login_page.dart';
import '../features/account/manual_cookie_page.dart';
import '../features/account/account_page.dart';
import '../features/cache/cache_page.dart';
import '../features/comics/comic_pages.dart';
import '../features/explore/explore_page.dart';
import '../features/library/library_page.dart';
import '../features/library/local_media_page.dart';
import '../features/navigation/app_shell.dart';
import '../features/navigation/exit_coordinator.dart';
import '../features/previews/getchu_preview_detail_page.dart';
import '../features/previews/getchu_preview_page.dart';
import '../features/previews/previews_page.dart';
import '../features/checkin/check_in_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/about_page.dart';
import '../features/settings/site_diagnostics_page.dart';
import '../features/settings/storage_settings_page.dart';
import '../features/settings/backup_settings_page.dart';
import '../features/settings/cloudflare_page.dart';
import '../features/settings/comment_settings_page.dart';
import '../features/settings/home_categories_page.dart';
import '../features/settings/hotkey_settings_page.dart';
import '../features/settings/keyframes_page.dart';
import '../features/settings/language_settings_page.dart';
import '../features/settings/layout_settings_page.dart';
import '../features/settings/license_page.dart';
import '../features/settings/network_settings_page.dart';
import '../features/settings/playback_settings_page.dart';
import '../features/settings/player_settings_page.dart';
import '../features/settings/recommendation_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/theme_settings_page.dart';
import '../features/settings/webdav_settings_page.dart';
import '../features/shared/comments_page.dart';
import '../features/stats/stats_page.dart';
import '../features/video/cast_receiver_page.dart';
import '../features/video/video_page.dart';
import '../features/video/tag_editor_page.dart';

class AppRouter {
  AppRouter(AppExitCoordinator exitCoordinator) {
    router = GoRouter(
      navigatorKey: navigatorKey,
      observers: [routeObserver],
      redirect: (context, state) => _deepLinkRedirect(state),
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShell(
            navigationShell: navigationShell,
            exitCoordinator: exitCoordinator,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const ExplorePage(),
                  // 这些页面挂在本分支下，使其在侧栏内侧展开（常驻侧栏不会消失）。
                  // 子路径与父路径拼接后仍是 /check-in、/previews/...、/search、/mine ，URL 不变。
                  routes: [
                    GoRoute(
                      path: 'check-in',
                      builder: (context, state) => const CheckInPage(),
                    ),
                    GoRoute(
                      path: 'previews/getchu/detail/:id',
                      builder: (context, state) => GetchuPreviewDetailPage(
                        id: state.pathParameters['id']!,
                      ),
                    ),
                    GoRoute(
                      path: 'previews/getchu/:month',
                      builder: (context, state) => GetchuPreviewPage(
                        month: state.pathParameters['month']!,
                      ),
                    ),
                    GoRoute(
                      path: 'previews/:month',
                      builder: (context, state) =>
                          PreviewsPage(month: state.pathParameters['month']!),
                    ),
                    // 搜索页挂在**根导航器**上（全屏）：它会被视频页这类顶层全屏页面打开，
                    // 而从顶层 push 一个 shell 分支内的路由时 go_router 不会构建页面
                    // （实测连 builder 都不会被调用）。挂在根上与当前栈无关，返回也能回到原页面。
                    GoRoute(
                      path: 'search',
                      parentNavigatorKey: navigatorKey,
                      builder: searchRouteBuilder,
                    ),
                    GoRoute(
                      path: 'mine',
                      builder: (context, state) => const AccountPage(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/library',
                  builder: (context, state) => const LibraryPage(),
                  routes: [
                    GoRoute(
                      path: ':tab',
                      builder: (context, state) {
                        final tab = _libraryTab(state.pathParameters['tab']);
                        return LibraryPage(key: ValueKey(tab), initialTab: tab);
                      },
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/cache',
                  builder: (context, state) => const CachePage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsPage(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/login/cookies',
          builder: (context, state) => const ManualCookiePage(),
        ),
        GoRoute(
          path: '/account/profile/:id',
          builder: (context, state) => AccountWebPage(
            path: '/user/${state.pathParameters['id']!}/edit',
            title: AppLocalizations.of(context)!.accountProfile,
          ),
        ),
        // 从视频页（根导航器上的全屏页）打开缓存页时的入口。
        //
        // /cache 本身是 shell 分支路由；从顶层的视频页 `push('/cache')` 虽然能构建
        // 页面，但它挂在 shell 分支下，返回语义不清（实测 pop 回不到视频页）。
        // 这里给一个**挂根导航器**的独立路径，和 /search 同一套办法：
        // 与当前栈无关，push 进来、返回就能回到正在看的视频。
        GoRoute(
          path: '/downloads',
          parentNavigatorKey: navigatorKey,
          builder: (context, state) => const CachePage(),
        ),
        GoRoute(
          path: '/settings/about',
          builder: (context, state) => const AboutPage(),
        ),
        GoRoute(
          path: '/settings/license',
          builder: (context, state) => const AppLicensePage(),
        ),
        GoRoute(
          path: '/settings/keyframes',
          builder: (context, state) => const KeyframesPage(),
        ),
        GoRoute(
          path: '/settings/playback',
          builder: (context, state) => const PlaybackSettingsPage(),
        ),
        GoRoute(
          path: '/settings/hotkeys',
          builder: (context, state) => const HotkeySettingsPage(),
        ),
        GoRoute(
          path: '/settings/player',
          builder: (context, state) => const PlayerSettingsPage(),
        ),
        GoRoute(
          path: '/settings/comments',
          builder: (context, state) => const CommentSettingsPage(),
        ),
        GoRoute(
          path: '/settings/comments/users',
          builder: (context, state) => const CommentUserFilterPage(),
        ),
        GoRoute(
          path: '/settings/theme',
          builder: (context, state) => const ThemeSettingsPage(),
        ),
        GoRoute(
          path: '/settings/layout',
          builder: (context, state) => const LayoutSettingsPage(),
        ),
        GoRoute(
          path: '/settings/layout/home-categories',
          builder: (context, state) => const HomeCategoriesPage(),
        ),
        GoRoute(
          path: '/settings/network',
          builder: (context, state) => const NetworkSettingsPage(),
        ),
        GoRoute(
          path: '/settings/network/diagnostics',
          builder: (context, state) => const SiteDiagnosticsPage(),
        ),
        GoRoute(
          path: '/settings/recommendations',
          builder: (context, state) => const RecommendationSettingsPage(),
        ),
        GoRoute(
          path: '/settings/recommendations/titles',
          builder: (context, state) => const VideoTitleFilterPage(),
        ),
        GoRoute(
          path: '/settings/recommendations/authors',
          builder: (context, state) => const AuthorFilterPage(),
        ),
        GoRoute(
          path: '/settings/webdav',
          builder: (context, state) => const WebDavSettingsPage(),
        ),
        GoRoute(
          path: '/settings/webdav/configuration',
          builder: (context, state) => const WebDavConfigurationPage(),
        ),
        GoRoute(
          path: '/settings/storage',
          builder: (context, state) => const StorageSettingsPage(),
        ),
        GoRoute(
          path: '/settings/storage/backup',
          builder: (context, state) => const BackupSettingsPage(),
        ),
        GoRoute(
          path: '/settings/language',
          builder: (context, state) => const LanguageSettingsPage(),
        ),
        GoRoute(
          path: '/cloudflare',
          builder: (context, state) =>
              CloudflarePage(initialUrl: state.extra as String?),
        ),
        GoRoute(
          path: '/comments/:type/:id',
          builder: (context, state) => CommentsPage(
            id: state.pathParameters['id']!,
            type: state.pathParameters['type']!,
            title: state.extra as String? ?? '',
          ),
        ),
        GoRoute(path: '/stats', builder: (context, state) => const StatsPage()),
        GoRoute(
          path: '/video/:id/tags/:mode',
          builder: (context, state) => TagEditorPage(
            videoId: state.pathParameters['id']!,
            mode: state.pathParameters['mode'] == 'remove'
                ? TagEditorMode.remove
                : TagEditorMode.add,
          ),
        ),
        GoRoute(
          path: '/video/:id',
          builder: (context, state) => VideoPage(
            id: state.pathParameters['id']!,
            localVideo: state.extra as VideoDetail?,
          ),
        ),
        GoRoute(
          path: '/local-media',
          builder: (context, state) => const LocalMediaPage(),
        ),
        // 投屏接收页：手机推片时从根导航器上打开，返回即回到原来的页面。
        GoRoute(
          path: '/cast',
          parentNavigatorKey: navigatorKey,
          builder: (context, state) =>
              CastReceiverPage(item: state.extra as CastMediaItem?),
        ),
        GoRoute(
          path: '/comics/browse',
          builder: (context, state) => ComicBrowsePage(
            target:
                state.extra as ComicBrowseTarget? ??
                const ComicBrowseTarget('/comics'),
          ),
        ),
        GoRoute(
          path: '/comics/:id/read',
          builder: (context, state) =>
              ComicReaderPage(comic: state.extra! as ComicDetail),
        ),
        GoRoute(
          path: '/comics/:id',
          builder: (context, state) =>
              ComicDetailPage(id: state.pathParameters['id']!),
        ),
      ],
    );
  }

  final navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter router;

  void dispose() {
    router.dispose();
  }
}

/// 搜索页的构造：优先用调用方传入的查询条件，其次解析 URL（深链或外部打开）。
///
/// 公开给独立播放窗口的精简路由复用（播放页里的作者 / 标签会 push 搜索页）。
Widget searchRouteBuilder(BuildContext context, GoRouterState state) {
  final extra = state.extra;
  final request = extra is SearchRouteRequest
      ? extra
      : SearchRouteRequest.fromRoute(
          state.pageKey.value.toString(),
          initialUrl: extra is String
              ? extra
              : (state.uri.hasQuery ? state.uri.toString() : null),
        );
  return SearchPage(key: ValueKey(request.sessionId), request: request);
}

String? _deepLinkRedirect(GoRouterState state) {
  final uri = state.uri;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  const hosts = {'hanime1.com', 'hanimeone.me', 'hanime1.me'};
  if (!hosts.contains(uri.host)) return null;
  final videoId = uri.queryParameters['v'];
  if (videoId != null && uri.path.contains('watch')) return '/video/$videoId';
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length >= 3 &&
      segments[0] == 'videos' &&
      segments[1] == 'hentai')
    return '/video/${segments[2]}';
  if (uri.path.contains('search')) return '/search';
  return null;
}

int _libraryTab(String? tab) => switch (tab) {
  'watch-later' => 0,
  'favorites' => 1,
  'playlists' => 2,
  'subscriptions' => 3,
  'history' => 4,
  _ => 0,
};
