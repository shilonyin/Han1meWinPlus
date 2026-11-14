import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_responsive.dart';
import '../../core/app_radius.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import 'video_actions.dart';
import 'video_comments.dart';
import 'play_window.dart';
import 'video_player_panel.dart';

/// 沉浸式视频详情页：上半部是铺满的 Hero（模糊背景 + 竖版海报 + 标签 + 主操作），
/// 下半部是一块白色圆角面板，用 Tab 在「概览 / 评论 / 信息 / 相关」之间切换。
///
/// 版式参照 FigCraft 的 `page/videoDetail-redesign`（Baka 番剧详情页风格）：
/// 不把评论区直接摊在页面上，信息都收进 Tab 里。
/// 旧的 [VideoDetailSplitView] 仍保留在 video_detail_content.dart，需要时可以一行切回去。
class VideoDetailImmersiveView extends ConsumerStatefulWidget {
  const VideoDetailImmersiveView({
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
  ConsumerState<VideoDetailImmersiveView> createState() =>
      _VideoDetailImmersiveViewState();
}

class _VideoDetailImmersiveViewState
    extends ConsumerState<VideoDetailImmersiveView> {
  /// 是否已经点过「开始观看」。进详情页先看 Hero，点了才创建播放器。
  bool _playing = false;
  int _tab = 0;

  static const _tabs = ['概览', '评论', '信息', '相关'];

  /// 「立即播放 / 开始观看」：默认弹独立播放窗口（多窗口方案），
  /// 拉不起来（窗口 exe 缺失、非 Windows 等）才回退到本页内嵌播放器。
  /// 之前这里直接 setState 内嵌，独立播放窗口就再也没出现过。
  Future<void> _play(BuildContext context, VideoDetail video) async {
    final opened =
        await openVideoInPlayWindow(context, ref, video.id);
    if (opened) return;
    if (!mounted) return;
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    if (_playing) {
      return ColoredBox(
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
      );
    }
    return LayoutBuilder(
      builder: (context, viewport) {
        // 内容面板至少铺满 Hero 以下的视口高度，跟 Getchu 新番详情页一样
        // 一直延伸到底，不在下方露出一大片页面底色。
        final minPanelHeight =
            (viewport.maxHeight -
                    AppResponsive.scaled(
                      context,
                      AppResponsive.isCompact(viewport.maxWidth) ? 360 : 430,
                    ))
                .clamp(0.0, double.infinity);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(
                video: video,
                onBack: widget.onBack,
                onPlay: () => _play(context, video),
              ),
              // 与首页一致：纯 #0A0A0D 深底、全宽，不再用浮起的圆角 surface 面板。
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minPanelHeight),
                child: ColoredBox(
                  color: const Color(0xFF0A0A0D),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OverviewTab(video: video),
                      if (video.playlist.isNotEmpty) ...[
                        Divider(height: 1, thickness: 1, color: AppDesignTokens.dividerOf(context)),
                        _EpisodeSection(video: video),
                      ],
                      Divider(height: 1, thickness: 1, color: AppDesignTokens.dividerOf(context)),
                      _RelatedTab(video: video),
                      Divider(height: 1, thickness: 1, color: AppDesignTokens.dividerOf(context)),
                      _CommentsSection(video: video),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _tabBar() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
    child: Row(
      children: [
        for (var i = 0; i < _tabs.length; i++) ...[
          PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => setState(() => _tab = i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tabs[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _tab == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: _tab == i
                            ? AppDesignTokens.inkOf(context)
                            : AppDesignTokens.inkMutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _tab == i
                            ? AppDesignTokens.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (i < _tabs.length - 1) const SizedBox(width: 12),
        ],
      ],
    ),
  );

  // ignore: unused_element
  Widget _buildTab(BuildContext context, VideoDetail video) {
    switch (_tab) {
      case 1:
        // 评论容器高度跟随文字缩放，并以视口高为上限，避免放大后列表被裁断。
        return SizedBox(
          height: AppResponsive.scaled(context, 900).clamp(
            0.0,
            MediaQuery.sizeOf(context).height,
          ),
          child: VideoCommentsView(video: video),
        );
      case 2:
        return _InfoTab(video: video);
      case 3:
        return Padding(
          padding: EdgeInsets.fromLTRB(
  28,
  AppResponsive.scaled(context, 56),
  28,
  AppResponsive.scaled(context, 32),
),
          child: _RelatedTab(video: video),
        );
      default:
        return _OverviewTab(video: video);
    }
  }
}


/// 剧集横向 rail：一排可横向滚动的集数按钮（取代原来塞在 Tab 里的 Wrap 网格）。
class _EpisodeSection extends StatefulWidget {
  const _EpisodeSection({required this.video});
  final VideoDetail video;

  @override
  State<_EpisodeSection> createState() => _EpisodeSectionState();
}

class _EpisodeSectionState extends State<_EpisodeSection> {
  final TextEditingController _searchCtl = TextEditingController();
  bool _grid = true;
  String _q = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final items = video.playlist.where((e) {
      if (_q.isEmpty) return true;
      final k = _q.toLowerCase();
      return e.title.toLowerCase().contains(k) || e.id.contains(k);
    }).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
          AppResponsive.scaled(context, 24),
          AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
          AppResponsive.scaled(context, 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('剧集',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.inkOf(context))),
              const SizedBox(width: 8),
              Text('共 ${video.playlist.length} 集',
                  style: TextStyle(
                      fontSize: 12, color: AppDesignTokens.inkMutedOf(context))),
              const Spacer(),
              SizedBox(
                width: 220,
                height: 38,
                child: TextField(
                  controller: _searchCtl,
                  onChanged: (v) => setState(() => _q = v.trim()),
                  style: TextStyle(fontSize: 13, color: AppDesignTokens.inkOf(context)),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppDesignTokens.fieldFillOf(context),
                    hintText: '搜索剧集',
                    hintStyle: TextStyle(fontSize: 13, color: AppDesignTokens.inkMutedOf(context)),
                    prefixIcon: Icon(Symbols.search_rounded,
                        size: 16, color: AppDesignTokens.inkSubtleOf(context)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide:
                            BorderSide(color: AppDesignTokens.dividerOf(context))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide:
                            BorderSide(color: AppDesignTokens.dividerOf(context))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ViewToggle(
                grid: _grid,
                onGrid: () => setState(() => _grid = true),
                onList: () => setState(() => _grid = false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('没有匹配的剧集',
                  style: TextStyle(fontSize: 13, color: AppDesignTokens.inkMutedOf(context))),
            )
          else if (_grid)
            _buildGrid(context, items, video)
          else
            _buildList(context, items, video),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<VideoCard> items, VideoDetail video) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cols = w >= 1000 ? 5 : (w >= 760 ? 4 : 3);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 1.45,
        ),
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = item.id == video.id;
          final img = item.coverUrl.isNotEmpty ? item.coverUrl : (video.coverUrl ?? '');
          return PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => context.push('/video/${item.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AppCachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                ColoredBox(color: AppDesignTokens.fieldFillOf(context)),
                          ),
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .55),
                                  borderRadius: BorderRadius.circular(4)),
                              child: Text('${i + 1}'.padLeft(2, '0'),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ),
                          ),
                          if (selected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(
                                        color: AppDesignTokens.accentDeep, width: 2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: selected
                              ? AppDesignTokens.accentDeep
                              : AppDesignTokens.inkOf(context))),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildList(BuildContext context, List<VideoCard> items, VideoDetail video) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Builder(builder: (context) {
            final item = items[i];
            final selected = item.id == video.id;
            final img = item.coverUrl.isNotEmpty ? item.coverUrl : (video.coverUrl ?? '');
            return PressScale(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => context.push('/video/${item.id}'),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppDesignTokens.accentDeep.withValues(alpha: .16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: SizedBox(
                          width: 96,
                          height: 54,
                          child: AppCachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                ColoredBox(color: AppDesignTokens.fieldFillOf(context)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${i + 1}'.padLeft(2, '0'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? AppDesignTokens.accentDeep
                                  : AppDesignTokens.inkSubtleOf(context))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: AppDesignTokens.inkOf(context))),
                      ),
                      if (selected)
                        Icon(Symbols.play_arrow_rounded,
                            size: 18, color: AppDesignTokens.accentDeep),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.grid, required this.onGrid, required this.onList});
  final bool grid;
  final VoidCallback onGrid;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) => Row(children: [
        _seg(context, Symbols.grid_view_rounded, grid, onGrid),
        const SizedBox(width: 6),
        _seg(context, Symbols.view_list_rounded, !grid, onList),
      ]);

  Widget _seg(BuildContext context, IconData icon, bool active, VoidCallback tap) =>
      PressScale(
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active ? AppDesignTokens.accentDeep : AppDesignTokens.fieldFillOf(context),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Icon(icon,
                size: 18,
                color: active ? Colors.white : AppDesignTokens.inkSubtleOf(context)),
          ),
        ),
      );
}

// ignore: unused_element
class _EpisodeRail extends StatelessWidget {
  const _EpisodeRail({required this.video});
  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            28, AppResponsive.scaled(context, 22), 0, AppResponsive.scaled(context, 22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Row(children: [
                Text('选集',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.inkOf(context))),
                const SizedBox(width: 8),
                Text('共 ${video.playlist.length} 集',
                    style: TextStyle(
                        fontSize: 12, color: AppDesignTokens.inkMutedOf(context))),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 28),
                itemCount: video.playlist.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final item = video.playlist[i];
                  final selected = item.id == video.id;
                  return PressScale(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => context.push('/video/${item.id}'),
                      child: Container(
                        width: 96,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppDesignTokens.accentDeep
                              : AppDesignTokens.fieldFillOf(context),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '${i + 1}'.padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
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
            ),
          ],
        ),
      );
}

/// 评论：平铺在详情页最下方的一块。
class _CommentsSection extends StatelessWidget {
  const _CommentsSection({required this.video});
  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
            24,
            AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
            32),
        child: SizedBox(
          height: AppResponsive.scaled(context, 640)
              .clamp(0.0, MediaQuery.sizeOf(context).height),
          child: VideoCommentsView(video: video),
        ),
      );
}


/// 去掉简介里混进来的「署名/元数据」行（Title/Brand/Release/File size/链接等），
/// 只保留剧情文字，避免 hero 简介显示成站点署名信息。
String _plainDescription(String raw) {
  final keep = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final l = t.toLowerCase();
    var isMeta = false;
    for (final k in const [
      'title', 'タイトル', 'brand', 'ブランド', 'release', '販売日', 'file size',
      'ファイル容量', 'http', 'support the author', 'circle', 'サークル', 'ジャンル',
    ]) {
      if (l.startsWith(k) || l.contains('$k /') || l.contains('$k:') || l.contains('$k：')) {
        isMeta = true;
        break;
      }
    }
    if (isMeta) continue;
    keep.add(t);
  }
  return keep.join('\n');
}

/// 封面主色缓存：同一张封面只采样一次。
final Map<String, Color?> _coverColorCache = {};

Future<Color?> _coverDominantColor(String url) {
  if (url.isEmpty) return Future<Color?>.value(null);
  if (_coverColorCache.containsKey(url)) {
    return Future<Color?>.value(_coverColorCache[url]);
  }
  return _computeCoverColor(url).then((c) {
    _coverColorCache[url] = c;
    return c;
  });
}

/// 采样封面缩略图的平均色（跳过过黑/过白像素），用作 hero 氛围主色。
Future<Color?> _computeCoverColor(String url) async {
  try {
    final stream = appNetworkImage(url).resolve(const ImageConfiguration());
    final completer = Completer<ui.Image>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (e, st) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    stream.addListener(listener);
    final img = await completer.future.timeout(const Duration(seconds: 8));
    const dim = 12;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, dim.toDouble(), dim.toDouble()),
      Paint()..filterQuality = FilterQuality.low,
    );
    final small = await recorder.endRecording().toImage(dim, dim);
    final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i + 3] < 32) continue;
      final pr = bytes[i], pg = bytes[i + 1], pb = bytes[i + 2];
      final lum = (pr * 30 + pg * 59 + pb * 11) ~/ 100;
      if (lum < 20 || lum > 235) continue;
      r += pr;
      g += pg;
      b += pb;
      n++;
    }
    if (n == 0) return null;
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  } catch (_) {
    return null;
  }
}

/// 封面主色氛围光：拿封面真实主色做径向柔光（取不到时回退主题强调色）。
class _CoverGlow extends StatelessWidget {
  const _CoverGlow({required this.coverUrl});
  final String coverUrl;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: FutureBuilder<Color?>(
          future: _coverDominantColor(coverUrl),
          builder: (context, snap) {
            // 取到封面色时更饱和；取不到（封面没加载）时用更强的主题色光，
            // 避免 hero 背景变成一块没有氛围的灰。
            final hasCoverColor = snap.data != null;
            final color = snap.data ?? AppDesignTokens.accentOf(context);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.25),
                  radius: 1.5,
                  colors: [
                    color.withValues(alpha: hasCoverColor ? .5 : .62),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

/// 沉浸式 Hero：模糊放大的封面作背景，竖版海报压在左侧，右侧是标题/标签/操作。
class _Hero extends ConsumerWidget {
  const _Hero({
    required this.video,
    required this.onBack,
    required this.onPlay,
  });

  final VideoDetail video;
  final VoidCallback onBack;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = video.coverUrl;
    final descPlain = _plainDescription(video.description ?? '');
    final actions = videoActionsFor(context, ref, video);
    final primary = actions.isNotEmpty ? actions.first : null;
    VideoAction? findAction(List<String> keys) {
      for (final a in actions) {
        for (final k in keys) {
          if (a.label.contains(k)) return a;
        }
      }
      return null;
    }
    return LayoutBuilder(
      builder: (context, viewport) {
        final wide = !AppResponsive.isCompact(viewport.maxWidth);
        final heroHeight = AppResponsive.scaled(context, wide ? 520 : 400);
        // 顶部导航半透明浮在 hero 上，hero 内容（返回/标题）要下移让位。
        final topPad = AppResponsive.scaled(context, 20) + 64;
        final bottomPad = AppResponsive.scaled(context, 28);
        final titleHeight = AppResponsive.scaled(context, 32);
        final titleGap = AppResponsive.scaled(context, 20);
        final gutter = AppResponsive.gutterFor(viewport.maxWidth);
        // 海报与右侧按钮共用同一段行高，底边才永远齐平；宽度按设计稿比例反推。
        final rowHeight = (heroHeight -
                topPad -
                bottomPad -
                titleHeight -
                titleGap)
            .clamp(120.0, double.infinity);
        final posterHeight = rowHeight;
        // Weebox 式：hero 不要独立海报卡，信息直接叠在全宽背景图上。
        final posterWidth = 0.0;
        return SizedBox(
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景与 GetchuBackdrop 完全一致：封面原图不模糊，只叠**单层**
              // 由 55% → 88% → 100% 页底白的渐变遮罩，图就这样平滑收进面板。
              // 之前额外叠的顶部压暗层会在两层交界处压出一条硬边，已去掉。
              if (cover != null && cover.isNotEmpty)
                AppCachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  width: viewport.maxWidth,
                  height: heroHeight,
                  fadeInDuration: Duration.zero,
                  errorWidget: (context, url, error) => const _HeroFallback(),
                )
              else
                const _HeroFallback(),
              // 封面主色氛围光：数据里没有单独的封面主色字段，用主题强调色近似，
              // 只做一次静态径向渐变，不逐帧重绘（性能友好）。
              Positioned.fill(
                child: _CoverGlow(coverUrl: cover ?? ''),
              ),
              // Weebox 式：从左到右的压暗渐变 —— 左侧标题/信息压在图上清晰可读，
              // 右侧保留画面透出，避免文字和清晰背景叠在一起显得杂乱。
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xB30A0A0D),
                        Color(0x330A0A0D),
                        Color(0x000A0A0D),
                      ],
                      stops: [0.0, 0.32, 0.60],
                    ),
                  ),
                ),
              ),
              // 渐隐遮罩改用面板底色 surfaceOf 而不是写死白：浅色下等于原来的白，
              // 深色下自动收进 #1C1C21，封面才不会在深色主题里渐隐成一片白。
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x8C0A0A0D),
                      Color(0xE00A0A0D),
                      Color(0xFF0A0A0D),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  topPad,
                  gutter,
                  bottomPad,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PressScale(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            onTap: onBack,
                            child: SizedBox(
                              width: titleHeight,
                              height: titleHeight,
                              child: Icon(
                                Symbols.arrow_back_rounded,
                                size: 22,
                                color: AppDesignTokens.inkOf(context),
                              ),
                            ),
                          ),
                        ),

                      ],
                    ),
                    SizedBox(height: titleGap),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 竖版海报
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: SizedBox(
                              width: posterWidth,
                              height: posterHeight,
                              child: cover != null && cover.isNotEmpty
                                  ? AppCachedNetworkImage(
                                      imageUrl: cover,
                                      fit: BoxFit.cover,
                                      faceFocus: true,
                                      errorWidget: (context, url, error) =>
                                          const ColoredBox(
                                        color: Color(0xFF2B2B31),
                                      ),
                                    )
                                  : const ColoredBox(
                                      color: Color(0xFF2B2B31),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Spacer(),
                                if ((video.genre ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      video.genre!,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                        color: Color(0xFFFF3B47),
                                      ),
                                    ),
                                  ),
                                Text(
                                  video.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: wide ? 34 : 26,
                                    height: 1.12,
                                    fontWeight: FontWeight.w900,
                                    color: AppDesignTokens.inkOf(context),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if ((video.rating ?? '').isNotEmpty)
                                      '评分 ${video.rating}',
                                    if (video.uploadDate != null) video.uploadDate!,
                                    if (video.artist != null) video.artist!,
                                    if (video.playlist.isNotEmpty)
                                      '${video.playlist.length} 集',
                                    if (video.duration != null) video.duration!,
                                  ].join('   ·   '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppDesignTokens.inkSubtleOf(context),
                                  ),
                                ),
                                if (video.tags.isNotEmpty)
                                  _HeroTags(tags: video.tags),
                                if (descPlain.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    descPlain,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                      color: AppDesignTokens.inkSubtleOf(context),
                                    ),
                                  ),
                                ],
                                SizedBox(height: AppResponsive.scaled(context, 16)),
                                Row(
                                  children: [
                                    if (primary != null)
                                      _HeroButton(
                                        label: primary.label,
                                        dark: true,
                                        icon: Symbols.add_rounded,
                                        onTap: primary.onPressed,
                                      ),
                                    const SizedBox(width: 12),
                                    _HeroButton(
                                      label: '开始观看',
                                      dark: false,
                                      icon: Symbols.play_arrow_rounded,
                                      onTap: onPlay,
                                    ),
                                    const SizedBox(width: 16),
                                    _HeroIconButton(
                                      icon: Symbols.favorite_border_rounded,
                                      tooltip: '收藏',
                                      onTap: findAction(['收藏', '订阅'])?.onPressed,
                                    ),
                                    const SizedBox(width: 10),
                                    _HeroIconButton(
                                      icon: Symbols.download_rounded,
                                      tooltip: '下载',
                                      onTap: findAction(['下载'])?.onPressed,
                                    ),
                                    const SizedBox(width: 10),
                                    _HeroIconButton(
                                      icon: Symbols.image_rounded,
                                      tooltip: '图片',
                                      onTap: null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // 无封面时的占位渐变：浅色沿用原来的浅灰→白；深色换成两档冷灰，
          // 否则深色主题里 Hero 位置会露出一块发白的底，和遮罩对不上。
          colors: dark
              ? [
                  AppDesignTokens.surfaceRaisedOf(context),
                  AppDesignTokens.surfaceOf(context),
                  AppDesignTokens.pageBackgroundOf(context),
                ]
              : const [
                  Color(0xFFD8D9E4),
                  Color(0xFFECECF3),
                  Color(0xFFFFFFFF),
                ],
        ),
      ),
    );
  }
}

class _HeroTags extends StatelessWidget {
  const _HeroTags({required this.tags});

  final List<VideoTag> tags;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      // IntrinsicWidth：Wrap 给子项的是无界宽度，不约束就会把每颗标签撑满整行
      // （宽窗口下见过一次），按钮和评分会被挤出 Hero。
      for (final tag in tags.take(6))
        IntrinsicWidth(
          child: PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                final url = Uri(
                  path: '/search',
                  queryParameters: {'tags[]': tag.name},
                ).toString();
                context.push(url, extra: SearchRouteRequest(initialUrl: url));
              },
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppDesignTokens.surfaceOf(context).withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkOf(context),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Hero 按钮行右侧的圆形图标按钮（下载 / 收藏 / 分享等）。
class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: PressScale(
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
          ),
        ),
      );
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.dark,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool dark;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B1B1F) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: dark ? Colors.white : AppDesignTokens.ink,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : AppDesignTokens.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ignore: unused_element
class _HeroRating extends StatelessWidget {
  const _HeroRating({required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        rating,
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: AppDesignTokens.inkOf(context),
        ),
      ),
      const SizedBox(width: 6),
      const Icon(Symbols.star_rounded, size: 22, color: Color(0xFFF5A623), fill: 1),
    ],
  );
}

/// 概览 Tab：左剧情简介、右基本信息，下面接选集与相关推荐。
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Padding(
    // 概览只放「剧情简介 + 基本信息」两栏，跟 Baka 的概览页一致；
    // 选集归到「信息」Tab、相关推荐归到「相关」Tab，不在概览下面堆长内容。
    padding: EdgeInsets.fromLTRB(
  AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
  AppResponsive.scaled(context, 24),
  AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
  AppResponsive.scaled(context, 24),
),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.description,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                video.description ?? '',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppDesignTokens.inkSubtleOf(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '基本信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
              const SizedBox(height: 12),
              _InfoTab(video: video, compact: true),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 信息 Tab：键值列表。紧凑模式下用在概览右侧，不重复画标题。
class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.video, this.compact = false});

  final VideoDetail video;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (video.views != null) ('播放量', video.views!),
      if (video.rating != null) ('评分', video.rating!),
      if (video.commentCount != null) ('评论数', '${video.commentCount}'),
      if (video.duration != null) ('时长', video.duration!),
      if (video.uploadDate != null) ('发布日期', video.uploadDate!),
      if (video.artist != null) ('作者', video.artist!),
      if (video.genre != null) ('分类', video.genre!),
    ];
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
          Text(
            '基本信息',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.inkOf(context),
            ),
          ),
        if (!compact) const SizedBox(height: 16),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.inkMutedOf(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.inkOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (rows.isEmpty)
          Text(
            '暂无信息',
            style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMutedOf(context)),
          ),
      ],
    );
    if (compact) return list;
    // 独立的「信息」Tab：基本信息 + 选集（选集不再堆在概览底部）。
    return Padding(
      padding: EdgeInsets.fromLTRB(
  28,
  AppResponsive.scaled(context, 56),
  28,
  AppResponsive.scaled(context, 32),
),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          list,
          if (video.playlist.isNotEmpty) ...[
            const SizedBox(height: 24),
            Divider(
              height: 1,
              thickness: 1,
              color: AppDesignTokens.dividerOf(context),
            ),
            const SizedBox(height: 24),
            _EpisodeGrid(video: video),
          ],
        ],
      ),
    );
  }
}

/// 选集网格：4 列编号按钮，当前集用主色。
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            '选集',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.inkOf(context),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '共 ${video.playlist.length} 集',
            style: TextStyle(
              fontSize: 12,
              color: AppDesignTokens.inkMutedOf(context),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      // 固定格宽、由 Wrap 自动换行：不按窗口宽度均分，否则超宽窗口下每格会被拉成横条。
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < video.playlist.length; i++)
            Builder(
              builder: (context) {
                final item = video.playlist[i];
                final selected = item.id == video.id;
                return PressScale(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => context.push('/video/${item.id}'),
                    child: Container(
                      width: AppResponsive.scaled(context, 100),
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppDesignTokens.accentDeep
                            : AppDesignTokens.fieldFillOf(context),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: TextStyle(
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
      ),
    ],
  );
}

/// 相关作品：网格卡片，最多两排；每排张数按宽度算，超出分页（左右箭头翻页）。
class _RelatedTab extends StatefulWidget {
  const _RelatedTab({required this.video});
  final VideoDetail video;

  @override
  State<_RelatedTab> createState() => _RelatedTabState();
}

class _RelatedTabState extends State<_RelatedTab> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: AppResponsive.gutterFor(MediaQuery.sizeOf(context).width)),
      child: LayoutBuilder(builder: (context, constraints) {
        const gap = 16.0;
        final minCardWidth = AppResponsive.scaled(context, 220);
        final cardWidth = AppResponsive.cardWidthFor(
          availableWidth: constraints.maxWidth,
          minCardWidth: minCardWidth,
          gap: gap,
        );
        final cols = ((constraints.maxWidth + gap) / (cardWidth + gap)).floor();
        final perPage = cols < 1 ? 1 : cols * 2;
        final pageCountRaw = (video.related.length + perPage - 1) ~/ perPage;
        final pageCount = pageCountRaw < 1 ? 1 : pageCountRaw;
        final p = _page < 0 ? 0 : (_page > pageCount - 1 ? pageCount - 1 : _page);
        final shown = video.related.skip(p * perPage).take(perPage).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('相关作品',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.inkOf(context))),
                const Spacer(),
                _RailArrow(
                  icon: Symbols.chevron_left_rounded,
                  onTap: p > 0 ? () => setState(() => _page = p - 1) : null,
                ),
                const SizedBox(width: 8),
                _RailArrow(
                  icon: Symbols.chevron_right_rounded,
                  onTap: p < pageCount - 1 ? () => setState(() => _page = p + 1) : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: gap,
              runSpacing: 20,
              children: [
                for (final item in shown)
                  SizedBox(width: cardWidth, child: _RelatedCard(item: item)),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _RailArrow extends StatelessWidget {
  const _RailArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppDesignTokens.fieldFillOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 20,
                color: onTap == null
                    ? AppDesignTokens.inkSubtleOf(context).withValues(alpha: .4)
                    : AppDesignTokens.inkOf(context)),
          ),
        ),
      );
}

/// 封面真实宽高比缓存：同一张图只解析一次，滚动时不再反复解码。
final Map<String, double> _coverAspectCache = <String, double>{};

/// 读取封面实际尺寸并返回宽高比，取不到时退回 16:9。
Future<double> _coverAspect(String url) async {
  final cached = _coverAspectCache[url];
  if (cached != null) return cached;
  if (url.isEmpty) return 16 / 9;
  try {
    final stream = appNetworkImage(url).resolve(const ImageConfiguration());
    final completer = Completer<ui.Image>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stack) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    final image = await completer.future.timeout(const Duration(seconds: 8));
    final ratio = image.width / image.height;
    _coverAspectCache[url] = ratio;
    return ratio;
  } catch (_) {
    return 16 / 9;
  }
}

/// 单张相关视频卡：封面按自身真实比例显示，标题与作者/播放量在下。
class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.item});

  final VideoCard item;

  @override
  Widget build(BuildContext context) => FutureBuilder<double>(
    future: _coverAspect(item.coverUrl),
    builder: (context, snapshot) {
      // 极端长条会撑坏网格，收敛到 0.56~1.9，仍保留竖版与横版的区别。
      final ratio = (snapshot.data ?? 16 / 9).clamp(0.56, 1.9);
      return PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: item.id.isEmpty
              ? null
              : () => context.push('/video/${item.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: AppCachedNetworkImage(
                    imageUrl: item.coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        const ColoredBox(color: Color(0xFF3D3540)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (item.tags.isNotEmpty) item.tags.take(2).join(' · '),
                  if (item.rating != null)
                    item.tags.isEmpty ? '评分 ${item.rating}%' : '${item.rating}%',
                  if (item.tags.isEmpty && item.rating == null && item.artist != null)
                    item.artist!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppDesignTokens.inkMutedOf(context),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
