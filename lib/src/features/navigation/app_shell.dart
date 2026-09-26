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
    // MD3 的窗口尺寸档位：compact <600（底部条）、medium 600–840（侧栏只留图标）、
    // expanded >840（侧栏图标 + 文字一起展开）。抽屉模式不变，仍是常驻窄侧栏。
    final railExpanded = MediaQuery.sizeOf(context).width > 840;
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
                  Expanded(child: animatedContent),
                ],
              )
            : useRail
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: widget.navigationShell.currentIndex,
                        // 宽屏按 MD3 的 expanded 档展开（图标 + 文字并排），中等宽度收成
                        // 只显示图标，窄窗口才落到底部条。
                        extended: railExpanded,
                        labelType: railExpanded ? NavigationRailLabelType.all : NavigationRailLabelType.none,
                        minWidth: railExpanded ? 192 : 72,
                        // 与常驻窄侧栏一致：靠色块深浅区分侧栏和内容，不画分隔线。
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                        onDestinationSelected: select,
                        destinations: destinations.map((destination) => NavigationRailDestination(icon: Icon(destination.icon), selectedIcon: Icon(destination.selectedIcon), label: Text(destination.label))).toList(),
                      ),
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
      _DrawerItem(icon: Icons.download_for_offline_outlined, selectedIcon: Icons.download_for_offline, label: l10n.download, location: '/cache', iconOnly: true),
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
  ///
  /// 参考布局的侧栏是 96（其窗口 100% 缩放，即屏幕上 96px），而我们这边是 150% 缩放，
  /// 同一个宽度要在屏幕上一样细，就用 96 / 1.5 = 64。
  static const double railWidth = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).valueOrNull;
    final comicMode = ref.watch(settingsProvider).valueOrNull?.comicMode ?? false;
    final sections = _drawerSections(context, comicMode: comicMode, previewSource: ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto');
    final path = GoRouterState.of(context).uri.path;
    final colorScheme = Theme.of(context).colorScheme;
    // 侧栏与内容区之间不画分隔线，改用色块深浅区分（比内容区深/浅一档）。
    // AMOLED 下所有 surface 都是纯黑，再加一层极淡的白叠出可分度。
    final amoled = ref.watch(settingsProvider).valueOrNull?.amoledMode ?? false;
    final railColor = amoled ? Colors.white.withValues(alpha: 0.04) : colorScheme.surfaceContainer;
    // 桌面窄侧栏分两段（与参考布局一致）：
    //   上段 = 主项（首页 / 新番预告 / 冲了么）
    //   下段 = 「我的」（头像打头）+ 观看历史 / 下载 + 主题模式 + 设置
    // 「我的清单」那一组已经挪进「我的」页的页签，侧栏不再重复列一遍。
    final mainItems = sections.first.items;
    final videoItems = sections.last.items;
    final settingsItem = videoItems.firstWhere((item) => item.location == '/settings');
    final iconItems = videoItems.where((item) => item.location != '/settings').toList();
    // 下段固定多三项：头像（我的）、主题模式、设置。
    final rows = mainItems.length + iconItems.length + 3;
    return Container(
      width: railWidth,
      color: railColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final themeMode = ref.watch(settingsProvider).valueOrNull?.themeMode ?? AppThemeMode.system;
            // 条目高度按可用高度算（限制在上下限之间），窗口变矮时图标与文案一起缩；
            // 富余的高度不给条目，而是留给上下两段之间的间隔 —— 上段贴顶、下段贴底。
            final extent = (constraints.maxHeight / rows).clamp(34.0, 58.0);
            const edge = EdgeInsets.symmetric(vertical: 8, horizontal: 4);
            const minGap = 16.0;
            final top = <Widget>[
              for (final item in mainItems) _CompactRailItem(item: item, selected: item.location == path, extent: extent, onTap: () => _openDrawerLocation(context, navigationShell, item.location)),
            ];
            final bottom = <Widget>[
              // 下段第一项就是「我的」（头像），点它进「我的」页。
              _CompactRailAvatar(account: account, extent: extent, selected: path == '/mine', onTap: () => context.push('/mine')),
              for (final item in iconItems) _CompactRailItem(item: item, selected: item.location == path, extent: extent, onTap: () => _openDrawerLocation(context, navigationShell, item.location)),
              // 主题模式：点一下在「跟随系统 → 浅色 → 深色」之间循环，图标跟着当前模式变。
              _CompactRailItem(
                item: _DrawerItem(icon: _themeModeIcon(themeMode), selectedIcon: _themeModeIcon(themeMode), label: AppLocalizations.of(context)!.themeMode, location: '', iconOnly: true),
                selected: false,
                extent: extent,
                onTap: () => unawaited(_cycleThemeMode(context, ref)),
              ),
              // 设置：放在最末尾（主题模式在它上面）。
              _CompactRailItem(item: settingsItem, selected: settingsItem.location == path, extent: extent, onTap: () => _openDrawerLocation(context, navigationShell, settingsItem.location)),
            ];
            if (extent * rows + minGap + 16 > constraints.maxHeight) {
              // 极矮窗口的兜底：允许滚动但隐藏滚动条（正常尺寸下根本不会滚）。
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(padding: edge, child: Column(children: [...top, const SizedBox(height: minGap), ...bottom])),
              );
            }
            // 注意：必须用 Column（mainAxisSize.max）撑满高度，否则侧栏背景只有内容那么高、
            // 会被外层 Row 垂直居中，看起来就像“所有东西都挤在中间”。
            return Padding(
              padding: edge,
              child: Column(children: [...top, constraints.maxHeight.isFinite ? const Spacer() : const SizedBox(height: minGap), ...bottom]),
            );
          },
        ),
      ),
    );
  }
}

/// 侧栏下段的第一项：「我的」（圆形头像）。悬停与选中都只给头像描一圈主题色，
/// 与其它条目一样不画底色块。
class _CompactRailAvatar extends StatefulWidget {
  const _CompactRailAvatar({required this.account, required this.extent, required this.selected, required this.onTap});

  final Account? account;
  final double extent;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CompactRailAvatar> createState() => _CompactRailAvatarState();
}

class _CompactRailAvatarState extends State<_CompactRailAvatar> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final account = widget.account;
    final loggedIn = account != null;
    final hasAvatar = account?.avatarUrl?.isNotEmpty == true;
    final radius = (widget.extent * 0.26).clamp(12.0, 14.0);
    final highlighted = widget.selected || _hovering;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: widget.extent,
        child: InkWell(
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: widget.onTap,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: highlighted ? scheme.primary : Colors.transparent, width: 2)),
              child: CircleAvatar(
                radius: radius,
                backgroundImage: hasAvatar ? appNetworkImage(account!.avatarUrl!) : null,
                child: hasAvatar ? null : Icon(loggedIn ? Icons.person : Icons.person_outline, size: radius, color: highlighted ? scheme.primary : scheme.onSurfaceVariant),
              ),
            ),
          ),
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
    // 图标尺寸统一按同一个口径算（带文案与纯图标条目一律同尺寸）；
    // 上限 24 与参考里的图标大小（屏幕上 30px 左右）相当。
    final iconSize = (extent * 0.45).clamp(16.0, 24.0);
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