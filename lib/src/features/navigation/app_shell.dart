import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_shell.dart';
import '../../core/platform_service.dart';
import '../../domain/models/account.dart';
import '../account/account_controller.dart';
import '../comics/comic_pages.dart';
import '../settings/settings_controller.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import 'exit_coordinator.dart';
import 'shell_destination.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.exitCoordinator,
  });

  final StatefulNavigationShell navigationShell;
  final AppExitCoordinator exitCoordinator;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late final List<int> _branchHistory;

  /// 切换侧栏分栏（首页/清单/缓存/设置）时让内容区整体淡入；侧栏本身不参与动画。
  late final AnimationController _branchSwitch;
  var _isBackNavigation = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell.currentIndex;
    _branchHistory = <int>[widget.navigationShell.currentIndex];
    _branchSwitch = AnimationController(
      vsync: this,
      duration: AppMotion.emphasis,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = widget.navigationShell.currentIndex;
    if (nextIndex == _currentIndex) return;
    if (_isBackNavigation) {
      if (_branchHistory.isNotEmpty) _branchHistory.removeLast();
      _isBackNavigation = false;
      widget.exitCoordinator.clearBranchBackHandled();
    } else {
      _branchHistory.remove(nextIndex);
      _branchHistory.add(nextIndex);
      if (_branchHistory.length > 4) _branchHistory.removeAt(0);
    }
    _currentIndex = nextIndex;
    _branchSwitch.forward(from: 0);
  }

  @override
  void dispose() {
    _branchSwitch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final comicMode = settings?.comicMode ?? false;
    // 导航形态固定：大屏（最短边 ≥600）常驻窄侧栏，窄屏用抽屉 —— 这是唯一的
    // 两种形态，原来那个「使用导航抽屉 / NavigationRail / 底部导航栏」三态开关已删除。
    final largeScreen = MediaQuery.sizeOf(context).shortestSide >= 600;
    final content = comicMode
        ? switch (widget.navigationShell.currentIndex) {
            0 => const ComicExplorePage(),
            1 => ComicLibraryPage(
              initialTab: _libraryTab(
                GoRouterState.of(context).pathParameters['tab'],
              ),
            ),
            2 => const ComicCachePage(),
            _ => widget.navigationShell,
          }
        : widget.navigationShell;
    final mediaQuery = MediaQuery.of(context);
    // 分栏切换时整块内容淡入（含漫画模式的四个根页）。
    final animatedContent = FadeTransition(
      opacity: CurvedAnimation(parent: _branchSwitch, curve: AppMotion.settle),
      child: content,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleRootBack(context);
      },
      child: Scaffold(
        key: appShellScaffoldKey,
        // 页面底统一是设计稿的 #F4F4F7：侧栏是纯白，内容区是浅灰，
        // 白卡压在浅灰上才有层次。原来透的是主题 surface，
        // 换成粉色/蓝色主题时整块底会泛色，白卡和底色就分不开了。
        backgroundColor: AppDesignTokens.pageBackgroundOf(context),
        drawer: largeScreen
            ? null
            : _AppDrawer(navigationShell: widget.navigationShell),
        body: largeScreen
            ? Row(
                children: [
                  AppDesktopSidebar(navigationShell: widget.navigationShell),
                  Expanded(child: animatedContent),
                ],
              )
            : MediaQuery(data: mediaQuery, child: animatedContent),
      ),
    );
  }

  Future<void> _handleRootBack(BuildContext context) async {
    if (_branchHistory.length > 1) {
      _isBackNavigation = true;
      widget.exitCoordinator.markBranchBackHandled();
      widget.navigationShell.goBranch(
        _branchHistory[_branchHistory.length - 2],
      );
      return;
    }
    if (!await widget.exitCoordinator.confirmExit(context)) return;
    if (PlatformService.isDesktop) {
      try {
        await SystemNavigator.pop();
      } catch (_) {}
      return;
    }
    await PlatformService.minimizeApp();
  }
}

int _libraryTab(String? tab) => switch (tab) {
  'watch-later' => 0,
  'favorites' => 1,
  'playlists' => 2,
  'subscriptions' => 3,
  'history' => 4,
  _ => 0,
};

/// 抽屉里的一个分组：标题为空表示顶部的「主项」区（不显示标题）。
class _DrawerSection {
  const _DrawerSection({this.title, required this.items});

  final String? title;
  final List<_DrawerItem> items;
}

/// 侧边栏结构（参考移动端分支的分组）：主项 → 我的清单 → 影片。
List<_DrawerSection> _drawerSections(
  BuildContext context, {
  bool comicMode = false,
  String previewSource = 'auto',
}) {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final month =
      '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';
  // 「新番」直接进用户选定的数据源：默认站点那张预告表常年不可用，别再让入口落在它上面。
  final previewsLocation = previewSource == 'getchu'
      ? '/previews/getchu/$month'
      : '/previews/$month';
  return [
    _DrawerSection(
      items: [
        _DrawerItem(
          icon: Symbols.home_rounded,
          selectedIcon: Symbols.home_rounded,
          label: l10n.home,
          location: '/',
        ),
        _DrawerItem(
          icon: Symbols.calendar_month_rounded,
          selectedIcon: Symbols.calendar_month_rounded,
          label: l10n.previews,
          shortLabel: l10n.railPreviews,
          location: previewsLocation,
        ),
        _DrawerItem(
          icon: Symbols.thumb_up_rounded,
          selectedIcon: Symbols.thumb_up_rounded,
          label: l10n.checkIn,
          location: '/check-in',
        ),
      ],
    ),
    _DrawerSection(
      title: l10n.myListSection,
      items: [
        _DrawerItem(
          icon: Symbols.watch_later_rounded,
          selectedIcon: Symbols.watch_later_rounded,
          label: l10n.watchLater,
          shortLabel: l10n.railWatchLater,
          location: '/library/watch-later',
        ),
        _DrawerItem(
          icon: Symbols.favorite_rounded,
          selectedIcon: Symbols.favorite_rounded,
          label: l10n.favoriteVideos,
          shortLabel: l10n.railFavorites,
          location: '/library/favorites',
        ),
        if (!comicMode) ...[
          _DrawerItem(
            icon: Symbols.playlist_play_rounded,
            selectedIcon: Symbols.playlist_play_rounded,
            label: l10n.playlists,
            shortLabel: l10n.railPlaylists,
            location: '/library/playlists',
          ),
          _DrawerItem(
            icon: Symbols.subscriptions_rounded,
            selectedIcon: Symbols.subscriptions_rounded,
            label: l10n.subscriptions,
            shortLabel: l10n.railSubscriptions,
            location: '/library/subscriptions',
          ),
        ],
      ],
    ),
    _DrawerSection(
      title: l10n.videoSection,
      items: [
        if (!comicMode)
          _DrawerItem(
            icon: Symbols.history_rounded,
            selectedIcon: Symbols.history_rounded,
            label: l10n.watchHistory,
            shortLabel: l10n.railHistory,
            location: '/library/history',
            iconOnly: true,
          ),
        _DrawerItem(
          icon: Symbols.download_for_offline_rounded,
          selectedIcon: Symbols.download_for_offline_rounded,
          label: l10n.download,
          location: '/cache',
          iconOnly: true,
        ),
        _DrawerItem(
          icon: Symbols.settings_rounded,
          selectedIcon: Symbols.settings_rounded,
          label: l10n.settings,
          location: '/settings',
          iconOnly: true,
        ),
      ],
    ),
  ];
}

/// 所有目的地（把分组压平，供选中下标与点击使用）。
List<_DrawerItem> _drawerDestinations(List<_DrawerSection> sections) => [
  for (final section in sections) ...section.items,
];

/// 分组标题（与设置页列表的标题保持一致的视觉）。
Widget _drawerSectionTitle(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
  child: Text(
    title,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    ),
  ),
);

/// 打开抽屉项对应的页面（分支页切分支，其余 go）。
void _openDrawerLocation(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  String location,
) => openShellDestination(context, navigationShell, location);

int _selectedDrawerIndex(BuildContext context, List<_DrawerItem> items) {
  final path = GoRouterState.of(context).uri.path;
  return items.indexWhere((item) => item.location == path);
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).valueOrNull;
    final comicMode =
        ref.watch(settingsProvider).valueOrNull?.comicMode ?? false;
    final sections = _drawerSections(
      context,
      comicMode: comicMode,
      previewSource:
          ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto',
    );
    final destinations = _drawerDestinations(sections);
    final selectedIndex = _selectedDrawerIndex(context, destinations);
    return NavigationDrawer(
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      onDestinationSelected: (index) =>
          _go(context, destinations[index].location),
      children: [
        _DrawerAccountCard(
          account: account,
          onTap: () {
            Navigator.pop(context);
            context.push('/mine');
          },
        ),
        const SizedBox(height: 12),
        for (final section in sections) ...[
          if (section.title != null)
            _drawerSectionTitle(context, section.title!),
          for (final item in section.items)
            NavigationDrawerDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon, fill: 1),
              label: Text(item.label),
            ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  void _go(BuildContext context, String location) {
    final current = GoRouterState.of(context).uri.path;
    Navigator.pop(context);
    if (current == location) return;
    _openDrawerLocation(context, navigationShell, location);
  }
}

class _DrawerItem {
  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.shortLabel,
    required this.location,
    this.iconOnly = false,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// 宽抽屉/抽屉模式下的完整文案。
  final String label;

  /// 窄侧栏（图标 + 文字上下排）用的精简文案；为空时用 [label]。
  final String? shortLabel;

  /// 窄侧栏里只显示图标、不显示文字（底部的历史/下载/设置用）。
  final bool iconOnly;

  final String location;
}

class _DrawerAccountCard extends StatelessWidget {
  const _DrawerAccountCard({
    this.account,
    required this.onTap,
    this.compact = false,
  });

  final Account? account;
  final VoidCallback onTap;

  /// 桌面常驻侧栏用紧凑版（v6 设计稿：144×56 的一行，头像 32）。
  ///
  /// 抽屉里仍然用大卡：抽屉是整屏浮层，卡片做小了反而显得空。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loggedIn = account != null;
    final textTheme = Theme.of(context).textTheme;
    final hasAvatar = account?.avatarUrl?.isNotEmpty == true;
    return Padding(
      // 侧栏（compact）的位置完全由调用处给：设计稿账号卡是 144×56、落在
      // (16,724)，卡外上下留白都有讲究，这里再叠一层内边距就会把卡挤窄、
      // 把底部那块往上顶（实测卡从 144 宽被压成 112，底部多出 16）。
      // 抽屉里那张仍是大卡（整屏浮层，做小了显空），用 8 的边距。
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        // Card 自带 4 的 margin，会把设计稿的刻度整体推 4 —— 位置由外面给，这里清零。
        margin: EdgeInsets.zero,
        // 设计稿的账号卡是 144×56：**#F6F6F9 的浅灰底、圆角 10、没有描边**。
        // 之前用的是白底 + 1px 描边，于是它和侧栏的白糊成一片，只剩下一条细线，
        // 看着像「多出来一条分割线」，不像一张卡。
        color: compact
            ? AppDesignTokens.accountCardFillOf(context)
            : AppDesignTokens.surfaceOf(context),
        elevation: compact ? 0 : null,
        shape: compact
            ? RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.sm))
            : null,
        child: PressScale(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              // 设计稿：头像 32 落在 x=28（卡内 12），名字 x=70（卡内 54）。
              padding: EdgeInsets.all(compact ? 12 : 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: compact ? 16 : 28,
                    backgroundImage: hasAvatar
                        ? appNetworkImage(account!.avatarUrl!)
                        : null,
                    child: hasAvatar
                        ? null
                        : Icon(Symbols.person_rounded, size: compact ? 18 : 30),
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          account?.name?.isNotEmpty == true
                              ? account!.name!
                              : loggedIn
                              ? l10n.signedIn
                              : l10n.signedOut,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: compact
                              // 行高收紧到 1.2：设计稿这张卡是定高 56，名字 + 间距 +
                              // 账号两行加起来要落在头像那 32 里；按默认行高算是 34，
                              // 卡就会被撑到 58，底部整块跟着往上挤。
                              ? TextStyle(
                                  fontSize: 12,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: AppDesignTokens.inkOf(context),
                                )
                              : textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          loggedIn ? '@${account!.id}' : l10n.tapToLogin,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: compact
                              ? TextStyle(
                                  fontSize: 10.5,
                                  height: 1.2,
                                  color: AppDesignTokens.inkMutedOf(context),
                                )
                              : textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端常驻宽侧栏（v6 设计稿样式）：分组标题 + 图标文字项 + 底部账号卡。
/// 桌面端常驻侧栏。
///
/// 导出成公开组件是为了让**搜索页**也能用：设计稿里搜索页左侧同样是这条
/// 常驻侧栏（`base_search.png` / `base_category_hentai.png` 两张都画了），
/// 而搜索页挂在根导航器上（它会被视频页这类全屏页 push），拿不到
/// [StatefulNavigationShell]，所以这里把 navigationShell 改成可选：
/// 给了就走分支跳转（保留各分支的滚动状态），没给就退化成普通的 `context.go`。
class AppDesktopSidebar extends ConsumerWidget {
  const AppDesktopSidebar({super.key, this.navigationShell});

  final StatefulNavigationShell? navigationShell;

  static const double width = AppDesignTokens.sidebarWidth;

  /// 侧栏项是不是当前页。
  ///
  /// 不能拿 `item.location == uri.path` 直接比：「里番 / 泡面番」这两项的位置是
  /// `/search?genre=里番`，而搜索页的 path 只有 `/search`，比出来永远不相等 ——
  /// 于是点进分类页后侧栏一个高亮都没有。这里按「path 相同 + 声明的 query 都对上」判。
  ///
  /// query 也不能拿整串比：中文会被 URL 编码成 `%E9%87%8C%E7%95%AA`，
  /// 和写在代码里的「里番」永远不等，得走 `queryParameters` 解码后的值。
  static bool _isSelected(Uri? current, String location) {
    if (current == null) return false;
    final target = Uri.parse(location);
    if (target.path != current.path) return false;
    for (final entry in target.queryParameters.entries) {
      if (current.queryParameters[entry.key] != entry.value) return false;
    }
    // 目标没声明 query 时，当前页也不该带别的筛选（例如从 /search?genre=里番
    // 回首页后，`/` 才是选中项，`/search` 不是）。
    if (target.queryParameters.isEmpty && current.queryParameters.isNotEmpty) {
      return false;
    }
    return true;
  }

  /// 侧栏项跳转：有 shell 就走分支跳转，没有（搜索页）就普通 go。
  void _navigate(BuildContext context, String location) {
    // 位置串里带中文（`/search?genre=泡面番`）：先过一遍 Uri 让它们被百分号编码，
    // 否则个别路径解析会把它当成非法字符，跳转直接不生效。
    final target = Uri.parse(location).toString();
    final shell = navigationShell;
    if (shell == null) {
      context.go(target);
      return;
    }
    _openDrawerLocation(context, shell, location);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).valueOrNull;
    // 用 maybeOf 而不是 of：搜索页复用这条侧栏时，有些宿主（widget 测试、
    // 独立预览）没有挂 GoRouter，`GoRouterState.of` 会直接抛 GoError 把整棵树带崩。
    final uri = GoRouter.maybeOf(
      context,
    )?.routerDelegate.currentConfiguration.uri;
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';
    final previewSource =
        ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto';
    final previewsLocation = previewSource == 'getchu'
        ? '/previews/getchu/$month'
        : '/previews/$month';
    // v6 设计稿：顶部 logo，中间两组导航（组间一条细线），底部「设置」+ 账号卡。
    // 「设置」单独拆出来是因为它在设计稿里被压在底部，不跟着上面两组滚。
    final navGroups = <List<_DrawerItem>>[
      [
        _DrawerItem(
          icon: Symbols.home_rounded,
          selectedIcon: Symbols.home_rounded,
          label: AppLocalizations.of(context)!.home,
          location: '/',
        ),
        // 侧栏文案按 v6 设计稿取短名「新番」；l10n.previews 仍是「新番预告」，
        // 预告页的标题 / 评论页 extra 继续用它，这里只在侧栏这一处改叫法。
        _DrawerItem(
          icon: Symbols.calendar_month_rounded,
          selectedIcon: Symbols.calendar_month_rounded,
          label: '新番',
          location: previewsLocation,
        ),
        _DrawerItem(
          icon: Symbols.movie_rounded,
          selectedIcon: Symbols.movie_rounded,
          label: '里番',
          location: '/search?genre=里番',
        ),
        _DrawerItem(
          icon: Symbols.ramen_dining_rounded,
          selectedIcon: Symbols.ramen_dining_rounded,
          label: '泡面番',
          location: '/search?genre=泡面番',
        ),
      ],
      [
        _DrawerItem(
          icon: Symbols.favorite_rounded,
          selectedIcon: Symbols.favorite_rounded,
          label: '关注',
          location: '/library/subscriptions',
        ),
        _DrawerItem(
          icon: Symbols.history_rounded,
          selectedIcon: Symbols.history_rounded,
          label: AppLocalizations.of(context)!.watchHistory,
          location: '/library/history',
        ),
        _DrawerItem(
          icon: Symbols.download_for_offline_rounded,
          selectedIcon: Symbols.download_for_offline_rounded,
          label: '缓存',
          location: '/cache',
        ),
        // 侧栏文案按 v6 设计稿：「签到」（l10n.checkIn 仍是「冲了么」，签到页标题继续用它）。
        _DrawerItem(
          icon: Symbols.thumb_up_rounded,
          selectedIcon: Symbols.thumb_up_rounded,
          label: '签到',
          location: '/check-in',
        ),
      ],
    ];
    final footerGroup = <_DrawerItem>[
      _DrawerItem(
        icon: Symbols.settings_rounded,
        selectedIcon: Symbols.settings_rounded,
        label: AppLocalizations.of(context)!.settings,
        location: '/settings',
      ),
    ];
    return Container(
      width: width,
      // 侧栏是设计稿里唯一一块纯白面板，右边那条 1px 把它和 #F4F4F7 的页面底分开。
      // 原来这里不铺底、靠外面的 Scaffold 底色透上来，换成浅灰页面底之后侧栏就
      // 和白卡糊成一片了。
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceOf(context),
        border: Border(right: BorderSide(color: AppDesignTokens.dividerOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部的品牌锁标。
          //
          // 设计稿（`home_v5_base.png` 实测）里粉色标是 32×28、落在 (18,10)，
          // 字标右端到 x=157 —— 整枚锁标 140 宽、28 高，长宽比 5.0。
          // 这正好是 `logo_lockup.svg`（1286×254）的比例，所以这里用**完整版**
          // 而不是 `logo_lockup_compact.svg`（1161×159，比例 7.3）：紧凑版按 24 高
          // 渲染出来有 175 宽，比侧栏留白还宽，会被压扁成 148×20 的一小条。
          //
          // 这块占 y 0~52（上 9 + 28 + 下 15），于是第一项导航的选中底正好从
          // y=61 开始，与设计稿 navBg/home 的 61..94 对上。
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 9, 18, 15),
            child: SizedBox(
              height: 28,
              child: SvgPicture.asset(
                'assets/logo_lockup.svg',
                width: 140,
                fit: BoxFit.contain,
                semanticsLabel: AppLocalizations.of(context)!.appTitle,
              ),
            ),
          ),
          // 导航区（可滚动）。设计稿的行距是 52：条目自己上下各留 9，
          // 中间那块 34 才是选中底的高度（navBg/home 实测 61..94）。
          Expanded(
            child: ListView(
              // 横向不再留内边距：条目自己左右各留 16，选中底因此是 144 宽、
              // 起点 x=16。列表再留一圈的话，图标会从设计稿的 x=28 漂到 x=40。
              padding: EdgeInsets.zero,
              children: [
                for (var g = 0; g < navGroups.length; g++) ...[
                  if (g > 0) const _SidebarGroupDivider(top: 17, bottom: 11),
                  for (final item in navGroups[g])
                    _SidebarItem(
                      item: item,
                      selected: _isSelected(uri, item.location),
                      onTap: () => _navigate(context, item.location),
                    ),
                ],
              ],
            ),
          ),
          // 底部固定块：细线 + 设置 + 账号卡。
          //
          // 设计稿里「设置」不是一个普通分组：它被一条细线（y=623）压在底部，
          // 上面那半个侧栏是弹性的（窗口变高时先撑开这一段），所以不能把它塞进
          // 上面那个可滚动的列表里 —— 那样它就会紧贴着「签到」，位置全乱。
          const _SidebarGroupDivider(top: 0, bottom: 10),
          for (final item in footerGroup)
            _SidebarItem(
              item: item,
              selected: _isSelected(uri, item.location),
              onTap: () => _navigate(context, item.location),
            ),
          Padding(
            // 设计稿账号卡：144×56，落在 y 724..779，卡底到侧栏底还有 20。
            // 上边距 39 是「设置」那一行（选中底 34 + 上下各 9）之后到卡的距离。
            padding: const EdgeInsets.fromLTRB(16, 39, 16, 20),
            child: _DrawerAccountCard(
              account: account,
              compact: true,
              onTap: () => context.push('/mine'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _DrawerItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 选中态按设计稿：底是一层 8% 的胭脂粉，文字与图标是再暗一档的 #B3265A。
    // 不再用 secondaryContainer / onSecondaryContainer —— 那一对跟着主题色种子走，
    // 用户换成蓝色主题时侧栏就还原不出设计稿的粉，而侧栏是设计稿的基准面。
    // 选中态用主题色（用户选的配色，见 `AppDesignTokens.accentOf`）。
    // 设计稿截图里是胭脂粉，那是因为设计稿画的是「玫瑰」这套配色 —— 粉不是写死的值。
    final foreground = selected
        ? AppDesignTokens.accentOf(context)
        : AppDesignTokens.inkSubtleOf(context);
    return Padding(
      // 行距 52 = 上 9 + 选中底 34 + 下 9；左右各 16 让选中底正好 144 宽、起点 x=16，
      // 与设计稿 navBg/home（61..94、16..159）逐像素对齐。
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: AppDesignTokens.sidebarItemInsetY,
      ),
      child: PressScale(
        child: Material(
          // 材质只负责承载水波纹，底色由里面的 Container 画：
          // Container 有确定高度、宽度跟父级走，选中底不会因为拿不到约束而塌掉。
          type: MaterialType.transparency,
          borderRadius: AppRadius.all(AppRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: AppRadius.all(AppRadius.sm),
            onTap: onTap,
            child: Container(
              // 选中底的高度是 34，不是 44 —— 设计稿在 52 的行距里上下各留 9。
              height: AppDesignTokens.sidebarItemHeight,
              decoration: BoxDecoration(
                // 选中底：主题色压到 8%，与选中文字同色系，跟随用户选的配色。
                color: selected
                    ? AppDesignTokens.accentOf(context).withValues(alpha: .08)
                    : Colors.transparent,
                borderRadius: AppRadius.all(AppRadius.sm),
              ),
              // 设计稿：图标 x=28、文字 x=56。卡片起点 16 + 内部左 12 = 28；
              // 图标 18 宽 + 间距 10 = 文字 x=56。
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: AppDesignTokens.sidebarIconSize,
                    color: foreground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        // 设计稿的导航文字是 13 号（`navText/home` fontSize 13）。
                        fontSize: AppDesignTokens.sidebarLabelSize,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏分组之间的细线：144 宽、左起 16、1px。
///
/// 上下留白要分开给：设计稿第一组之后是「上 17 / 下 11」——下 11 让下一组的
/// 选中底仍然落在 52 的节拍上；底部那条细线上面是弹性空白，所以上边距给 0。
class _SidebarGroupDivider extends StatelessWidget {
  const _SidebarGroupDivider({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, bottom),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppDesignTokens.dividerOf(context),
      ),
    );
  }
}
