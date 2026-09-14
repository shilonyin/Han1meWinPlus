import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../domain/models/search_query.dart';
import 'search_controller.dart';

/// 搜索框下方展开的建议面板（样式参考主流视频站点）：搜索历史 + 热门标签。
///
/// 面板本身不关心「点了以后去哪」——[onSelected] 由调用方决定：首页跳到搜索页，
/// 搜索页则就地替换当前的查询条件。
class SearchSuggestions extends ConsumerStatefulWidget {
  const SearchSuggestions({super.key, required this.onSelected, this.width = 560, this.historyLimit = 8});

  final ValueChanged<SearchQuery> onSelected;
  final double width;

  /// 未展开时最多显示几条搜索历史。
  final int historyLimit;

  @override
  ConsumerState<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends ConsumerState<SearchSuggestions> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final history = ref.watch(searchHistoryProvider).valueOrNull ?? const <SearchQuery>[];
    final catalog = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final visible = _expanded ? history : history.take(widget.historyLimit).toList(growable: false);
    final popular = _popularTags(catalog, locale);
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(l10n.searchHistory, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (history.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                    child: Text(l10n.clearSearchHistory),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (history.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(l10n.searchHistoryEmpty, style: theme.textTheme.bodySmall))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final query in visible) _SuggestionChip(label: _historyLabel(query, catalog, locale, l10n), onTap: () => widget.onSelected(query)),
                  if (!_expanded && history.length > widget.historyLimit) _MoreChip(label: l10n.expand, onTap: () => setState(() => _expanded = true)),
                ],
              ),
            if (popular.isNotEmpty) ...[
              Divider(height: 26, color: theme.colorScheme.outlineVariant.withValues(alpha: .5)),
              Text(l10n.searchPopularTags, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _PopularTagList(items: popular, onSelected: widget.onSelected),
            ],
          ],
        ),
      ),
    );
  }
}

/// 历史条目的显示文案：有搜索词就用搜索词，否则把筛选条件拼成摘要。
String _historyLabel(SearchQuery query, SearchOptionCatalog? catalog, String locale, AppLocalizations l10n) {
  if (query.text.isNotEmpty) return query.text;
  final parts = <String>[
    if (query.tags.isNotEmpty) query.tags.map((tag) => catalog?.localizeTag(tag, locale) ?? tag).join(' · '),
    if (query.genre.isNotEmpty) catalog?.genres.localize(query.genre, locale) ?? query.genre,
    if (query.sort.isNotEmpty) catalog?.sorts.localize(query.sort, locale) ?? query.sort,
    if (query.date.isNotEmpty) catalog?.releaseDates.localize(query.date, locale) ?? query.date,
    if (query.duration.isNotEmpty) catalog?.durations.localize(query.duration, locale) ?? query.duration,
    if (query.type.isNotEmpty) l10n.searchAuthors,
  ];
  return parts.isEmpty ? l10n.searchHistoryAll : parts.join(' · ');
}

/// 热门标签：取站点属性标签的前若干个，按「序号 + 名称」两列排布。
List<({String label, String key})> _popularTags(SearchOptionCatalog? catalog, String locale) {
  final options = catalog?.tags['video_attributes']?.options ?? const <SearchOption>[];
  return [
    for (final option in options.take(10))
      if (option.searchKey case final key?) (label: option.labelFor(locale), key: key),
  ];
}

class _PopularTagList extends StatelessWidget {
  const _PopularTagList({required this.items, required this.onSelected});

  final List<({String label, String key})> items;
  final ValueChanged<SearchQuery> onSelected;

  @override
  Widget build(BuildContext context) {
    final rows = (items.length + 1) ~/ 2;
    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var column = 0; column < 2; column++)
                Expanded(
                  child: row * 2 + column < items.length
                      ? _PopularTagTile(index: row * 2 + column, label: items[row * 2 + column].label, hot: row * 2 + column < 3, onTap: () => onSelected(SearchQuery(tags: [items[row * 2 + column].key])))
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }
}

class _PopularTagTile extends StatelessWidget {
  const _PopularTagTile({required this.index, required this.label, required this.hot, required this.onTap});

  final int index;
  final String label;
  final bool hot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text('${index + 1}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: index < 3 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
            if (hot) Icon(Icons.local_fire_department, size: 14, color: theme.colorScheme.error),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 168),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5, color: theme.colorScheme.primary)),
            Icon(Icons.keyboard_arrow_down, size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
