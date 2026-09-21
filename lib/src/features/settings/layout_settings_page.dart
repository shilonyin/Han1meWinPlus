import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../explore/explore_controller.dart';
import 'home_categories_page.dart';
import 'recommendation_settings_page.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';

class LayoutSettingsPage extends ConsumerStatefulWidget {
  const LayoutSettingsPage({super.key});

  @override
  ConsumerState<LayoutSettingsPage> createState() => _LayoutSettingsPageState();
}

class _LayoutSettingsPageState extends ConsumerState<LayoutSettingsPage> {
  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  String? _subPage;

  @override
  Widget build(BuildContext context) {
    if (_subPage == 'home-categories') return SettingsSubPageScope(onBack: () => setState(() => _subPage = null), child: const HomeCategoriesPage());
    if (_subPage == 'recommendations') return SettingsSubPageScope(onBack: () => setState(() => _subPage = null), child: const RecommendationSettingsPage());
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(appBar: AppBar(title: Text(l10n.interfaceLayout)), body: ListView(children: [
      SettingsCardList(title: l10n.general, children: [
        SettingsCardItem(title: l10n.navigationDrawer, subtitle: l10n.navigationDrawerDescription, leading: const Icon(Icons.menu_open_outlined), trailing: Switch(value: settings.useNavigationDrawer, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useNavigationDrawer: value)))),
        SettingsCardItem(title: l10n.comicMode, subtitle: l10n.comicModeDescription, leading: const Icon(Icons.menu_book_outlined), trailing: Switch(value: settings.comicMode, onChanged: (value) async { await controller.saveChanges((current) => current.copyWith(comicMode: value, baseUrl: value ? 'https://hanimeone.me' : current.videoBaseUrl, videoBaseUrl: value ? current.baseUrl : current.videoBaseUrl)); resetHomeFeed(ref); })),
        SettingsCardItem(title: l10n.horizontalSearchCards, subtitle: l10n.horizontalSearchCardsDescription, leading: const Icon(Icons.view_stream_outlined), trailing: Switch(value: settings.useHorizontalSearchCards, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useHorizontalSearchCards: value)))),
        SettingsCardItem(title: l10n.homeCategoryTabs, subtitle: l10n.homeCategoryTabsDescription, leading: const Icon(Icons.tab_outlined), trailing: Switch(value: settings.useHomeCategoryTabs, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useHomeCategoryTabs: value)))),
        SettingsCardItem(title: l10n.homeQuickCategories, subtitle: l10n.homeQuickCategoriesDescription, leading: const Icon(Icons.bookmarks_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => _subPage = 'home-categories')),
        SettingsCardItem(title: l10n.recommendationFilters, leading: const Icon(Icons.filter_alt_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => _subPage = 'recommendations')),
        SettingsMenuItem(title: l10n.searchCardsPerRow, subtitle: l10n.searchCardsPerRowValue(settings.searchCardsPerRow), leading: const Icon(Icons.grid_view_outlined), value: settings.searchCardsPerRow, options: const [1, 2, 3], label: l10n.searchCardsPerRowValue, onSelected: (value) => controller.saveChanges((current) => current.copyWith(searchCardsPerRow: value))),
      ]),
    ]));
  }
}
