import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_motion.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/video_meta_cache.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../video/play_window.dart';
import 'press_scale.dart';
import 'app_image_cache.dart';
import 'hover_preview.dart';

int videoCardCacheWidth(double cardWidth, double devicePixelRatio) =>
    (cardWidth * devicePixelRatio).round().clamp(240, 480).toInt();

/// 视频卡片统一圆角：卡片本体、封面切口与选中描边共用这一个值，
/// 避免几处各写一个数字后慢慢走样。
const videoCardRadius = 8.0;

/// 封面下方详情区的预留高度：标题两行(40) + 间隙(6) + 作者(16) + 间隙(4) + 评分行(16) + 底距(2)。
///
/// 原值是 120，比实际内容高出 40 多像素 —— 卡片底部会空出一大块，
/// 加上投影之后看起来像"卡片下面还有一层"。这里收到贴近实际内容的高度，
/// 卡片按真实内容收口（`_details` 自身 overflow 由外层 ClipRect 兜底）。
/// 行间距从 2/2 放宽到 6/4、并加了 2px 内边距之后，这个值同步抬高，否则会裁掉评分行。
const _horizontalCardMetaHeight = 92.0;

/// 站点有些分类列表（如里番、泡麵番）只给封面和标题，卡片下方不需要留出两行空间。
const _horizontalCardCompactMetaHeight = 84.0;

/// 该卡片是否带作者 / 评分 / 上传时间。
bool hasVideoCardMeta(VideoCard video) =>
    video.artist != null || video.rating != null || video.uploadTime != null;

/// 一批卡片在封面下方需要的高度（整批都没有 meta 时用矮一点的值）。
/// [assumeMeta] 为真时按完整高度算（卡片会去详情页补全信息）。
double videoCardMetaHeight(
  Iterable<VideoCard> videos, {
  bool assumeMeta = false,
}) => assumeMeta || videos.any(hasVideoCardMeta)
    ? _horizontalCardMetaHeight
    : _horizontalCardCompactMetaHeight;

/// 简单并发闸门：补全卡片信息会同时发起不少详情页请求，限制同时在跑的个数。
class _RequestGate {
  _RequestGate(this.maxConcurrent);

  final int maxConcurrent;
  var _active = 0;
  final _waiting = <Completer<void>>[];

  Future<void> enter() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void leave() {
    if (_waiting.isEmpty) {
      _active--;
    } else {
      _waiting.removeAt(0).complete();
    }
  }
}

final _metaGate = _RequestGate(6);

/// 站点有些分类列表（里番、泡麵番）只给封面和标题，
/// 这些卡片用详情页把时长/播放量/作者/评分/视频截图补回来，结果写进 [VideoMetaCache]。
/// 缓存命中时不会再发请求，所以刷新、滚动来回、重启都直接有值。
final videoCardMetaProvider = FutureProvider.autoDispose
    .family<VideoCard, String>((ref, id) async {
      // 预热时不一定有卡片在监听，靠缓存（内存 + 磁盘）就足够，不需要重复进入并发闸门。
      ref.keepAlive();
      final cache = ref.watch(videoMetaCacheProvider);
      final cached = cache.read(id);
      if (cached != null) return cached;
      final settings = await ref.watch(settingsProvider.future);
      final repository = ref.watch(han1meRepositoryProvider);
      await _metaGate.enter();
      try {
        final detail = await repository.video(settings.resolvedBaseUrl, id);
        final meta = VideoCard(
          id: id,
          title: detail.title,
          coverUrl: detail.coverUrl ?? '',
          duration: detail.duration,
          views: detail.views,
          rating: detail.rating,
          artist: detail.artist,
          uploadTime: detail.uploadDate,
          tags: detail.tags
              .map((tag) => tag.name)
              .where((tag) => tag.isNotEmpty)
              .toList(growable: false),
        );
        await cache.put(meta);
        return meta;
      } finally {
        _metaGate.leave();
      }
    });

class VideoCardMetrics {
  const VideoCardMetrics({
    required this.horizontal,
    required this.cardsPerRow,
    required this.cardWidth,
    required this.cardHeight,
  });

  final bool horizontal;
  final int cardsPerRow;
  final double cardWidth;
  final double cardHeight;
}

VideoCardMetrics videoCardMetrics({
  required double viewportWidth,
  required bool horizontal,
  required int cardsPerRow,
  required bool expanded,
}) {
  const spacing = 10.0;
  const padding = 32.0;
  if (expanded) {
    final effective = viewportWidth >= 1200
        ? (viewportWidth / 300).floor().clamp(cardsPerRow, 6).toInt()
        : cardsPerRow;
    final cardWidth =
        (viewportWidth - padding - spacing * (effective - 1)) / effective;
    final cardHeight = horizontal
        ? cardWidth * 9 / 16 + _horizontalCardMetaHeight
        : cardWidth / .58;
    return VideoCardMetrics(
      horizontal: horizontal,
      cardsPerRow: effective,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
    );
  }
  final desktop = viewportWidth >= 700;
  final cardWidth = horizontal
      ? (desktop ? 220.0 : 154.0)
      : (desktop ? 170.0 : 132.0);
  final cardHeight = horizontal
      ? cardWidth * 9 / 16 + _horizontalCardMetaHeight
      : cardWidth / .58;
  return VideoCardMetrics(
    horizontal: horizontal,
    cardsPerRow: 1,
    cardWidth: cardWidth,
    cardHeight: cardHeight,
  );
}

/// 本次会话里点开过的视频 id：卡片标题会染成主题色，一眼能看出哪几张看过了。
///
/// 只放内存、不落盘 —— 真正的观看记录由 `WatchRepository` 负责（/library/history 那页）。
/// 这里要的是即时、可理解的反馈，刷新或重启就回到干净状态。
final openedVideoIdsProvider =
    NotifierProvider<OpenedVideoIdsNotifier, Set<String>>(
      OpenedVideoIdsNotifier.new,
    );

class OpenedVideoIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void mark(String id) {
    if (id.isEmpty || state.contains(id)) return;
    state = <String>{...state, id};
  }
}

/// 悬停时封面推近的幅度。
///
/// 只作用在图片上（外层 `ClipRRect` 不动），所以角标、描边和卡片占位都留在原位，
/// 观感是"图在框里推近"，而不是整张卡片被撑大 —— 后者会把邻居挤走。
const coverHoverScale = 1.06;

/// 整块封面的悬停状态：把 [builder] 需要的那一份状态集中在这里。
///
/// 为什么不给"推近的图片"和"角标"各挂一个 `MouseRegion`：角标是压在封面**上面**的，
/// 鼠标停在角标上时命中路径里没有下面那层，图片那层会以为鼠标走了 ——
/// 推近动画就会抖一下。这里整块封面只算一次悬停，角标只是它的消费者。
class _HoverZone extends StatefulWidget {
  const _HoverZone({required this.builder, this.onHoverChanged});

  final Widget Function(BuildContext context, bool hovered) builder;

  /// 鼠标进入 / 离开封面。悬停预览靠它排定与收尾。
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<_HoverZone> createState() => _HoverZoneState();
}

class _HoverZoneState extends State<_HoverZone> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    widget.onHoverChanged?.call(value);
  }

  @override
  void dispose() {
    // 悬停中途卡片被移出树（滚走了 / 换页了）不会再有 onExit，
    // 不补这一下就会留一个静音播放器在后台一直解码。
    if (_hovered) widget.onHoverChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _setHovered(true),
    onExit: (_) => _setHovered(false),
    child: widget.builder(context, _hovered),
  );
}

/// 封面角标（时长 / 播放量）在悬停时淡出。
///
/// 悬停会同时把封面推近、并在停稳 1.5 秒后在里面放预览画面；角标压在最上面会正好
/// 挡在那块画面上。BiliDesk 的首页卡片也是悬停即淡出，他们在源码里写的理由是
/// 「放大的是封面，角标压在上面会挡住画面 —— 这也是 B 站网页版的行为」。
///
/// 淡出比淡入快一档：移开鼠标时希望角标干脆地回来，而不是慢慢浮上来。
/// 外面套 [IgnorePointer]：角标本来就不该可点（点它等于点卡片），
/// 顺带保证鼠标停在角标上时整块封面的悬停状态不会断。
class _CoverBadgeFade extends StatelessWidget {
  const _CoverBadgeFade({required this.hovered, required this.child});

  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: hovered ? 0 : 1,
      duration: motionDuration(
        context,
        hovered ? AppMotion.quick : AppMotion.standard,
      ),
      curve: AppMotion.standardCurve,
      child: child,
    ),
  );
}

/// 封面上的悬停预览：要额外铺的一层画面 + 鼠标进出的回调。
///
/// 画面和回调必须成对传：只给画面不给回调，那个画面永远不会出现。
class _CoverHover {
  const _CoverHover({
    this.surface,
    this.onHoverChanged,
    this.preparing = false,
  });

  final Widget? surface;
  final ValueChanged<bool>? onHoverChanged;

  /// 已在为这张卡抓详情 / 起播放器，但画面还没出来。
  ///
  /// 这一步在真机上实测要 3～11 秒（详情页 ~2.6s + `initialize()` 缓冲 2.6~11s），
  /// 不给提示的话用户会以为"悬停播放这个功能没了"，所以封面中央放一个小转圈。
  final bool preparing;
}

class VideoCardTile extends ConsumerWidget {
  const VideoCardTile({
    super.key,
    required this.video,
    this.horizontal = false,
    this.selected = false,
    this.dense = false,
    this.fillCover = false,
    this.coverAspectRatio,
    this.autoFetchMeta = false,
    this.onTap,
    this.onLongPress,
    this.coverImage,
  });

  final VideoCard video;
  final bool horizontal;
  final bool selected;

  /// 小卡片（侧栏「系列影片」）用：字号、间距、角标都缩小一号
  final bool dense;

  /// 固定高度的网格里让封面吃掉剩余高度（高度不够时裁切图片，而不是撑破卡片）
  final bool fillCover;

  /// 封面比例（宽 / 高）。"新番预告"这类结果给的是竖版海报（实测 268x394），
  /// 不指定时会按 16:9 排版 → 海报被缩放到铺满宽度再上下裁掉，只剩中间一条。
  /// 传了比例就让封面按这个比例占位（网格用 [VideoCardGrid.coverAspectRatio] 同步算卡高）。
  final double? coverAspectRatio;

  /// 卡片没有作者/评分时去详情页补（站点部分分类列表只给封面和标题）。
  /// 搜索结果页不用它，保持只显示站点列表给出的内容。
  final bool autoFetchMeta;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ImageProvider? coverImage;

  /// 需要补全时用详情页的数据填掉缺的字段。
  /// 命中本地缓存时是同步的，所以刷新后卡片会直接显示补全后的内容。
  VideoCard _resolved(WidgetRef ref) {
    if (!autoFetchMeta || video.id.isEmpty) return video;
    // AV 源的列表页自己就带标题/封面/时长/播放量/作者，不需要补 —— 而且**不能**补：
    // 一屏十几张卡片各抓一次详情页会把站点打到 Cloudflare 限流（实测 jable 直接
    // 返回 Error 1015），限流期间站点给的是「Page not Found」错误页，那张页面的
    // logo 又会被当成封面写进缓存 —— 表现就是整屏卡片用同一张占位图。
    if (javSiteFor(
          ref.watch(settingsProvider).valueOrNull?.homeBaseUrl ?? '',
        ) !=
        null) {
      return video;
    }
    // 缓存优先，而且**要在 `hasVideoCardMeta` 之前**：上传日期只有详情页才有
    // （列表页解析只给作者与评分），原来"信息够了就直接返回"的写法让日期永远补不上。
    // 本地缓存里已有 1200+ 条带日期的记录，同步命中即可，不发请求。
    final cached = ref.watch(videoMetaCacheProvider).read(video.id);
    if (cached != null) return _mergeMeta(cached);
    // 卡片已经有日期就不再抓详情；没有则补一次（并发由 `_metaGate` 限到 6，结果落盘）。
    if (video.uploadTime != null) return video;
    final fetched = ref.watch(videoCardMetaProvider(video.id)).valueOrNull;
    return fetched == null ? video : _mergeMeta(fetched);
  }

  /// 补全信息以详情页为准（封面换成视频内容截图，而不是列表页给的海报）。
  VideoCard _mergeMeta(VideoCard meta) => VideoCard(
    id: video.id,
    title: video.title,
    coverUrl: meta.coverUrl.isEmpty ? video.coverUrl : meta.coverUrl,
    duration: meta.duration ?? video.duration,
    views: meta.views ?? video.views,
    rating: meta.rating ?? video.rating,
    artist: meta.artist ?? video.artist,
    uploadTime: meta.uploadTime ?? video.uploadTime,
    tags: meta.tags.isEmpty ? video.tags : meta.tags,
  );

  /// 悬停预览在卡片这一侧的全部接线。
  _CoverHover _coverHover(WidgetRef ref, HoverPreviewState preview) {
    // 回调捕获的是 notifier 本身（不是 WidgetRef）：卡片被移出树时
    // `_HoverZoomState.dispose` 还会调一次，那时不该再碰 ref。
    final notifier = ref.read(hoverPreviewProvider.notifier);
    return _CoverHover(
      // 只有「这一张正在播」时才铺画面：playingId 变成它的那一刻播放器已经初始化好了。
      surface: preview.playingId == video.id
          ? notifier.player?.buildSurface()
          : null,
      // 鼠标停在这张上、但画面还没出来 —— 卡片据此在封面里显示"正在准备"。
      preparing: preview.hoveredId == video.id && preview.playingId != video.id,
      onHoverChanged: (hovered) {
        if (hovered) {
          notifier.hover(video.id);
        } else {
          notifier.unhover(video.id);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolved(ref);
    // 点开过的卡片标题染主题色（会话级，见 openedVideoIdsProvider）。
    final marked = ref.watch(openedVideoIdsProvider).contains(video.id);
    // 悬停预览要 watch 状态才知道自己是不是"正在播的那一张"。
    final preview = ref.watch(hoverPreviewProvider);
    // 没有 id、或者详情页里的小卡片（dense）都不接预览：小卡片里既看不清，
    // 又要多起一路解码。
    final coverHover = video.id.isEmpty || dense
        ? const _CoverHover()
        : _coverHover(ref, preview);
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final cacheWidth = videoCardCacheWidth(
          constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
        );
        // 卡片本体不再铺底色：封面是独立的一块，文字直接落在页面底上（对齐 b 站首页卡片）。
        // 仍套一层**透明** Material —— InkWell 需要一个 Material 祖先才能画水波纹，
        // 但没有底色，就不会再出现"封面和文字同属一块白板"的两层感。
        return _HoverZone(
          // 整张卡片一个悬停状态，用来给标题换强调色（b 站与 BiliDesk 的卡片都是
          // 悬停即标题变色）。封面推近 / 角标淡出 / 悬停预览另有一个**更小**的悬停区
          // （`_cover` 里那个 `_HoverZone`）：只有鼠标真的压到封面上才开始抓详情，
          // 停在标题或空白处不该发请求。
          builder: (context, hovered) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Material(
              type: MaterialType.transparency,
              child: PressScale(child: InkWell(
                borderRadius: BorderRadius.circular(videoCardRadius),
                // InkWell 的悬停/按下灰罩在"无底卡片"上只能从文字区透出来，看起来
                // 就是「选中时下面变暗」（用户反馈的原话）。这里全部关掉：悬停反馈
                // 交给标题变色 + 封面推近，按下反馈交给 PressScale 的缩放。
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                // 统一入口：Windows 上按设置弹出独立播放窗口（b 站客户端行为），其余平台窗口内跳转。
                // 只在"点开视频"这条路径上记标记：库页多选模式下 onTap 被换成了选择，不算看过了。
                onTap:
                    onTap ??
                    (video.id.isEmpty
                        ? null
                        : () {
                            ref.read(openedVideoIdsProvider.notifier).mark(video.id);
                            openVideo(context, ref, video.id);
                          }),
                onLongPress: onLongPress,
                child: horizontal
                    ? _horizontalContent(
                        theme,
                        cacheWidth,
                        resolved,
                        marked,
                        coverHover,
                        hovered,
                      )
                    : _verticalContent(
                        theme,
                        cacheWidth,
                        resolved,
                        marked,
                        coverHover,
                        hovered,
                      ),
              )),
            ),
          ),
        );
      },
    );
  }

  Widget _verticalContent(
    ThemeData theme,
    int cacheWidth,
    VideoCard video,
    bool marked,
    _CoverHover hover,
    bool hovered,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _cover(theme, cacheWidth, video, hover)),
      const SizedBox(height: 8),
      _details(theme, video, marked, hovered),
    ],
  );

  Widget _horizontalContent(
    ThemeData theme,
    int cacheWidth,
    VideoCard video,
    bool marked,
    _CoverHover hover,
    bool hovered,
  ) {
    // 竖版海报结果（「新番预告」这类）：网格已按海报比例算好卡高，封面必须吃掉
    // 「除标题区以外的全部高度」。**详情区不能放在 Flexible 里** —— Flexible 默认 flex 1，
    // 会和封面的 Expanded 平分剩余高度：封面只剩一半（图被压扁、海报仍被裁），
    // 详情区用不完的那一半就变成卡片下方的一大块空白。
    if (coverAspectRatio != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cover(theme, cacheWidth, video, hover)),
          const SizedBox(height: 8),
          // 标题区是固定高度（详见 _details），不参与 flex 分配。
          ClipRect(child: _details(theme, video, marked, hovered)),
        ],
      );
    }
    // 封面吃掉剩余高度，详情区**不参与 flex 分配**：详情区按自然高度收在卡片底部，
    // 同一行里各卡片的作者行/评分行才会落在同一条水平线上（用户要求"取个平均值
    // 固定水平"）；一行标题省下的空间落进封面，而不是夹在标题与作者之间。
    // 原来这里是 AspectRatio(16/9) + Flexible：Flexible 默认 flex 1 会和封面平分
    // 高度，详情区在它那一半里顶部对齐 —— 标题一行还是两行，直接把作者行推到不同高度。
    // 站点有些分类只给封面和标题（例如里番的后续分页），这时封面同样撑满剩余高度，
    // 否则卡片下方会空出一段没有内容的区域。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _cover(theme, cacheWidth, video, hover)),
        SizedBox(height: dense ? 4 : 8),
        // 网格给的是固定卡高，详情区超出时裁剪而不是溢出报错
        ClipRect(child: _details(theme, video, marked, hovered)),
      ],
    );
  }

  Widget _cover(
    ThemeData theme,
    int cacheWidth,
    VideoCard video,
    _CoverHover hover,
  ) {
    // 选中态（详情页的"当前这一集"）改成给**封面**描一圈主题色：卡片底板已经去掉，
    // 再给整块（封面 + 文字）描边会连页面底色一起框住，看起来像一张没铺满的空卡。
    final highlight = selected ? theme.colorScheme.primary : null;
    return RepaintBoundary(
      child: ClipRRect(
        // 封面是独立的一块，四角都切圆角 —— 卡片底板没了，也就不存在"封面下缘从底上
        // 翘起一条缝"的问题（那正是当初"两层感"的来源，现在整张卡片本来就只有封面一层）。
        borderRadius: BorderRadius.circular(videoCardRadius),
        child: _HoverZone(
          onHoverChanged: hover.onHoverChanged,
          builder: (context, hovered) => Stack(
            fit: StackFit.expand,
            children: [
              // 图片本身在悬停时推近，裁切框（这一层 ClipRRect）不动。
              AnimatedScale(
                scale: hovered ? coverHoverScale : 1,
                duration: motionDuration(context, AppMotion.brief),
                curve: AppMotion.standardCurve,
                // 预览层排在缩放**里面**：它跟着封面一起被推近，观感是
                // 「这张封面动起来了」，而不是又叠了一块东西上去。
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverImage != null)
                      Image(image: coverImage!, fit: BoxFit.cover)
                    else
                      CachedNetworkImage(
                        imageUrl: video.coverUrl,
                        cacheManager: appImageCacheManager,
                        fit: BoxFit.cover,
                        memCacheWidth: cacheWidth,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (context, url) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Symbols.broken_image_rounded),
                          ),
                        ),
                      ),
                    if (hover.surface != null) hover.surface!,
                  ],
                ),
              ),
              // 正在为这张卡抓详情 / 起播放器 —— 真机实测这一步要 3～11 秒
              // （详情页约 2.6s，`initialize()` 缓冲 2.6~11s），不给提示的话用户会
              // 以为"悬停播放这个功能没了"（用户反馈原话）。用一小块深色底保证在
              // 任何封面上都看得见，且不整块压暗封面。
              if (hover.preparing)
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: SizedBox(
                        width: dense ? 12 : 16,
                        height: dense ? 12 : 16,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              if (video.duration != null)
                Positioned(
                  right: dense ? 3 : 6,
                  bottom: dense ? 3 : 6,
                  child: _CoverBadgeFade(
                    hovered: hovered,
                    child: _OverlayText(text: video.duration!, dense: dense),
                  ),
                ),
              if (video.views != null)
                Positioned(
                  left: dense ? 3 : 6,
                  bottom: dense ? 3 : 6,
                  child: _CoverBadgeFade(
                    hovered: hovered,
                    child: _OverlayText(
                      icon: Symbols.visibility_rounded,
                      text: video.views!,
                      dense: dense,
                    ),
                  ),
                ),
              // 封面贴边时给一圈内描边：深色封面直接压在页面底上会糊在一起，
              // 分不出「图到哪结束」。平时是 1px 极浅（浅色 black/10、深色 white/10，依据见
              // `docs/ui-polish.md` 的缩略图描边条目），选中时换成主题色 2px。
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: highlight ??
                            (theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black)
                                .withValues(alpha: .10),
                        width: highlight == null ? 1 : 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题区的高度：**固定两行**，与 B 站一样 —— 标题短也占两排空间。
  ///
  /// 为什么不能按标题实际行数留高：标题一行还是两行会改变卡片内容区的高度，于是同一行里
  /// 封面下沿、作者行、评分行全都跟着错位（用户截图反馈"视频封面怎么也是没对齐的"）。
  /// 标题本体仍是 `maxLines: 2` + 省略号，太长的标题第三行就被截成「…」。
  ///
  /// 为什么不拿标题本身去量行高：标题里带 emoji 时行高比纯文字更高，量出来会比别的卡多
  /// 一截，封面又对不齐 —— 这里固定用代表字符「国A」按同一套样式（含文字缩放）量一行高
  /// 再乘 2，每张卡拿到完全相同的高度。
  double _titleBoxHeight(BuildContext context, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: '国A', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height * 2;
  }

  /// 作者名做成可点的链接：点进作者页（`/search?query=<作者>`，与详情页作者卡同一条路径）。
  ///
  /// 为什么把条件同时写进 URL：`extra` 在路由重建后可能丢掉（go_router 不保证），那时
  /// 搜索页会退化成"没有关键词"的页，看起来就是点了作者没内容 —— 详情页作者卡踩过这个
  /// 坑，这里照抄同样的写法。悬停只用文字变主题色提示（与标题一致），不铺灰罩。
  Widget _artistLink(
    BuildContext context,
    ThemeData theme,
    String artist,
    Color ink,
  ) => _HoverZone(
    builder: (context, hovered) => PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        onTap: () {
          final url = Uri(
            path: '/search',
            queryParameters: {'query': artist},
          ).toString();
          context.push(
            url,
            extra: SearchRouteRequest(initialUrl: url, authorName: artist),
          );
        },
        child: Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: dense ? 10 : null,
            color: hovered ? theme.colorScheme.primary : ink,
          ),
        ),
      ),
    ),
  );

  Widget _details(
    ThemeData theme,
    VideoCard video,
    bool marked,
    bool hovered,
  ) {
    final hasMeta = hasVideoCardMeta(video);
    // 作者名 / 评分 / 上传时间原来是 `colorScheme.outline` —— 那是**描边**色，
    // 压在页面底上对比度只有 1.6:1 上下（用户反馈"下面的用户和时间对比度有些弱"）。
    // 正文级的次要文字该用 onSurfaceVariant。
    final metaInk = theme.colorScheme.onSurfaceVariant;
    // 标题在三种情况下染主题色：看过（会话级标记）、详情页里正在看的那一张、
    // 以及鼠标停在这张卡片上 —— b 站与 BiliDesk 的卡片都是「悬停即标题变强调色」。
    // 卡片本身不再铺底色、也不再用 InkWell 的灰色高亮提示悬停：那层灰只能从没有
    // 背景的文字区透出来，看起来就是"选中时下面变暗"（用户反馈的原话），
    // 现在改成颜色变化 + 封面推近。
    final accentTitle = marked || selected || hovered
        ? theme.colorScheme.primary
        : null;
    // 左右各让 2px、底部留 2px：文字原来是紧贴卡片边的（用户反馈"太贴边"）。
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleStyle = theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: accentTitle,
          );
          // 标题区固定两行高（见 `_titleBoxHeight`）：封面下沿、作者行、评分行才会对齐。
          final titleHeight = _titleBoxHeight(context, titleStyle);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dense)
                // 小卡片只留一行标题：短标题时不会在标题和作者名之间空一大截
                Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    // 点开过的卡片标题染主题色：一眼能看出哪几张看过了。
                    color: accentTitle,
                  ),
                )
              else
                SizedBox(
                  height: titleHeight,
                  child: Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
            if (hasMeta) ...[
              const SizedBox(height: 4),
              // 作者名 + 上传时间同一行：作者可点（进作者页），日期靠右（用户要求
              // "作者名右边加个视频上传时间，这样看着更平衡"）。这一行给**固定高度**：
              // 作者缺失时行高会塌成 0，评分行就会比其他卡片高一截。
              SizedBox(
                height: dense ? 16 : 18,
                child: Row(
                  children: [
                    Expanded(
                      child: video.artist == null || video.artist!.isEmpty
                          ? const SizedBox.shrink()
                          : _artistLink(context, theme, video.artist!, metaInk),
                    ),
                    if (video.uploadTime != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          video.uploadTime!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: dense ? 10 : null,
                            color: metaInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: dense ? 14 : 16,
                child: video.rating == null
                    ? const SizedBox.shrink()
                    : Row(
                        children: [
                          Icon(
                            Symbols.thumb_up_rounded,
                            size: dense ? 11 : 14,
                            color: metaInk,
                          ),
                          SizedBox(width: dense ? 3 : 4),
                          Flexible(
                            child: Text(
                              video.rating!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: dense ? 10 : null,
                                color: metaInk,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
            ],
          );
        },
      ),
    );
  }
}

class VideoCardGrid extends ConsumerWidget {
  const VideoCardGrid({
    super.key,
    required this.videos,
    this.itemBuilder,
    this.cardsPerRow,
    this.rowsPerScreen,
    this.horizontal,
    this.controller,
    this.coverAspectRatio,
    this.bottomPadding = 24,
  });

  final List<VideoCard> videos;
  final Widget Function(
    BuildContext context,
    int index,
    VideoCard video,
    bool horizontal,
  )?
  itemBuilder;

  /// 指定每行几个（为空时用设置里的值，宽屏会自动加宽）。
  final int? cardsPerRow;

  /// 指定一屏显示几行（固定高度网格，卡片高度按可用高度反推）。
  final int? rowsPerScreen;

  /// 指定卡片方向（为空时用设置里的值）。
  final bool? horizontal;

  /// 外部控制器（用于「回到顶部」这类滚动控制）。
  final ScrollController? controller;

  /// 封面比例（宽 / 高），给竖版海报结果用（见 [VideoCardTile.coverAspectRatio]）。
  /// 传了之后卡片高度按海报比例算，而不是按 16:9。
  final double? coverAspectRatio;

  /// 网格底部内边距（不含系统安全区）。
  ///
  /// 页面上浮着右下角操作（刷新 / 回到顶部）时要传 `floatingActionsClearance`，
  /// 否则滚到底时最后一行右侧那张卡会被那两个按钮压住、点不到。
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final horizontal =
        this.horizontal ?? settings?.useHorizontalSearchCards ?? true;
    final cardsPerRow = this.cardsPerRow ?? settings?.searchCardsPerRow ?? 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 24.0;
        const crossAxisSpacing = 10.0;
        const mainAxisSpacing = 12.0;
        final autoWiden =
            this.cardsPerRow == null && constraints.maxWidth >= 1200;
        final effectiveCardsPerRow = autoWiden
            ? (constraints.maxWidth / 300).floor().clamp(cardsPerRow, 6).toInt()
            : cardsPerRow;
        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding -
                crossAxisSpacing * (effectiveCardsPerRow - 1)) /
            effectiveCardsPerRow;
        final rows = rowsPerScreen;
        final double cardHeight;
        if (rows != null && constraints.hasBoundedHeight) {
          cardHeight =
              ((constraints.maxHeight -
                          36 -
                          MediaQuery.paddingOf(context).bottom -
                          mainAxisSpacing * (rows - 1)) /
                      rows)
                  .clamp(96.0, 420.0);
        } else if (coverAspectRatio != null) {
          // 竖版海报：封面按传入比例留高；没有作者/评分时详细区只剩标题（40 高 + 8 间距）。
          cardHeight =
              cardWidth / coverAspectRatio! +
              (videos.any(hasVideoCardMeta) ? _horizontalCardMetaHeight : 48);
        } else {
          cardHeight = horizontal
              ? cardWidth * 9 / 16 + videoCardMetaHeight(videos)
              : cardWidth / .58;
        }
        return GridView.builder(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            bottomPadding + MediaQuery.paddingOf(context).bottom,
          ),
          scrollCacheExtent: const ScrollCacheExtent.pixels(1400),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveCardsPerRow,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) =>
              itemBuilder?.call(context, index, videos[index], horizontal) ??
              VideoCardTile(
                video: videos[index],
                horizontal: horizontal,
                coverAspectRatio: coverAspectRatio,
              ),
        );
      },
    );
  }
}

class _OverlayText extends StatelessWidget {
  const _OverlayText({this.icon, required this.text, this.dense = false});
  final IconData? icon;
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: dense ? 10 : 12, color: Colors.white),
        SizedBox(width: dense ? 2 : 3),
      ],
      Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: dense ? 9 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
