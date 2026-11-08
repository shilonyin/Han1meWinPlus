import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_radius.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../domain/models/video.dart';
import '../explore/explore_controller.dart';
import '../explore/explore_page.dart';
import '../shared/press_scale.dart';
import 'settings_controller.dart';
import 'settings_sub_page.dart';
import '../shared/app_top_bar.dart';

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
      backgroundColor: AppDesignTokens.pageBackground,
      appBar: AppTopBar(
        leading: settingsSubPageBack(context),
        title: Text(l10n.homeQuickCategories, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
      ),
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
          // `SliverReorderableList` 无法直接塞进 `SettingsCardList`（后者是非 sliver 的
          // Column 卡片），所以这里保持自定义 sliver 布局，只把每行做成白卡圆角 16、
          // 行高 44、token 配色，拖拽排序仍由 `ReorderableDragStartListener` 驱动。
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            sliver: SliverReorderableList(
              itemCount: selected.length,
              onReorderItem: (oldIndex, newIndex) {
                final list = [...selected];
                list.insert(newIndex, list.removeAt(oldIndex));
                save(list);
              },
              itemBuilder: (context, index) => _CategoryRow(
                key: ValueKey(selected[index]),
                title: label(selected[index]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text('${index + 1}', style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted)),
                    ),
                    PressScale(
                      child: IconButton(
                        tooltip: l10n.delete,
                        onPressed: () => save([...selected]..removeAt(index)),
                        icon: const Icon(Symbols.remove_circle_rounded, size: 20),
                        color: AppDesignTokens.inkMuted,
                        splashRadius: 20,
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Symbols.drag_indicator_rounded, size: 20, color: AppDesignTokens.inkMuted),
                      ),
                    ),
                  ],
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: Text(l10n.homeQuickCategoriesNeedsNetwork, style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkSubtle)),
                    )
                  else
                    for (final raw in available)
                      _CategoryRow(
                        title: label(raw),
                        enabled: !isFull,
                        onTap: isFull ? null : () => save([...selected, raw]),
                        leading: const Icon(Symbols.add_circle_rounded, size: 20, color: AppDesignTokens.inkMuted),
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

/// 统一设置页样式的分类行：白底圆角 16、行高 44、1px 分隔线的卡片里的一行。
///
/// 与 [SettingsTile] 的视觉保持一致（同样的行高与 token 配色），但额外支持
/// `leading`/`trailing` 的自由排布，好让 `SliverReorderableList` 的拖拽手柄能放进去。
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({super.key, required this.title, this.leading, this.trailing, this.onTap, this.enabled = true});

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: PressScale(child: InkWell(
          onTap: enabled ? onTap : null,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          focusColor: AppDesignTokens.accent.withValues(alpha: .16),
          child: Padding(
            // 行高约 44：minHeight 32 + 上下各 6（与 settings_list 的 SettingsTile 一致）。
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                children: [
                  if (leading != null) ...[
                    IconTheme.merge(data: const IconThemeData(color: AppDesignTokens.inkSubtle), child: leading!),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        color: enabled ? AppDesignTokens.ink : AppDesignTokens.inkMuted,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
    )));
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
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppDesignTokens.accent)),
            if (hint case final hint?) ...[
              const SizedBox(height: 4),
              Text(hint, style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
            ],
          ],
        ),
      );
}
