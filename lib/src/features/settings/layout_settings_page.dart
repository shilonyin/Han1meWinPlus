import 'dart:io';

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../explore/explore_controller.dart';
import 'home_categories_page.dart';
import 'recommendation_settings_page.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';

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
    return Scaffold(appBar: embeddedInSettingsPanes(context) ? null : AppBar(title: Text(l10n.interfaceLayout)), body: ListView(children: [
      SettingsCardList(title: l10n.general, children: [
        SettingsCardItem(title: l10n.comicMode, subtitle: l10n.comicModeDescription, leading: const Icon(Symbols.menu_book_rounded), trailing: Switch(value: settings.comicMode, onChanged: (value) async { await controller.saveChanges((current) => current.copyWith(comicMode: value, baseUrl: value ? 'https://hanimeone.me' : current.videoBaseUrl, videoBaseUrl: value ? current.baseUrl : current.videoBaseUrl)); resetHomeFeed(ref); })),
        // 独立播放窗口是多进程方案（play_window.dart），只有 Windows 的 runner
        // 认 `--play-window` 参数，其余平台不显示这个开关。
        if (Platform.isWindows)
          SettingsCardItem(title: l10n.openVideoInWindow, subtitle: l10n.openVideoInWindowDescription, leading: const Icon(Symbols.picture_in_picture_rounded), trailing: Switch(value: settings.openVideoInWindow, onChanged: (value) => controller.saveChanges((current) => current.copyWith(openVideoInWindow: value)))),
        SettingsCardItem(title: l10n.homeQuickCategories, subtitle: l10n.homeQuickCategoriesDescription, leading: const Icon(Symbols.bookmarks_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => setState(() => _subPage = 'home-categories')),
        SettingsCardItem(title: l10n.recommendationFilters, leading: const Icon(Symbols.filter_alt_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => setState(() => _subPage = 'recommendations')),
      ]),
    ]));
  }
}