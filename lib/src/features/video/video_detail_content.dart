import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
import '../../core/app_design_tokens.dart';
import '../shared/glass/glass_panel.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/download_requests.dart';
import '../../data/local/library_repository.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../account/account_controller.dart';
import '../library/remote_library_controller.dart';
import '../settings/settings_controller.dart';
import '../shared/press_scale.dart';
import '../shared/bouncy_toggle_icon.dart';
import '../shared/app_image_cache.dart';
import 'play_window.dart';
import 'video_actions.dart';
import 'video_comments.dart';
import 'video_player_panel.dart';
import 'video_controller.dart';
import '../../core/app_motion.dart';

class VideoDescriptionView extends ConsumerStatefulWidget {
  const VideoDescriptionView({super.key, required this.video});

  final VideoDetail video;

  @override
  ConsumerState<VideoDescriptionView> createState() =>
      _VideoDescriptionViewState();
}

/// 简介默认收起（整块详情都不显示），点标题旁的「展开」才展示
class _VideoDescriptionViewState extends ConsumerState<VideoDescriptionView>
    with AutomaticKeepAliveClientMixin {
  var _descriptionExpanded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final video = widget.video;
    final description = video.description ?? '';
    final related = visibleRelatedVideos(ref, video.related);
    // 作者 / 上传者 / 简介内容都算「详情」，收起时整块一起隐藏
    final hasDetails =
        description.isNotEmpty ||
        video.uploader != null ||
        video.captionTitle != null;
    void toggleDescription() =>
        setState(() => _descriptionExpanded = !_descriptionExpanded);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 侧栏内容顺序：作者 → 标题（带展开/收起）→ 数据 → 简介 → 标签 → 系列
              _ArtistRow(video: video),
              _TitleBlock(
                video: video,
                hasDetails: hasDetails,
                expanded: _descriptionExpanded,
                onToggleDescription: toggleDescription,
              ),
              // 操作排放在标题/数据下面
              VideoActionRow(video: video),
              if (_descriptionExpanded)
                _Description(video: video, onToggle: toggleDescription),
              _TagList(video: video),
              if (video.playlist.isNotEmpty)
                _SeriesVideos(videos: video.playlist, currentVideoId: video.id),
            ],
          ),
        ),
        // 相关推荐并进简介里滚动（不再单独占一个标签页）
        if (related.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                AppLocalizations.of(context)!.relatedVideos,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        SliverList.builder(
          itemCount: related.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _RelatedVideoTile(video: related[index]),
          ),
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
  return videos
      .where(
        (video) =>
            !titles.any(
              (keyword) =>
                  video.title.toLowerCase().contains(keyword.toLowerCase()),
            ) &&
            !authors.any(
              (author) => (video.artist ?? '').toLowerCase().contains(
                author.toLowerCase(),
              ),
            ) &&
            !tags.any(
              (blockedTag) => video.tags.any(
                (tag) => tag.toLowerCase().contains(blockedTag.toLowerCase()),
              ),
            ),
      )
      .toList();
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.video,
    required this.hasDetails,
    required this.expanded,
    required this.onToggleDescription,
  });

  final VideoDetail video;
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
                _TitleText(
                  text: video.title,
                  style:
                      theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ) ??
                      const TextStyle(),
                  expanded: expanded,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (video.views != null)
                      _MetaText(
                        icon: Symbols.visibility_rounded,
                        label: video.views!,
                      ),
                    if (video.commentCount != null)
                      _MetaText(
                        icon: Symbols.mode_comment_rounded,
                        label: '${video.commentCount}',
                      ),
                    if (video.uploadDate != null)
                      _MetaText(
                        icon: Symbols.calendar_today_rounded,
                        label: video.uploadDate!,
                      ),
                    if (video.genre != null)
                      _MetaText(
                        icon: Symbols.local_offer_rounded,
                        label: video.genre!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // 标题右侧的展开/收起（收起后整块详情都不占位置）
          if (hasDetails)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: PressScale(
                child: TextButton(
                  onPressed: onToggleDescription,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(expanded ? l10n.collapse : l10n.expand),
                      Icon(
                        expanded
                            ? Symbols.expand_less_rounded
                            : Symbols.expand_more_rounded,
                        size: 18,
                      ),
                    ],
                  ),
                ),
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
    final remote = account == null
        ? null
        : ref.watch(remoteLibraryProvider).valueOrNull;
    final library = ref.watch(libraryProvider).value ?? const LibraryState();
    final persisted = (remote?.subscriptionArtists ?? library.artists).any(
      (item) => item.name == video.artist,
    );
    final subscribed =
        ref.watch(subscriptionOverrideProvider(video.id)) ?? persisted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        solidColor: theme.colorScheme.surfaceContainerLow,
        child: PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // 条件同时写进 URL：`extra` 在路由重建后可能丢掉（go_router 不保证），
            // 那时作者页会退化成「没有作者名」的空页，看起来就是点了作者没内容。
            //
            // 播放窗口里改走信箱投递：就地 push 会把作者页整页盖在正在播的画面上
            // （用户报的就是这个——点作者头像后视频被挡住）。交给主窗口打开，
            // 播放窗口继续放。
            onTap: () {
              if (isPlayWindowProcess) {
                unawaited(postOpenAuthorRequest(video.artist!));
                return;
              }
              context.push(
                Uri(
                  path: '/author',
                  queryParameters: {'name': video.artist!},
                ).toString(),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    backgroundImage: video.artistAvatarUrl == null
                        ? null
                        : appNetworkImage(video.artistAvatarUrl!),
                    child: video.artistAvatarUrl == null
                        ? Text(
                            video.artist!.characters.first,
                            style: theme.textTheme.titleMedium,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(video.artist!, style: theme.textTheme.titleSmall),
                        Text(
                          AppLocalizations.of(context)!.studio,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: account == null
                        ? () => ref
                              .read(libraryProvider.notifier)
                              .setSubscription(video, !subscribed)
                        : video.artistId == null ||
                              (video.csrfToken ?? account.csrfToken) == null ||
                              (video.subscriptionUserId ??
                                      video.currentUserId ??
                                      account.id) ==
                                  null
                        ? null
                        : () => _setSubscription(
                            ref,
                            video.csrfToken ?? account.csrfToken!,
                            video.subscriptionUserId ??
                                video.currentUserId ??
                                account.id!,
                            video.artistId!,
                            !subscribed,
                          ),
                    child: Text(
                      subscribed
                          ? AppLocalizations.of(context)!.subscribed
                          : AppLocalizations.of(context)!.subscribe,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setSubscription(
    WidgetRef ref,
    String token,
    String userId,
    String artistId,
    bool enabled,
  ) async {
    ref.read(subscriptionOverrideProvider(video.id).notifier).state = enabled;
    try {
      final settings = await ref.read(settingsProvider.future);
      await ref
          .read(han1meRepositoryProvider)
          .setSubscription(
            settings.resolvedBaseUrl,
            token,
            userId,
            artistId,
            enabled,
          );
      ref.invalidate(remoteLibraryProvider);
    } catch (_) {
      ref.read(subscriptionOverrideProvider(video.id).notifier).state =
          !enabled;
    }
  }
}

class _Description extends StatelessWidget {
  const _Description({
    required this.video,
    required this.onToggle,
    this.compact = false,
  });

  final VideoDetail video;
  final VoidCallback onToggle;

  /// 为 true 时不再叠加 `_gridPad` 页边距与宽度上限：
  /// 两栏版式里它直接铺满左列 640 宽（设计稿简介卡 x=204 w=640）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final description = video.description ?? '';
    final l10n = AppLocalizations.of(context)!;
    if (description.isEmpty) return const SizedBox.shrink();
    final card = AnimatedSize(
      duration: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: GlassPanel(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        solidColor: Theme.of(context).colorScheme.surfaceContainerLow,
        child: PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (video.uploader case final uploader?) ...[
                    Text(
                      '${l10n.uploader}: $uploader',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (video.captionTitle case final title?) ...[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(description),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (compact) return card;
    return Align(
      alignment: Alignment.topLeft,
      // 和播放器同一个宽度上限：两边各让出 _gridPad 的边距，卡片本体才是 640。
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _videoStageMaxWidth + _gridPad * 2,
        ),
        child: Padding(
          // 与播放器共用同一组页边距，简介卡才是和播放器等宽的一道。
          padding: const EdgeInsets.fromLTRB(_gridPad, 8, _gridPad, 8),
          child: card,
        ),
      ),
    );
  }
}

class _TagList extends ConsumerStatefulWidget {
  const _TagList({required this.video});

  final VideoDetail video;

  @override
  ConsumerState<_TagList> createState() => _TagListState();
}

class _TagListState extends ConsumerState<_TagList> {
  bool _expanded = false;

  Future<void> _editTags(String mode) async {
    await context.push('/video/${widget.video.id}/tags/$mode');
    ref.invalidate(videoDetailProvider(widget.video.id));
  }

  void _openTagScoped(int index) {
    final tags = widget.video.tags;
    final href = tags[index].href;
    final uri = href == null
        ? Uri(path: '/search', queryParameters: {'tags[]': tags[index].name})
        : Uri.parse(href);
    final url = Uri(
      path: uri.path,
      queryParameters: uri.queryParameters.isEmpty
          ? {'tags[]': tags[index].name}
          : uri.queryParameters,
    ).toString();
    context.push(url, extra: SearchRouteRequest(initialUrl: url));
  }

  String _chipLabel(int index) {
    final tags = widget.video.tags;
    final catalog = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final localeKey = searchOptionLocaleKey(Localizations.localeOf(context));
    final name = catalog?.localizeTag(tags[index].name, localeKey) ?? tags[index].name;
    return tags[index].count == null ? name : '$name (${tags[index].count})';
  }

  Widget _chip(int index) {
    // 用 IntrinsicWidth 按内容自然撑宽：展开态用 Wrap 时父级是无界宽度约束，
    // 直接放 PressScale/Container 会被撑满整行（标签竖排成列的 bug）；写死宽度又
    // 会把文字挤成省略号。IntrinsicWidth 正好取两者之间——按文字实际宽度排。
    return IntrinsicWidth(
      child: SizedBox(
        height: 24,
        child: PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => _openTagScoped(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppDesignTokens.fieldFillOf(context),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                _chipLabel(index),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontSize: 11, color: AppDesignTokens.inkSubtleOf(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 精确测量一颗 chip 的宽度（11px 字号 + 水平 padding 20）。
  double _chipWidth(int index) {
    final tp = TextPainter(
      text: TextSpan(
        text: _chipLabel(index),
        style: const TextStyle(fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width + 20; // 左右各 10 的 padding
    tp.dispose();
    return w;
  }

  /// 标签行：默认单行，能放几颗放几颗（撑满整行），多余的隐藏，末尾给「⋯」；
  /// 点「⋯」在**原位展开成多排**显示全部，再点收起。
  @override
  Widget build(BuildContext context) {
    final tags = widget.video.tags;
    final account = ref.watch(accountProvider).valueOrNull;
    final enabled =
        account != null &&
        (widget.video.csrfToken ?? account.csrfToken) != null;
    if (tags.isEmpty && !enabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;

        // 展开态：多排 Wrap 显示全部 + 收起按钮。
        if (_expanded) {
          return Wrap(
            spacing: gap,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < tags.length; i++) _chip(i),
              _collapseButton(),
            ],
          );
        }

        // 收起态：单行。算出这一行放得下几颗，给末尾「⋯」留位置。
        final maxWidth = constraints.maxWidth;
        final widths = [for (var i = 0; i < tags.length; i++) _chipWidth(i)];
        const moreWidth = 28.0; // 「⋯」按钮
        var used = 0.0;
        var visible = 0;
        for (var i = 0; i < widths.length; i++) {
          final add = widths[i] + (i == 0 ? 0 : gap);
          final hasMore = (i + 1) < widths.length;
          final reserve = hasMore ? moreWidth + gap : 0;
          if (used + add + reserve > maxWidth) break;
          used += add;
          visible++;
        }
        if (visible == 0 && tags.isNotEmpty) visible = 1;
        final hidden = tags.length - visible;

        return Row(
          children: [
            Expanded(
              child: ClipRect(
                child: Row(
                  children: [
                    for (var i = 0; i < visible; i++)
                      Padding(
                        padding: EdgeInsets.only(right: gap),
                        child: _chip(i),
                      ),
                  ],
                ),
              ),
            ),
            if (hidden > 0)
              PressScale(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => setState(() => _expanded = true),
                  child: Container(
                    width: 28,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.fieldFillOf(context),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Symbols.more_horiz_rounded,
                      size: 16,
                      color: AppDesignTokens.inkSubtleOf(context),
                    ),
                  ),
                ),
              )
            else if (enabled)
              PressScale(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => _editTags('add'),
                  child: Container(
                    width: 28,
                    height: 24,
                    alignment: Alignment.center,
                    child: Icon(
                      Symbols.add_rounded,
                      size: 16,
                      color: AppDesignTokens.inkMutedOf(context),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _collapseButton() => PressScale(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => setState(() => _expanded = false),
      child: Container(
        width: 28,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppDesignTokens.fieldFillOf(context),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          Symbols.keyboard_arrow_up_rounded,
          size: 16,
          color: AppDesignTokens.inkSubtleOf(context),
        ),
      ),
    ),
  );
}

class _SeriesVideos extends StatefulWidget {
  const _SeriesVideos({required this.videos, required this.currentVideoId});

  final List<VideoCard> videos;
  final String currentVideoId;

  @override
  State<_SeriesVideos> createState() => _SeriesVideosState();
}

class _SeriesVideosState extends State<_SeriesVideos> {
  var _reversed = false;

  @override
  Widget build(BuildContext context) {
    // 设计稿「选集」：标题 14 SemiBold + `共 N 集` 11 灰，下面是 4 列按钮网格
    // （74×36 圆角8、浅灰底，当前集粉色底白字）。不再是旧的横排缩略图小卡。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 0, bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '选集',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '共 ${widget.videos.length} 集',
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.inkMutedOf(context),
                ),
              ),
              const Spacer(),
              // 设计稿这里是「倒序 ⇅」，不是「查看更多」。
              PressScale(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  onTap: () => setState(() => _reversed = !_reversed),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _reversed ? '正序' : '倒序',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppDesignTokens.inkMutedOf(context),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Symbols.swap_vert_rounded,
                          size: 14,
                          color: AppDesignTokens.inkMutedOf(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const cols = 4;
            const gap = 8.0;
            final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < _ordered.length; i++)
                  Builder(
                    builder: (context) {
                      final v = _ordered[i];
                      final selected = v.id == widget.currentVideoId;
                      return PressScale(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () => context.push('/video/${v.id}'),
                          child: Container(
                            width: w,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppDesignTokens.accentDeep
                                  : AppDesignTokens.fieldFillOf(context),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              // 设计稿「选集」格子里是**编号**（01/02/03…），
                              // 不是视频标题：标题长度不一，塞进 74×36 的格子里
                              // 全被省略号吃掉，一排看过去分不出哪一集。
                              '${i + 1}'.padLeft(2, '0'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // 设计稿 epText：13 号居中。
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? Colors.white
                                    : AppDesignTokens.inkSubtleOf(context),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<VideoCard> get _ordered => _reversed
      ? widget.videos.reversed.toList(growable: false)
      : widget.videos;
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({required this.video});

  final VideoCard video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      solidColor: theme.colorScheme.surfaceContainerLow,
      child: PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: video.id.isEmpty
              ? null
              : () => context.push('/video/${video.id}'),
          child: Padding(
            // 设计稿 relCard 72 高、缩略图 114×64，上下各留 4。
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: 114,
                    height: 64,
                    child: AppCachedNetworkImage(
                      imageUrl: video.coverUrl,
                      fit: BoxFit.cover,
                      faceFocus: true,
                      placeholder: (context, url) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Symbols.broken_image_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (video.artist != null)
                        Text(
                          video.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      if (video.views != null)
                        Text(
                          video.views!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
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

/// 标题最多两行；放不下就从中间截断（保留首尾、用「……」连接），比只在末尾省略更容易认出标题
class _TitleText extends StatelessWidget {
  const _TitleText({
    required this.text,
    required this.style,
    required this.expanded,
  });

  /// 标题最多显示两行。原来是个可传参数，但唯一调用点从没传过值 ——
  /// 留着只会让后来人以为「这里能调」，收成常量后语义不变。
  static const int _maxLines = 2;

  final String text;
  final TextStyle style;

  /// 展开详情时标题显示完整，不再中间省略
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (expanded) return Text(text, style: style);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0)
          return Text(
            text,
            maxLines: _maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        bool fits(String candidate) {
          final painter = TextPainter(
            text: TextSpan(text: candidate, style: style),
            maxLines: _maxLines,
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: constraints.maxWidth);
          final ok = !painter.didExceedMaxLines;
          painter.dispose();
          return ok;
        }

        if (fits(text))
          return Text(
            text,
            maxLines: _maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
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
          final candidate =
              '${characters.take(head).join()}$marker${tail > 0 ? characters.skip(characters.length - tail).join() : ''}';
          if (fits(candidate)) {
            best = candidate;
            low = total + 1;
          } else {
            high = total - 1;
          }
        }
        return Text(
          best,
          maxLines: _maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// v6 设计稿的详情页分栏布局：
/// 左列 = 播放器 + 简介 + 评论；右栏 = 信息 + 选集 + 相关推荐。
class VideoDetailSplitView extends ConsumerStatefulWidget {
  const VideoDetailSplitView({
    super.key,
    required this.video,
    required this.sidebarWidth,
    required this.onBack,
    this.onHome,
    this.onPrevious,
    this.onNext,
    this.onEpisodeSelected,
    this.hidePlayerTopBar = false,
  });

  final VideoDetail video;
  final double sidebarWidth;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;
  final bool hidePlayerTopBar;

  @override
  ConsumerState<VideoDetailSplitView> createState() =>
      _VideoDetailSplitViewState();
}

class _VideoDetailSplitViewState extends ConsumerState<VideoDetailSplitView> {
  var _descriptionExpanded = true;

  /// 是否已经点过「播放」。
  ///
  /// 设计稿 `base_videodetail.png` 的播放器区域是**封面占位 + 居中播放按钮**，
  /// 不是一进来就开始加载播放器：进详情页先看封面，点了播放才创建播放器。
  var _playing = false;

  /// 「播放」：默认弹独立播放窗口，拉不起来才回退内嵌播放器。
  Future<void> _play(BuildContext context, VideoDetail video) async {
    final opened = await openVideoInPlayWindow(context, ref, video.id);
    if (opened) return;
    if (!mounted) return;
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final l10n = AppLocalizations.of(context)!;
    final description = video.description ?? '';
    final related = visibleRelatedVideos(ref, video.related);
    final hasDetails =
        description.isNotEmpty ||
        video.uploader != null ||
        video.captionTitle != null;
    void toggleDescription() =>
        setState(() => _descriptionExpanded = !_descriptionExpanded);
    // 设计稿 `design_detail.png`：**两栏**版式，整页纵向滚动。
    //   顶栏：← 返回 + 视频标题（左对齐），右侧 收藏/下载/更多 三枚图标
    //   主体 Row（宽 1048 居中）：
    //     左列 640：16:9 封面 → 简介 → 评论
    //     间隙 48
    //     右列 360：标题 → 作者 → 数据 → 播放+操作 → 标签 → 选集 → 相关推荐
    // 尺寸/间距全部取自 `detail_spec.txt`（封面 x=204 w=640、右栏 x=892 w=360，
    // 即 640 + 48 + 360 = 1048）。
    const double leftColWidth = 640;
    const double rightColWidth = 360;
    const double colGap = 48;
    const double contentWidth = leftColWidth + colGap + rightColWidth;

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftColWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _playing
                  ? ColoredBox(
                      color: Colors.black,
                      child: VideoPlayerPanel(
                        video: video,
                        onBack: widget.onBack,
                        onHome: widget.onHome,
                        onPrevious: widget.onPrevious,
                        onNext: widget.onNext,
                        onEpisodeSelected: widget.onEpisodeSelected,
                        hideTopBar: true,
                      ),
                    )
                  : _CoverStage(
                      coverUrl: video.coverUrl,
                      title: video.title,
                      onPlay: () => _play(context, video),
                    ),
            ),
          ),
        ),
        if (hasDetails) ...[
          const SizedBox(height: 24),
          Text(
            '简介',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.inkOf(context),
            ),
          ),
          const SizedBox(height: 10),
          _Description(
            video: video,
            onToggle: toggleDescription,
            compact: true,
          ),
        ],
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '评论',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.inkOf(context),
              ),
            ),
            if (video.commentCount != null) ...[
              const SizedBox(width: 6),
              Text(
                '· ${video.commentCount}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppDesignTokens.inkMutedOf(context),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // 评论容器高度随文字缩放，放大后评论行不被固定高裁掉，上限取视口高。
        SizedBox(
          height: AppResponsive.scaled(context, 520).clamp(
            0.0,
            MediaQuery.sizeOf(context).height,
          ),
          child: VideoCommentsView(video: video),
        ),
        const SizedBox(height: 32),
      ],
    );

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SideTitle(video: video),
        const SizedBox(height: 12),
        _SideAuthor(video: video),
        const SizedBox(height: 12),
        _SideStats(video: video),
        const SizedBox(height: 14),
        VideoActionRow(video: video),
        const SizedBox(height: 14),
        _TagList(video: video),
        if (video.playlist.isNotEmpty) ...[
          const SizedBox(height: 20),
          Divider(height: 1, thickness: 1, color: AppDesignTokens.dividerOf(context)),
          const SizedBox(height: 14),
          _SeriesVideos(videos: video.playlist, currentVideoId: video.id),
        ],
        if (related.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l10n.relatedVideos,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.inkOf(context),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in related)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RelatedVideoTile(video: item),
            ),
        ],
        const SizedBox(height: 32),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailTopBar(
          title: video.title,
          onBack: widget.onBack,
          onHome: widget.onHome,
          video: video,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final wide = viewport.maxWidth >= contentWidth + _gridPad * 2;
              final body = wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: leftColWidth, child: leftColumn),
                        const SizedBox(width: colGap),
                        SizedBox(width: rightColWidth, child: rightColumn),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        leftColumn,
                        const SizedBox(height: 24),
                        rightColumn,
                      ],
                    );
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_gridPad, 8, _gridPad, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: contentWidth),
                      child: body,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 未播放时的播放器占位：封面铺底压暗 + 居中播放按钮。
///
/// 设计稿的播放器区域**不是一块纯黑**，而是封面占位（深色、圆角）+ 中间一个
/// 播放按钮；点了它才开始加载播放器。这样进详情页不会立刻转圈等视频。
class _CoverStage extends StatelessWidget {
  const _CoverStage({
    required this.coverUrl,
    required this.title,
    required this.onPlay,
  });

  final String? coverUrl;
  final String title;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if ((coverUrl ?? '').isNotEmpty)
          AppCachedNetworkImage(
            imageUrl: coverUrl!,
            fit: BoxFit.cover,
            faceFocus: true,
            placeholder: (context, url) =>
                const ColoredBox(color: Color(0xFF1B1B1F)),
            errorWidget: (context, url, error) =>
                const ColoredBox(color: Color(0xFF1B1B1F)),
          )
        else
          const ColoredBox(color: Color(0xFF1B1B1F)),
        // 压暗一层，播放按钮才在亮封面上也看得清。
        const ColoredBox(color: Color(0x66000000)),
        Center(
          child: PressScale(
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPlay,
              child: Container(
                // 设计稿 `553_videoDetail.png`：白色实心圆 + 品红 ▶，
                // 不是描边圆环。实心圆在深色封面上更醒目，也更接近 v6 的按钮语言。
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.play_arrow_rounded,
                  size: 26,
                  color: AppDesignTokens.accentDeep,
                ),
              ),
            ),
          ),
        ),
        // 设计稿播放器底部：一条品红进度条 + `08:12 / 19:30` 时间胶囊。
        // 未播放时没有真实进度，给一条极短的"起点"与占位时长，只作视觉对齐，
        // 不编造具体播放时间（数据时来自详情页解析，这里不写死示例值）。
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 3,
                width: 168,
                decoration: const BoxDecoration(
                  color: AppDesignTokens.accentDeep,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(AppRadius.xs),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  '00:00 / --:--',
                  style: TextStyle(fontSize: 10.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 右栏右上角的三个圆形图标（设计稿：♡ / 😊 / ⋯，浅灰圆底）。
///
/// 复用 [videoActionsFor] 里真实的收藏/下载/分享，不另造装饰性按钮。
class _SideTopIcons extends ConsumerWidget {
  const _SideTopIcons({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = videoActionsFor(context, ref, video);
    final icons = actions.length > 1
        ? actions.sublist(1).take(3).toList()
        : const <VideoAction>[];
    if (icons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final action in icons)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: PressScale(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: action.onPressed,
                  child: Container(
                    // 设计稿 act/*：32×32、圆角 8 的方块（不是圆形）。
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.fieldFillOf(context),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: BouncyToggleIcon(
                      icon: action.icon,
                      size: 16,
                      filled: action.filled,
                      color: action.onPressed == null
                          ? AppDesignTokens.inkMutedOf(context)
                          : AppDesignTokens.inkSubtleOf(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 详情页顶部独立标题行：← 返回 + 视频标题（设计稿里它不压在画面上）。
const double _gridPad = 20;

/// 播放器宽度上限。叠加比对 + 像素实测：设计稿播放器水平 228..867，即 640 宽，
/// 高度 360，正好 16:9。
const double _videoStageMaxWidth = 640;

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.title,
    required this.onBack,
    this.onHome,
    this.video,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onHome;
  final VideoDetail? video;

  @override
  Widget build(BuildContext context) {
    // 设计稿：backBtn x=204（页面左边距 28 + 侧栏 176）、pageTitle x=248（= 204+32+12）。
    // 顶栏左右各留 _gridPad，并且**两边都占位**：右侧没有图标时也留出同样宽度，
    // 标题才不会一路顶到右缘。
    const double trailingWidth = 3 * 32 + 2 * 6;
    return SizedBox(
      // 像素实测：设计稿标题文字落在 y=23~37，播放器上缘 y=64。
      // 这个顶栏在 SafeArea 里、不会自动让过自绘标题栏，所以要自己让出
      // `windowControlsHeight`（28）—— 否则整行会顶到窗口按钮上。
      // 28 + 56 = 84，标题正落在设计稿的高度上。
      height: AppDesignTokens.windowControlsHeight + 56,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _gridPad,
          AppDesignTokens.windowControlsHeight,
          _gridPad,
          0,
        ),
        child: Row(
          children: [
            PressScale(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: onBack,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Symbols.arrow_back_rounded,
                    size: 20,
                    color: AppDesignTokens.inkOf(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
            ),
            // 设计稿 act/*：和标题同一行、右对齐，三枚 32×32 圆角 8 的浅灰方块。
            const SizedBox(width: 16),
            if (video case final v?)
              _SideTopIcons(video: v)
            else
              const SizedBox(width: trailingWidth),
          ],
        ),
      ),
    );
  }
}

/// 右栏标题：设计稿 sideTitle 16 SemiBold 墨色。
class _SideTitle extends StatelessWidget {
  const _SideTitle({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Text(
      video.title,
      // 设计稿 sideTitle 高 21 = **一行**。之前写 2 行，长标题一换行就把
      // 作者/统计/按钮/标签/选集整体往下顶 21，整列节奏全乱。
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // 设计稿 sideTitle：fs 16（x=892 y=108 w=360）。
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppDesignTokens.inkOf(context),
      ),
    ),
  );
}

/// 右栏作者行：26 圆角头像 + 名字 13 灰 + 右侧日期 11 更淡。
class _SideAuthor extends ConsumerWidget {
  const _SideAuthor({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((video.artist ?? '').isEmpty && video.uploadDate == null)
      return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFFBE9EF),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: (video.artistAvatarUrl?.isNotEmpty ?? false)
                ? Image(
                    image: appNetworkImage(video.artistAvatarUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              video.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.inkSubtleOf(context),
              ),
            ),
          ),
          if (video.uploadDate != null)
            Text(
              video.uploadDate!,
              style: TextStyle(
                fontSize: 11,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
        ],
      ),
    );
  }
}

/// 右栏数据行：浏览量 / 点赞率 / 收藏数。
class _SideStats extends StatelessWidget {
  const _SideStats({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          if (video.views != null) ...[
            Icon(
              Symbols.play_circle_rounded,
              size: 14,
              color: AppDesignTokens.inkMutedOf(context),
            ),
            const SizedBox(width: 4),
            Text(
              video.views!,
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
            const SizedBox(width: 16),
          ],
          if (video.rating != null) ...[
            const Icon(
              Symbols.thumb_up_rounded,
              size: 14,
              color: AppDesignTokens.accentDeep,
            ),
            const SizedBox(width: 4),
            Text(
              video.rating!,
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.accentDeep,
              ),
            ),
            const SizedBox(width: 16),
          ],
          if (video.commentCount != null) ...[
            const Icon(
              Symbols.favorite_border_rounded,
              size: 14,
              color: AppDesignTokens.accentDeep,
            ),
            const SizedBox(width: 4),
            Text(
              '${video.commentCount}',
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.accentDeep,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
