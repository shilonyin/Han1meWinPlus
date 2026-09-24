import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/settings.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/library_repository.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../account/account_controller.dart';
import '../library/remote_library_controller.dart';
import '../settings/settings_controller.dart';
import '../shared/video_card.dart';
import '../shared/app_image_cache.dart';
import 'video_actions.dart';
import 'video_controller.dart';

class VideoDescriptionView extends ConsumerStatefulWidget {
  const VideoDescriptionView({super.key, required this.video});

  final VideoDetail video;

  @override
  ConsumerState<VideoDescriptionView> createState() => _VideoDescriptionViewState();
}

/// 简介默认收起（整块详情都不显示），点标题旁的「展开」才展示
class _VideoDescriptionViewState extends ConsumerState<VideoDescriptionView> with AutomaticKeepAliveClientMixin {  var _descriptionExpanded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final video = widget.video;
    final translation = ref.watch(videoTranslationProvider(video.id)).valueOrNull;
    final description = translation?.description ?? video.description ?? '';
    final related = visibleRelatedVideos(ref, video.related);
    // 作者 / 上传者 / 简介内容都算「详情」，收起时整块一起隐藏
    final hasDetails = description.isNotEmpty || video.uploader != null || translation?.captionTitle != null || video.captionTitle != null;
    void toggleDescription() => setState(() => _descriptionExpanded = !_descriptionExpanded);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 侧栏内容顺序：作者 → 标题（带展开/收起）→ 数据 → 简介 → 标签 → 系列 → 翻译
              _ArtistRow(video: video),
              _TitleBlock(video: video, title: translation?.title, hasDetails: hasDetails, expanded: _descriptionExpanded, onToggleDescription: toggleDescription),
              // 操作排放在标题/数据下面
              VideoActionRow(video: video),
              if (_descriptionExpanded) _Description(video: video, captionTitle: translation?.captionTitle, description: translation?.description, onToggle: toggleDescription),
              _TagList(video: video),
              if (video.playlist.isNotEmpty) _SeriesVideos(videos: video.playlist, currentVideoId: video.id),
              _TranslateButton(video: video),
            ],
          ),
        ),
        // 相关推荐并进简介里滚动（不再单独占一个标签页）
        if (related.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(AppLocalizations.of(context)!.relatedVideos, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        SliverList.builder(
          itemCount: related.length,
          itemBuilder: (context, index) => Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: _RelatedVideoTile(video: related[index])),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

/// 相关推荐列表需要应用的推荐过滤规则（原来在独立的「相关推荐」标签页里）
List<VideoCard> visibleRelatedVideos(WidgetRef ref, List<VideoCard> videos) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (settings?.applyRecommendationFiltersToRelated != true) return videos;
  final authors = settings?.blockedAuthors ?? const <String>[];
  final titles = settings?.blockedVideoTitleKeywords ?? const <String>[];
  final tags = settings?.blockedVideoTags ?? const <String>[];
  return videos.where((video) => !titles.any((keyword) => video.title.toLowerCase().contains(keyword.toLowerCase())) && !authors.any((author) => (video.artist ?? '').toLowerCase().contains(author.toLowerCase())) && !tags.any((blockedTag) => video.tags.any((tag) => tag.toLowerCase().contains(blockedTag.toLowerCase())))).toList();
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.video, required this.hasDetails, required this.expanded, required this.onToggleDescription, this.title});

  final VideoDetail video;
  final String? title;
  final bool hasDetails;
  final bool expanded;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleText(text: title ?? video.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ?? const TextStyle(), expanded: expanded),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (video.views != null) _MetaText(icon: Icons.visibility_outlined, label: video.views!),
                    if (video.commentCount != null) _MetaText(icon: Icons.mode_comment_outlined, label: '${video.commentCount}'),
                    if (video.uploadDate != null) _MetaText(icon: Icons.calendar_today_outlined, label: video.uploadDate!),
                    if (video.genre != null) _MetaText(icon: Icons.local_offer_outlined, label: video.genre!),
                  ],
                ),
              ],
            ),
          ),
          // 标题右侧的展开/收起（收起后整块详情都不占位置）
          if (hasDetails)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton(
                onPressed: onToggleDescription,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Text(expanded ? l10n.collapse : l10n.expand), Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18)]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((video.artist ?? '').isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).valueOrNull;
    final remote = account == null ? null : ref.watch(remoteLibraryProvider).valueOrNull;
    final library = ref.watch(libraryProvider).value ?? const LibraryState();
    final persisted = (remote?.subscriptionArtists ?? library.artists).any((item) => item.name == video.artist);
    final subscribed = ref.watch(subscriptionOverrideProvider(video.id)) ?? persisted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          // 条件同时写进 URL：`extra` 在路由重建后可能丢掉（go_router 不保证），
          // 那时搜索页会退化成「没有关键词」的页，看起来就是点了作者没内容。
          onTap: () {
            final url = Uri(path: '/search', queryParameters: {'query': video.artist!}).toString();
            context.push(url, extra: SearchRouteRequest(initialUrl: url, authorName: video.artist));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(radius: 24, backgroundColor: theme.colorScheme.surfaceContainerHighest, backgroundImage: video.artistAvatarUrl == null ? null : appNetworkImage(video.artistAvatarUrl!), child: video.artistAvatarUrl == null ? Text(video.artist!.characters.first, style: theme.textTheme.titleMedium) : null),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(video.artist!, style: theme.textTheme.titleSmall), Text(AppLocalizations.of(context)!.studio, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))])),
                FilledButton.tonal(
                  onPressed: account == null
                      ? () => ref.read(libraryProvider.notifier).setSubscription(video, !subscribed)
                      : video.artistId == null || (video.csrfToken ?? account.csrfToken) == null || (video.subscriptionUserId ?? video.currentUserId ?? account.id) == null
                          ? null
                          : () => _setSubscription(ref, video.csrfToken ?? account.csrfToken!, video.subscriptionUserId ?? video.currentUserId ?? account.id!, video.artistId!, !subscribed),
                  child: Text(subscribed ? AppLocalizations.of(context)!.subscribed : AppLocalizations.of(context)!.subscribe),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setSubscription(WidgetRef ref, String token, String userId, String artistId, bool enabled) async {
    ref.read(subscriptionOverrideProvider(video.id).notifier).state = enabled;
    try {
      final settings = await ref.read(settingsProvider.future);
      await ref.read(han1meRepositoryProvider).setSubscription(settings.resolvedBaseUrl, token, userId, artistId, enabled);
      ref.invalidate(remoteLibraryProvider);
    } catch (_) {
      ref.read(subscriptionOverrideProvider(video.id).notifier).state = !enabled;
    }
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.video, required this.onToggle, this.captionTitle, this.description});

  final VideoDetail video;
  final VoidCallback onToggle;
  final String? captionTitle;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final description = this.description ?? video.description ?? '';
    final l10n = AppLocalizations.of(context)!;
    if (description.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (video.uploader case final uploader?) ...[Text('${l10n.uploader}: $uploader', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)), const SizedBox(height: 8)],
                  if (captionTitle ?? video.captionTitle case final title?) ...[Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8)],
                  Text(description),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签区：一排 4 个 + 折叠时显示的行数
const int _tagColumns = 4;
const double _tagSpacing = 8;
const double _tagRunSpacing = 6;
const int _tagCollapsedRows = 2;

class _TagList extends ConsumerStatefulWidget {
  const _TagList({required this.video});

  final VideoDetail video;

  @override
  ConsumerState<_TagList> createState() => _TagListState();
}

class _TagListState extends ConsumerState<_TagList> {
  final _wrapKey = GlobalKey();
  final _firstChipKey = GlobalKey();
  var _expanded = false;
  var _canExpand = false;
  double? _collapsedHeight;
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wrap = _wrapKey.currentContext?.size;
      final chip = _firstChipKey.currentContext?.size;
      if (wrap == null || chip == null) return;
      // 折叠时显示 2 排；行高取芯片高度与行内 +/- 按钮高度的较大值
      final rowHeight = (chip.height < 32.0 ? 32.0 : chip.height);
      final height = rowHeight * _tagCollapsedRows + _tagRunSpacing * (_tagCollapsedRows - 1);
      final canExpand = wrap.height > height + .5;
      if (_collapsedHeight != height || _canExpand != canExpand) setState(() {
        _collapsedHeight = height;
        _canExpand = canExpand;
      });
    });
  }

  Future<void> _editTags(String mode) async {
    await context.push('/video/${widget.video.id}/tags/$mode');
    ref.invalidate(videoDetailProvider(widget.video.id));
  }

  @override
  Widget build(BuildContext context) {
    final tags = widget.video.tags;
    final account = ref.watch(accountProvider).valueOrNull;
    final enabled = account != null && (widget.video.csrfToken ?? account.csrfToken) != null;
    final catalog = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final localeKey = searchOptionLocaleKey(Localizations.localeOf(context));
    final l10n = AppLocalizations.of(context)!;
    if (tags.isEmpty && !enabled) return const SizedBox.shrink();
    final children = <Widget>[
      for (var index = 0; index < tags.length; index++)
        ActionChip(
          key: index == 0 ? _firstChipKey : null,
          label: Text('${catalog?.localizeTag(tags[index].name, localeKey) ?? tags[index].name}${tags[index].count == null ? '' : ' (${tags[index].count})'}', maxLines: 1, overflow: TextOverflow.ellipsis),
          labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 12),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          // 同上：条件要放进 URL，不能只靠 `extra`。
          onPressed: () {
            final href = tags[index].href;
            final uri = href == null ? Uri(path: '/search', queryParameters: {'tags[]': tags[index].name}) : Uri.parse(href);
            // 只取路径与查询参数：站点地址（可能是绝对 URL）不能直接交给 go_router 匹配。
            final url = Uri(path: uri.path, queryParameters: uri.queryParameters.isEmpty ? {'tags[]': tags[index].name} : uri.queryParameters).toString();
            context.push(url, extra: SearchRouteRequest(initialUrl: url));
          },
        ),
      IconButton(tooltip: l10n.addTags, visualDensity: VisualDensity.compact, iconSize: 18, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 32, height: 32), icon: const Icon(Icons.add), onPressed: enabled ? () => _editTags('add') : null),
      IconButton(tooltip: l10n.removeTags, visualDensity: VisualDensity.compact, iconSize: 18, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 32, height: 32), icon: const Icon(Icons.remove), onPressed: enabled ? () => _editTags('remove') : null),
    ];
    if (tags.isEmpty) children.first = SizedBox(key: _firstChipKey, width: 32, height: 32, child: children.first);
    _measure();
    // 一排 4 个（每格等宽，芯片左对齐）；窗口很窄时按可用宽度自动减到 3/2 个，免得标签全被省略号吃掉
    final wrap = LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 70).floor().clamp(1, _tagColumns).toInt();
        final cellWidth = (constraints.maxWidth - _tagSpacing * (columns - 1)) / columns;
        return Wrap(
          key: _wrapKey,
          spacing: _tagSpacing,
          runSpacing: _tagRunSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final child in children) SizedBox(width: cellWidth, child: Align(alignment: Alignment.centerLeft, child: child))],
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_expanded || _collapsedHeight == null)
              wrap
            else
              LayoutBuilder(
                builder: (context, constraints) => ClipRect(
                  child: SizedBox(
                    height: _collapsedHeight,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: constraints.maxWidth,
                      maxWidth: constraints.maxWidth,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: wrap,
                    ),
                  ),
                ),
              ),
            if (_canExpand) IconButton(tooltip: _expanded ? l10n.collapse : l10n.expand, visualDensity: VisualDensity.compact, iconSize: 20, onPressed: () => setState(() => _expanded = !_expanded), icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more)),
          ],
        ),
      ),
    );
  }
}

class _SeriesVideos extends StatefulWidget {
  const _SeriesVideos({required this.videos, required this.currentVideoId});

  final List<VideoCard> videos;
  final String currentVideoId;

  @override
  State<_SeriesVideos> createState() => _SeriesVideosState();
}

class _SeriesVideosState extends State<_SeriesVideos> {
  final _controller = ScrollController();
  /// 鼠标是否在这一排上（决定左右翻页箭头显示）
  var _hovered = false;
  var _canBack = false;
  var _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncArrows);
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canBack = position.pixels > 1;
    final canForward = position.pixels < position.maxScrollExtent - 1;
    if (canBack != _canBack || canForward != _canForward) {
      setState(() {
        _canBack = canBack;
        _canForward = canForward;
      });
    }
  }

  /// 整页翻动（按可视宽度滚动）
  void _page(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + direction * position.viewportDimension).clamp(0.0, position.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 8, 8), child: Row(children: [Expanded(child: Text(l10n.seriesVideos, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), TextButton(onPressed: () => _showAll(context), child: Text(l10n.more))])),
        MouseRegion(
          // 鼠标移进这一排（图片附近）才显示翻页箭头，移开自动淡出
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: SizedBox(
            height: 120,
            child: Stack(
              children: [
                ListView.separated(controller: _controller, padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal, itemCount: widget.videos.length, separatorBuilder: (context, index) => const SizedBox(width: 8), itemBuilder: (context, index) => SizedBox(width: 90, child: VideoCardTile(video: widget.videos[index], horizontal: true, dense: true, selected: widget.videos[index].id == widget.currentVideoId))),
                if (_canBack) Positioned(left: 4, top: 0, bottom: 0, child: Center(child: _SeriesPageArrow(icon: Icons.chevron_left, tooltip: l10n.previousPage, visible: _hovered, onPressed: () => _page(-1)))),
                if (_canForward) Positioned(right: 4, top: 0, bottom: 0, child: Center(child: _SeriesPageArrow(icon: Icons.chevron_right, tooltip: l10n.nextPage, visible: _hovered, onPressed: () => _page(1)))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAll(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .78, child: Column(children: [Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 12), child: Align(alignment: Alignment.centerLeft, child: Text(AppLocalizations.of(context)!.seriesVideos, style: Theme.of(context).textTheme.titleLarge))), Expanded(child: VideoCardGrid(videos: widget.videos, itemBuilder: (context, index, video, horizontal) => VideoCardTile(video: video, horizontal: horizontal, selected: video.id == widget.currentVideoId)))]))));
}

/// 系列影片左右翻页箭头：半透明圆角，鼠标移开自动隐藏（参考侧栏手把）
class _SeriesPageArrow extends StatelessWidget {
  const _SeriesPageArrow({required this.icon, required this.tooltip, required this.visible, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: const Color(0x73000000),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(width: 32, height: 56, child: Icon(icon, size: 22, color: Colors.white)),
            ),
          ),
        ),
      );
}

class _TranslateButton extends ConsumerWidget {
  const _TranslateButton({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoTranslationProvider(video.id));
    ref.listen(videoTranslationProvider(video.id), (previous, next) {
      if (next.hasError && previous?.hasError != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.translationFailed)));
      }
    });
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: TextButton(
          onPressed: state.isLoading
              ? null
              : () {
                  final language = ref.read(settingsProvider).valueOrNull?.language ?? AppLanguage.system;
                  final locale = Localizations.localeOf(context);
                  ref.read(videoTranslationProvider(video.id).notifier).translate(video, language, locale.toLanguageTag());
                },
          child: Text(state.isLoading ? AppLocalizations.of(context)!.translating : AppLocalizations.of(context)!.translate),
        ),
      ),
    );
  }
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({required this.video});

  final VideoCard video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: video.id.isEmpty ? null : () => context.push('/video/${video.id}'),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 144, height: 81, child: CachedNetworkImage(imageUrl: video.coverUrl, cacheManager: appImageCacheManager, fit: BoxFit.cover, placeholder: (context, url) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest), errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image_outlined))))),
              const SizedBox(width: 12),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)), const SizedBox(height: 6), if (video.artist != null) Text(video.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)), if (video.views != null) Text(video.views!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))])),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题最多两行；放不下就从中间截断（保留首尾、用「……」连接），比只在末尾省略更容易认出标题
class _TitleText extends StatelessWidget {
  const _TitleText({required this.text, required this.style, required this.expanded, this.maxLines = 2});

  final String text;
  final TextStyle style;
  /// 展开详情时标题显示完整，不再中间省略
  final bool expanded;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (expanded) return Text(text, style: style);
    return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0) return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          bool fits(String candidate) {
            final painter = TextPainter(text: TextSpan(text: candidate, style: style), maxLines: maxLines, textDirection: direction, textScaler: scaler)..layout(maxWidth: constraints.maxWidth);
            final ok = !painter.didExceedMaxLines;
            painter.dispose();
            return ok;
          }

          if (fits(text)) return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
          const marker = '……';
          final characters = text.characters.toList();
          var low = 0;
          var high = characters.length;
          var best = marker;
          // 二分找「开头 + …… + 结尾」能塞进两行的最长结果（开头多留一点）
          while (low <= high) {
            final total = (low + high) ~/ 2;
            final head = (total * .6).ceil();
            final tail = total - head;
            final candidate = '${characters.take(head).join()}$marker${tail > 0 ? characters.skip(characters.length - tail).join() : ''}';
            if (fits(candidate)) {
              best = candidate;
              low = total + 1;
            } else {
              high = total - 1;
            }
          }
          return Text(best, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
        },
      );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 4), Text(label, style: Theme.of(context).textTheme.bodySmall)]);
}
