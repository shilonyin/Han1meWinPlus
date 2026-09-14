import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/remote/han1me_api.dart' show SearchResult;
import '../../domain/models/search_query.dart';
import '../settings/settings_controller.dart';
import '../shared/compact_video_card.dart';
import '../shared/underline_tab_strip.dart';
import '../shared/video_card.dart';
import 'search_controller.dart';

const _compactSearchGenres = {'裏番', '泡麵番'};

/// 搜索结果网格：每行四个、一屏三行。
const _searchColumns = 4;
const _searchRows = 3;

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, required this.request});

  final SearchRouteRequest request;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final query = ref.read(searchQueryProvider(widget.request));
    _textController.text = query.text;
    if (query.hasSearchCriteria) unawaited(ref.read(searchHistoryProvider.notifier).record(query));
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request == widget.request) return;
    _textController.text = ref.read(searchQueryProvider(widget.request)).text;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final result = ref.watch(searchResultsProvider(request));
    final query = ref.watch(searchQueryProvider(request));
    final notifier = ref.read(searchQueryProvider(request).notifier);
    final options = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    final useCompactCards = (ref.watch(settingsProvider).valueOrNull?.useCompactSearchCards ?? true) &&
        _compactSearchGenres.contains(options?.genres.canonical(query.genre) ?? query.genre);
    ref.listen<SearchQuery>(searchQueryProvider(request), (previous, next) {
      if (previous != next && next.hasSearchCriteria) unawaited(ref.read(searchHistoryProvider.notifier).record(next));
      if (_textController.text != next.text) _textController.value = _textController.value.copyWith(text: next.text, selection: TextSelection.collapsed(offset: next.text.length));
    });
    void submit(String value) {
      notifier.text(value.trim());
      unawaited(ref.read(searchHistoryProvider.notifier).record(ref.read(searchQueryProvider(request))));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
        titleSpacing: 0,
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _SearchInput(
              controller: _textController,
              hintText: l10n.searchHint,
              autoFocus: request.initialUrl == null && request.initialQuery == null,
              onSubmitted: submit,
              onClear: () {
                _textController.clear();
                notifier.text('');
              },
            ),
          ),
        ),
        actions: const [SizedBox(width: 56)],
      ),
      body: Column(
        children: [
          _GenreTabs(options: options, query: query, notifier: notifier),
          _SortRow(options: options, query: query, notifier: notifier),
          Expanded(
            child: result.when(
              loading: () => const Center(child: M3EContainedLoadingIndicator()),
              error: (error, stackTrace) => _ErrorView(error: error, onRetry: () => ref.invalidate(searchResultsProvider(request))),
              data: (page) => page.items.isEmpty
                  ? _EmptyState(message: l10n.noSearchResults)
                  : useCompactCards
                      ? CompactVideoCardGrid(
                          videos: page.items,
                          cardsPerRow: _searchColumns,
                          rowsPerScreen: _searchRows,
                          itemBuilder: (context, index, video) => CompactVideoCard(
                            video: video,
                            onTap: video.id.isEmpty ? null : () => context.push('/video/${video.id}'),
                          ),
                        )
                      : VideoCardGrid(
                          videos: page.items,
                          cardsPerRow: _searchColumns,
                          rowsPerScreen: _searchRows,
                          itemBuilder: (context, index, video, horizontal) => VideoCardTile(
                            video: video,
                            horizontal: horizontal,
                            fillCover: true,
                            onTap: video.id.isEmpty ? null : () => context.push('/video/${video.id}'),
                          ),
                        ),
            ),
          ),
          _PaginationBar(
            result: result.valueOrNull,
            onChanged: notifier.page,
          ),
        ],
      ),
    );
  }
}

/// 搜索页顶部输入框：圆角填充、右侧「清除 + 搜索」，样式对齐主流视频站点。
class _SearchInput extends StatelessWidget {
  const _SearchInput({required this.controller, required this.hintText, required this.autoFocus, required this.onSubmitted, required this.onClear});

  final TextEditingController controller;
  final String hintText;
  final bool autoFocus;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      autofocus: autoFocus,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: .6))),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(visualDensity: VisualDensity.compact, iconSize: 18, onPressed: onClear, icon: const Icon(Icons.close)),
            ),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => onSubmitted(controller.text), icon: const Icon(Icons.search, size: 20)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// 第一行：内容分类页签（全部 / 各分类），选中项染色 + 下划线。
class _GenreTabs extends StatelessWidget {
  const _GenreTabs({required this.options, required this.query, required this.notifier});

  final SearchOptionCatalog? options;
  final SearchQuery query;
  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final catalog = options;
    if (catalog == null) return const SizedBox(height: 44);
    final l10n = AppLocalizations.of(context)!;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final items = catalog.genres.options;
    return SizedBox(
      height: 44,
      child: UnderlineTabStrip(
        center: true,
        labels: [for (final item in items) item.searchKey == null ? l10n.all : item.labelFor(locale)],
        index: items.indexWhere((item) => (item.searchKey ?? '') == query.genre),
        onSelected: (value) => notifier.genre(items[value].searchKey ?? ''),
      ),
    );
  }
}

/// 第二行：排序方式（文本胶囊）+ 右侧「更多筛选」。
class _SortRow extends StatelessWidget {
  const _SortRow({required this.options, required this.query, required this.notifier});

  final SearchOptionCatalog? options;
  final SearchQuery query;
  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final catalog = options;
    final l10n = AppLocalizations.of(context)!;
    if (catalog == null) return const SizedBox(height: 46);
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    return SizedBox(
      height: 46,
      child: Stack(
        children: [
          // 排序胶囊居中；两侧留出「更多筛选」的宽度，窄窗时内容仍可横向滚动。
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 112),
              child: Row(
                children: [
                  for (final item in catalog.sorts.options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SortChip(
                        label: item.searchKey == null ? l10n.searchSortGeneral : item.labelFor(locale),
                        selected: (item.searchKey ?? '') == query.sort,
                        onTap: () => notifier.sort(item.searchKey ?? ''),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(padding: const EdgeInsets.only(right: 12), child: _MoreFiltersMenu(options: catalog, query: query, notifier: notifier)),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: selected ? scheme.primary : scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
        child: Text(label, maxLines: 1, style: TextStyle(fontSize: 12.5, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

/// 「更多筛选」：把发布日期、时长、标签、作者收进一个菜单，菜单项直接显示当前取值。
class _MoreFiltersMenu extends StatelessWidget {
  const _MoreFiltersMenu({required this.options, required this.query, required this.notifier});

  final SearchOptionCatalog options;
  final SearchQuery query;
  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final dates = options.releaseDates;
    final durations = options.durations;
    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          leadingIcon: const Icon(Icons.calendar_month_outlined, size: 18),
          menuChildren: [
            for (final item in dates.options)
              MenuItemButton(onPressed: () => notifier.date(item.searchKey ?? ''), child: Text((item.searchKey ?? '').isEmpty ? l10n.all : item.labelFor(locale))),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: () async {
                final date = await _showDateFilter(context, query.date, dates.options, locale);
                if (date != null) notifier.date(date);
              },
              child: Text(l10n.specificYearMonth),
            ),
          ],
          child: Text(l10n.releaseDate(query.date.isEmpty ? l10n.all : dates.localize(query.date, locale) ?? query.date)),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.schedule_outlined, size: 18),
          menuChildren: [
            for (final item in durations.options)
              MenuItemButton(onPressed: () => notifier.duration(item.searchKey ?? ''), child: Text((item.searchKey ?? '').isEmpty ? l10n.all : item.labelFor(locale))),
          ],
          child: Text(l10n.duration(query.duration.isEmpty ? l10n.all : durations.localize(query.duration, locale) ?? query.duration)),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.sell_outlined, size: 18),
          onPressed: () async {
            final selection = await _showTagFilter(context, query.tags, query.broad, options, locale);
            if (selection != null) notifier.tags(selection.tags, selection.broad);
          },
          child: Text(query.tags.isEmpty ? l10n.tags : l10n.tagsSelected(query.tags.length)),
        ),
        MenuItemButton(
          leadingIcon: Icon(query.type == 'artist' ? Icons.check : Icons.person_search_outlined, size: 18),
          onPressed: () => notifier.type(query.type == 'artist' ? '' : 'artist'),
          child: Text(l10n.searchAuthors),
        ),
      ],
      builder: (context, controller, child) => TextButton.icon(
        onPressed: controller.open,
        icon: const Icon(Icons.tune, size: 18),
        label: Text(l10n.searchMoreFilters),
      ),
    );
  }
}

enum _DateMode { range, month }

Future<String?> _showDateFilter(BuildContext context, String currentDate, List<SearchOption> options, String locale) => showDialog<String>(
      context: context,
      builder: (context) => _DateFilterDialog(currentDate: currentDate, options: options, locale: locale),
    );

class _DateFilterDialog extends StatefulWidget {
  const _DateFilterDialog({required this.currentDate, required this.options, required this.locale});

  final String currentDate;
  final List<SearchOption> options;
  final String locale;

  @override
  State<_DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<_DateFilterDialog> {
  _DateMode _mode = _DateMode.range;
  String _range = '';
  String _year = '';
  String _month = '';

  @override
  void initState() {
    super.initState();
    if (widget.options.map((item) => item.searchKey).contains(widget.currentDate)) {
      _range = widget.currentDate;
    } else if (widget.currentDate.isNotEmpty) {
      final values = widget.currentDate.split(' ');
      _year = values.take(2).join(' ');
      _month = values.length > 2 ? values.skip(2).take(2).join(' ') : '';
      _mode = _DateMode.month;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final years = [for (var year = DateTime.now().year; year >= 1990; year--) '$year 年'];
    return AlertDialog(
      title: Text(l10n.releaseDateTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<_DateMode>(
              segments: [
                ButtonSegment(value: _DateMode.range, label: Text(l10n.dateRange)),
                ButtonSegment(value: _DateMode.month, label: Text(l10n.specificYearMonth)),
              ],
              selected: {_mode},
              onSelectionChanged: (value) => setState(() => _mode = value.first),
            ),
            const SizedBox(height: 16),
            if (_mode == _DateMode.range)
              DropdownButtonFormField<String>(
                value: _range,
                decoration: InputDecoration(labelText: l10n.releaseDateTitle),
                 items: widget.options.map((item) => DropdownMenuItem(value: item.searchKey ?? '', child: Text((item.searchKey?.isEmpty ?? true) ? l10n.all : item.labelFor(widget.locale)))).toList(),
                onChanged: (value) => setState(() => _range = value ?? ''),
              )
            else
              Row(
                children: [
                  Expanded(child: DropdownButtonFormField(value: _year, decoration: InputDecoration(labelText: l10n.year), items: ['', ...years].map((value) => DropdownMenuItem(value: value, child: Text(value.isEmpty ? l10n.allYears : value))).toList(), onChanged: (value) => setState(() => _year = value ?? ''))),
                  const SizedBox(width: 12),
                  Expanded(child: DropdownButtonFormField(value: _month, decoration: InputDecoration(labelText: l10n.month), items: [for (var month = 1; month <= 12; month++) '$month 月', ''].map((value) => DropdownMenuItem(value: value, child: Text(value.isEmpty ? l10n.allMonths : value))).toList(), onChanged: (value) => setState(() => _month = value ?? ''))),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _mode == _DateMode.range ? _range : [_year, _month].where((value) => value.isNotEmpty).join(' ')), child: Text(l10n.apply)),
      ],
    );
  }
}

class _TagSelection {
  const _TagSelection(this.tags, this.broad);

  final List<String> tags;
  final bool broad;
}

Future<_TagSelection?> _showTagFilter(BuildContext context, List<String> selectedTags, bool broad, SearchOptionCatalog catalog, String locale) => showDialog<_TagSelection>(
      context: context,
      builder: (context) => _TagFilterDialog(selectedTags: selectedTags, broad: broad, catalog: catalog, locale: locale),
    );

class _TagFilterDialog extends StatefulWidget {
  const _TagFilterDialog({required this.selectedTags, required this.broad, required this.catalog, required this.locale});

  final List<String> selectedTags;
  final bool broad;
  final SearchOptionCatalog catalog;
  final String locale;

  @override
  State<_TagFilterDialog> createState() => _TagFilterDialogState();
}

class _TagFilterDialogState extends State<_TagFilterDialog> with SingleTickerProviderStateMixin {
  late final Set<String> _selected;
  late final TabController _tabController;
  late bool _broad;
  late String _group;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedTags.map(widget.catalog.canonicalTag).toSet();
    _broad = widget.broad;
    _group = widget.catalog.tags.keys.first;
    _tabController = TabController(length: widget.catalog.tags.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.tags),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.broadMatch),
              subtitle: Text(l10n.broadMatchDescription),
              value: _broad,
              onChanged: (value) => setState(() => _broad = value),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: widget.catalog.tags.keys.map((group) => Tab(text: _tagGroupLabel(l10n, group))).toList(growable: false),
              onTap: (index) => setState(() => _group = widget.catalog.tags.keys.elementAt(index)),
            ),
            Expanded(
              child: ListView(
                children: [
                  _TagGroup(
                    tags: widget.catalog.tags[_group]!.options,
                    locale: widget.locale,
                    selected: _selected,
                    onChanged: (tag, selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(tag);
                        } else {
                          _selected.remove(tag);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _TagSelection(_selected.toList()..sort(), _broad)), child: Text(l10n.apply)),
      ],
    );
  }
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({required this.tags, required this.locale, required this.selected, required this.onChanged});

  final List<SearchOption> tags;
  final String locale;
  final Set<String> selected;
  final void Function(String tag, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.map((tag) => FilterChip(label: Text(tag.labelFor(locale)), selected: selected.contains(tag.searchKey), onSelected: (value) => onChanged(tag.searchKey ?? '', value))).toList(),
            ),
          ],
        ),
      );
}

String _tagGroupLabel(AppLocalizations l10n, String group) => switch (group) {
  'video_attributes' => l10n.tagVideoAttributes,
  'character_relationships' => l10n.tagRelationships,
  'characteristics' => l10n.tagCharacterSettings,
  'appearance_and_figure' => l10n.tagAppearance,
  'story_location' => l10n.tagSettings,
  'story_plot' => l10n.tagStory,
  'sex_positions' => l10n.tagPositions,
  _ => group,
};

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.result, required this.onChanged});

  final SearchResult? result;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = result;
    if (value == null || value.totalPages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: value.page > 1 ? () => onChanged(value.page - 1) : null, icon: const Icon(Icons.chevron_left)),
          Text('${value.page} / ${value.totalPages}', style: Theme.of(context).textTheme.labelLarge),
          IconButton(onPressed: value.page < value.totalPages ? () => onChanged(value.page + 1) : null, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 56),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: Text(AppLocalizations.of(context)!.retry)),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
}
