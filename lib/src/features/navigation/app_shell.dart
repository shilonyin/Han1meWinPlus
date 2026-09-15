import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_shell.dart';
import '../../core/platform_service.dart';
import '../../core/settings.dart';
import '../../domain/models/account.dart';
import '../account/account_controller.dart';
import '../comics/comic_pages.dart';
import '../settings/settings_controller.dart';
import '../shared/app_image_cache.dart';
import '../shared/app_toast.dart';
import 'exit_coordinator.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell, required this.exitCoordinator});

  final StatefulNavigationShell navigationShell;
  final AppExitCoordinator exitCoordinator;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with SingleTickerProviderStateMixin {
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
    _branchSwitch = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);
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
    // 分栏切换时整块内容淡入（含漫画模式的四个根页）。
    final animatedContent = FadeTransition(opacity: CurvedAnimation(parent: _branchSwitch, curve: Curves.easeOutCubic), child: content);
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
                  _CompactNavigationRail(navigationShell: widget.navigationShell),
                  const VerticalDivider(width: 1),
                  Expanded(child: animatedContent),
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
                      Expanded(child: animatedContent),
                    ],
                  )
                : MediaQuery(data: mediaQuery, child: animatedContent),
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
List<_DrawerSection> _drawerSections(BuildContext context, {bool comicMode = false, String previewSource = 'auto'}) {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final month = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}';
  // 「新番」直接进用户选定的数据源：默认站点那张预告表常年不可用，别再让入口落在它上面。
  final previewsLocation = previewSource == 'getchu' ? '/previews/getchu/$month' : '/previews/$month';
  return [
    _DrawerSection(items: [
      _DrawerItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: l10n.home, location: '/'),
      _DrawerItem(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: l10n.previews, shortLabel: l10n.railPreviews, location: previewsLocation),
      _DrawerItem(icon: Icons.thumb_up_alt_outlined, selectedIcon: Icons.thumb_up_alt, label: l10n.checkIn, location: '/check-in'),
    ]),
    _DrawerSection(title: l10n.myListSection, items: [
      _DrawerItem(icon: Icons.watch_later_outlined, selectedIcon: Icons.watch_later, label: l10n.watchLater, shortLabel: l10n.railWatchLater, location: '/library/watch-later'),
      _DrawerItem(icon: Icons.favorite_outline, selectedIcon: Icons.favorite, label: l10n.favoriteVideos, shortLabel: l10n.railFavorites, location: '/library/favorites'),
      if (!comicMode) ...[
        _DrawerItem(icon: Icons.playlist_play_outlined, selectedIcon: Icons.playlist_play, label: l10n.playlists, shortLabel: l10n.railPlaylists, location: '/library/playlists'),
        _DrawerItem(icon: Icons.subscriptions_outlined, selectedIcon: Icons.subscriptions, label: l10n.subscriptions, shortLabel: l10n.railSubscriptions, location: '/library/subscriptions'),
      ],
    ]),
    _DrawerSection(title: l10n.videoSection, items: [
      if (!comicMode) _DrawerItem(icon: Icons.history_outlined, selectedIcon: Icons.history, label: l10n.watchHistory, shortLabel: l10n.railHistory, location: '/library/history', iconOnly: true),
      _DrawerItem(icon: Icons.download_outlined, selectedIcon: Icons.download, label: l10n.download, location: '/cache', iconOnly: true),
      _DrawerItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: l10n.settings, location: '/settings', iconOnly: true),
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
    final sections = _drawerSections(context, comicMode: comicMode, previewSource: ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto');
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

/// 桌面端的常驻窄侧栏（b 站风格）：宽度固定 88，图标 + 短标签上下排，分组之间用分隔线。
///
/// 用自绘而不是 [NavigationDrawer]，是因为抽屉的展开宽度（320）在桌面上太占地方，
/// 而 [NavigationRail] 又不支持分组与“非分支页面”的选中态。
class _CompactNavigationRail extends ConsumerWidget {
  const _CompactNavigationRail({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 图标 + 两三个汉字宽度，恰好放得下精简后的标签。
  static const double railWidth = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).valueOrNull;
    final comicMode = ref.watch(settingsProvider).valueOrNull?.comicMode ?? false;
    final sections = _drawerSections(context, comicMode: comicMode, previewSource: ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto');
    final path = GoRouterState.of(context).uri.path;
    final loggedIn = account != null;
    final hasAvatar = account?.avatarUrl?.isNotEmpty == true;
    final items = _drawerDestinations(sections);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: railWidth,
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 不用 ListView（桌面端会带滚动条）：按可用高度把每个条目的高度算出来，
            // 图标、文字、间距跟着一起缩，所以调整窗口大小时侧栏始终完整显示、不滚动。
            const avatarBlock = 50.0;
            const dividerBlock = 14.0;
            final themeMode = ref.watch(settingsProvider).valueOrNull?.themeMode ?? AppThemeMode.system;
            final fixed = avatarBlock + (sections.length - 1) * dividerBlock;
            // 末尾还要放一个「主题模式」入口，所以按 items.length + 1 算条目高度。
            final extent = ((constraints.maxHeight - fixed - 8) / (items.length + 1)).clamp(32.0, 60.0);
            final content = Column(
              children: [
                SizedBox(
                  height: avatarBlock,
                  child: Center(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => context.push('/mine'),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: CircleAvatar(radius: 17, backgroundImage: hasAvatar ? appNetworkImage(account!.avatarUrl!) : null, child: hasAvatar ? null : Icon(loggedIn ? Icons.person : Icons.person_outline, size: 19)),
                        ),
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: dividerBlock, child: Divider(height: dividerBlock, indent: 12, endIndent: 12)),
                  for (final item in sections[i].items) _CompactRailItem(item: item, selected: item.location == path, extent: extent, onTap: () => _openDrawerLocation(context, navigationShell, item.location)),
                ],
                // 左下角的主题模式：点一下在「跟随系统 → 浅色 → 深色」之间循环，图标跟着当前模式变。
                _CompactRailItem(
                  item: _DrawerItem(icon: _themeModeIcon(themeMode), selectedIcon: _themeModeIcon(themeMode), label: AppLocalizations.of(context)!.themeMode, location: '', iconOnly: true),
                  selected: false,
                  extent: extent,
                  onTap: () => unawaited(_cycleThemeMode(context, ref)),
                ),
              ],
            );
            // 极端尺寸的兜底：允许滚动但隐藏滚动条（正常尺寸下根本不会滚）。
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6), child: content),
            );
          },
        ),
      ),
    );
  }
}

/// 主题模式图标：跟随系统 / 浅色 / 深色 各一个。
IconData _themeModeIcon(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => Icons.brightness_auto_outlined,
      AppThemeMode.light => Icons.light_mode_outlined,
      AppThemeMode.dark => Icons.dark_mode_outlined,
    };

/// 左下角的主题模式入口：点一下在「跟随系统 → 浅色 → 深色」之间循环，
/// 切换后给一个居中提示（侧栏按约定不用 tooltip）。
Future<void> _cycleThemeMode(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider).valueOrNull;
  if (settings == null) return;
  final next = switch (settings.themeMode) {
    AppThemeMode.system => AppThemeMode.light,
    AppThemeMode.light => AppThemeMode.dark,
    AppThemeMode.dark => AppThemeMode.system,
  };
  final l10n = AppLocalizations.of(context);
  await ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(themeMode: next));
  if (!context.mounted || l10n == null) return;
  showAppToast(
    context,
    switch (next) {
      AppThemeMode.system => l10n.followSystem,
      AppThemeMode.light => l10n.light,
      AppThemeMode.dark => l10n.dark,
    },
    icon: _themeModeIcon(next),
  );
}

/// 单个窄栏条目：悬停或选中时**只有图标与文字**转为主题色（b 站那种），
/// 不画底色块 —— 底色块会显得比图标本身还抢眼。
class _CompactRailItem extends StatefulWidget {
  const _CompactRailItem({required this.item, required this.selected, required this.extent, required this.onTap});

  final _DrawerItem item;
  final bool selected;

  /// 由侧栏可用高度算出：窗口变矮时图标 / 文字 / 间距一起缩，保证不出现滚动。
  final double extent;
  final VoidCallback onTap;

  @override
  State<_CompactRailItem> createState() => _CompactRailItemState();
}

class _CompactRailItemState extends State<_CompactRailItem> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final item = widget.item;
    final highlighted = selected || _hovering;
    final color = highlighted ? scheme.primary : scheme.onSurfaceVariant;
    final label = item.shortLabel ?? item.label;
    final extent = widget.extent;
    final iconSize = (extent * 0.42).clamp(14.0, 24.0);
    final labelSize = (extent * 0.2).clamp(9.0, 11.5);
    final gap = ((extent - iconSize - labelSize - 4) / 2).clamp(1.0, 5.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: extent,
        child: InkWell(
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: widget.onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.selectedIcon : item.icon, size: iconSize, color: color),
              if (!item.iconOnly) ...[
                SizedBox(height: gap),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: labelSize, height: 1.0, color: color, fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem {
  const _DrawerItem({required this.icon, required this.selectedIcon, required this.label, this.shortLabel, required this.location, this.iconOnly = false});

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
                CircleAvatar(radius: 28, backgroundImage: account?.avatarUrl?.isNotEmpty == true ? appNetworkImage(account!.avatarUrl!) : null, child: account?.avatarUrl?.isNotEmpty == true ? null : Icon(loggedIn ? Icons.person : Icons.person_outline, size: 30)),
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