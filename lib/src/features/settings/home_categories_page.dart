import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../domain/models/video.dart';
import '../explore/explore_controller.dart';
import '../explore/explore_page.dart';
import 'settings_controller.dart';
import 'settings_sub_page.dart';

/// 顶栏「快捷分类」的数量上限。
const int maxHomeQuickCategories = 6;

/// 「首页快捷分类」设置页：决定顶栏那六个分类是哪些、按什么顺序显示。
///
/// 存的是**站点原始分类名**（与界面语言无关），显示时再用 [localizedHomeSectionTitle]
/// 本地化；没设置过时等价于「首页的前 6 个分类」，所以这里把默认值展开供用户拖动/增删。
class HomeCategoriesPage extends ConsumerWidget {
  const HomeCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final feed = ref.watch(homeSectionsProvider).valueOrNull;
    final catalog = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));

    final controller = ref.read(settingsProvider.notifier);
    final sections = feed?.sections ?? const <HomeSection>[];
    // 原始分类名 → 当前语言下的显示名
    String label(String raw) {
      for (final section in sections) {
        if (section.title == raw) return localizedHomeSectionTitle(section, catalog, locale, l10n: AppLocalizations.of(context));
      }
      return raw;
    }

    final allRaw = [for (final section in sections) section.title];
    final selected = settings.homeQuickCategories.isEmpty
        ? allRaw.take(maxHomeQuickCategories).toList()
        : [for (final raw in settings.homeQuickCategories) if (allRaw.isEmpty || allRaw.contains(raw)) raw];
    final available = [for (final raw in allRaw) if (!selected.contains(raw)) raw];
    final isFull = selected.length >= maxHomeQuickCategories;

    void save(List<String> titles) => controller.saveChanges((current) => current.copyWith(homeQuickCategories: titles));

    return Scaffold(
      appBar: AppBar(leading: settingsSubPageBack(context), title: Text(l10n.homeQuickCategories)),
      // 用 Sliver 组合而不是 ReorderableListView 的 header/footer：后者的 footer 区域
      // 在桌面端收不到指针事件，导致「可选分类」点不动。
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(title: l10n.homeQuickCategoriesSelected, hint: l10n.homeQuickCategoriesHint(maxHomeQuickCategories)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverReorderableList(
              itemCount: selected.length,
              onReorderItem: (oldIndex, newIndex) {
                final list = [...selected];
                list.insert(newIndex, list.removeAt(oldIndex));
                save(list);
              },
              itemBuilder: (context, index) => Padding(
                key: ValueKey(selected[index]),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator)),
                    title: Text(label(selected[index])),
                    subtitle: Text('${index + 1}'),
                    trailing: IconButton(tooltip: l10n.delete, onPressed: () => save([...selected]..removeAt(index)), icon: const Icon(Icons.remove_circle_outline, size: 20)),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle(title: l10n.homeQuickCategoriesAvailable, hint: isFull ? l10n.homeQuickCategoriesFull(maxHomeQuickCategories) : null),
                  if (sections.isEmpty)
                    Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 12), child: Text(l10n.homeQuickCategoriesNeedsNetwork, style: Theme.of(context).textTheme.bodySmall))
                  else
                    for (final raw in available)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Material(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            enabled: !isFull,
                            leading: const Icon(Icons.add_circle_outline, size: 20),
                            title: Text(label(raw)),
                            onTap: isFull ? null : () => save([...selected, raw]),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
            if (hint case final hint?) ...[const SizedBox(height: 4), Text(hint, style: Theme.of(context).textTheme.bodySmall)],
          ],
        ),
      );
}
