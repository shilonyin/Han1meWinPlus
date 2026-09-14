import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_shell.dart';
import '../../core/platform_service.dart';
import '../../domain/models/account.dart';
import '../account/account_controller.dart';
import '../comics/comic_pages.dart';
import '../settings/settings_controller.dart';
import 'exit_coordinator.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell, required this.exitCoordinator});

  final StatefulNavigationShell navigationShell;
  final AppExitCoordinator exitCoordinator;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late int _currentIndex;
  late final List<int> _branchHistory;
  var _isBackNavigation = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell.currentIndex;
    _branchHistory = <int>[widget.navigationShell.currentIndex];
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
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final comicMode = settings?.comicMode ?? false;
    final drawerMode = settings?.useNavigationDrawer ?? false;
    final largeScreen = MediaQuery.sizeOf(context).shortestSide >= 600;
    final permanentDrawer = drawerMode && largeScreen;
    final useRail = !drawerMode && largeScreen;
    final destinations = [
      (icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: AppLocalizations.of(context)!.explore),
      (icon: Icons.bookmark_outline, selectedIcon: Icons.bookmark, label: AppLocalizations.of(context)!.library),
      (icon: Icons.download_outlined, selectedIcon: Icons.download, label: AppLocalizations.of(context)!.cache),
      (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: AppLocalizations.of(context)!.settings),
    ];
    void select(int index) => widget.navigationShell.goBranch(index, initialLocation: index == widget.navigationShell.currentIndex);
    final content = comicMode
        ? switch (widget.navigationShell.currentIndex) {
            0 => const ComicExplorePage(),
            1 => ComicLibraryPage(initialTab: _libraryTab(GoRouterState.of(context).pathParameters['tab']), drawerMode: drawerMode),
            2 => const ComicCachePage(),
            _ => widget.navigationShell,
          }
        : widget.navigationShell;
    final mediaQuery = MediaQuery.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleRootBack(context);
      },
      child: Scaffold(
        key: drawerMode ? appShellScaffoldKey : null,
        drawer: drawerMode && !permanentDrawer ? _AppDrawer(navigationShell: widget.navigationShell) : null,
        body: permanentDrawer
            ? Row(
                children: [
                  _PermanentNavigationDrawer(navigationShell: widget.navigationShell),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : useRail
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: widget.navigationShell.currentIndex,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: select,
                        destinations: destinations.map((destination) => NavigationRailDestination(icon: Icon(destination.icon), selectedIcon: Icon(destination.selectedIcon), label: Text(destination.label))).toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : MediaQuery(data: mediaQuery, child: content),
        bottomNavigationBar: drawerMode || useRail
            ? null
            : NavigationBar(
                selectedIndex: widget.navigationShell.currentIndex,
                onDestinationSelected: select,
                destinations: destinations.map((destination) => NavigationDestination(icon: Icon(destination.icon), selectedIcon: Icon(destination.selectedIcon), label: destination.label)).toList(),
              ),
      ),
    );
  }

  Future<void> _handleRootBack(BuildContext context) async {
    if (_branchHistory.length > 1) {
      _isBackNavigation = true;
      widget.exitCoordinator.markBranchBackHandled();
      widget.navigationShell.goBranch(_branchHistory[_branchHistory.length - 2]);
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
List<_DrawerSection> _drawerSections(BuildContext context, {bool comicMode = false}) {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final month = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';
  return [
    _DrawerSection(items: [
      _DrawerItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: l10n.home, location: '/'),
      _DrawerItem(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: l10n.previews, location: '/previews/$month'),
      _DrawerItem(icon: Icons.thumb_up_alt_outlined, selectedIcon: Icons.thumb_up_alt, label: l10n.checkIn, location: '/check-in'),
      _DrawerItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: l10n.settings, location: '/settings'),
    ]),
    _DrawerSection(title: l10n.myListSection, items: [
      _DrawerItem(icon: Icons.watch_later_outlined, selectedIcon: Icons.watch_later, label: l10n.watchLater, location: '/library/watch-later'),
      _DrawerItem(icon: Icons.favorite_outline, selectedIcon: Icons.favorite, label: l10n.favoriteVideos, location: '/library/favorites'),
      if (!comicMode) ...[
        _DrawerItem(icon: Icons.playlist_play_outlined, selectedIcon: Icons.playlist_play, label: l10n.playlists, location: '/library/playlists'),
        _DrawerItem(icon: Icons.subscriptions_outlined, selectedIcon: Icons.subscriptions, label: l10n.subscriptions, location: '/library/subscriptions'),
      ],
    ]),
    _DrawerSection(title: l10n.videoSection, items: [
      if (!comicMode) _DrawerItem(icon: Icons.history_outlined, selectedIcon: Icons.history, label: l10n.watchHistory, location: '/library/history'),
      _DrawerItem(icon: Icons.download_outlined, selectedIcon: Icons.download, label: l10n.download, location: '/cache'),
    ]),
  ];
}

/// 所有目的地（把分组压平，供选中下标与点击使用）。
List<_DrawerItem> _drawerDestinations(List<_DrawerSection> sections) => [for (final section in sections) ...section.items];

/// 分组标题（与设置页列表的标题保持一致的视觉）。
Widget _drawerSectionTitle(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
    );

/// 打开抽屉项对应的页面（分支页切分支，其余 push）。
void _openDrawerLocation(BuildContext context, StatefulNavigationShell navigationShell, String location) {
  switch (location) {
    case '/':
      navigationShell.goBranch(0, initialLocation: navigationShell.currentIndex == 0);
    case '/settings':
      navigationShell.goBranch(3, initialLocation: navigationShell.currentIndex == 3);
    case '/cache':
      navigationShell.goBranch(2, initialLocation: navigationShell.currentIndex == 2);
    default:
      context.push(location);
  }
}

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
    final comicMode = ref.watch(settingsProvider).valueOrNull?.comicMode ?? false;
    final sections = _drawerSections(context, comicMode: comicMode);
    final destinations = _drawerDestinations(sections);
    final selectedIndex = _selectedDrawerIndex(context, destinations);
    return NavigationDrawer(
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      onDestinationSelected: (index) => _go(context, destinations[index].location),
      children: [
        _DrawerAccountCard(account: account, onTap: () {
          Navigator.pop(context);
          context.push('/mine');
        }),
        const SizedBox(height: 12),
        for (final section in sections) ...[
          if (section.title != null) _drawerSectionTitle(context, section.title!),
          for (final item in section.items) NavigationDrawerDestination(icon: Icon(item.icon), selectedIcon: Icon(item.selectedIcon), label: Text(item.label)),
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

class _PermanentNavigationDrawer extends ConsumerWidget {
  const _PermanentNavigationDrawer({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).valueOrNull;
    final comicMode = ref.watch(settingsProvider).valueOrNull?.comicMode ?? false;
    final sections = _drawerSections(context, comicMode: comicMode);
    final destinations = _drawerDestinations(sections);
    final selectedIndex = _selectedDrawerIndex(context, destinations);
    return SizedBox(
      width: 320,
      child: SafeArea(
        child: NavigationDrawer(
          selectedIndex: selectedIndex < 0 ? null : selectedIndex,
          onDestinationSelected: (index) => _openDrawerLocation(context, navigationShell, destinations[index].location),
          children: [
            _DrawerAccountCard(account: account, onTap: () => context.push('/mine')),
            const SizedBox(height: 12),
            for (final section in sections) ...[
              if (section.title != null) _drawerSectionTitle(context, section.title!),
              for (final item in section.items) NavigationDrawerDestination(icon: Icon(item.icon), selectedIcon: Icon(item.selectedIcon), label: Text(item.label)),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem {
  const _DrawerItem({required this.icon, required this.selectedIcon, required this.label, required this.location});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String location;
}

class _DrawerAccountCard extends StatelessWidget {
  const _DrawerAccountCard({this.account, required this.onTap});

  final Account? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loggedIn = account != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(radius: 28, backgroundImage: account?.avatarUrl?.isNotEmpty == true ? NetworkImage(account!.avatarUrl!) : null, child: account?.avatarUrl?.isNotEmpty == true ? null : Icon(loggedIn ? Icons.person : Icons.person_outline, size: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account?.name?.isNotEmpty == true ? account!.name! : loggedIn ? l10n.signedIn : l10n.signedOut, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(loggedIn ? '@${account!.id}' : l10n.tapToLogin, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}