import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;

import '../../core/face/face_crop.dart';
import '../../core/face/face_focus_service.dart';

/// 图片缓存索引文件的路径（`<应用数据目录>/han1me_images.json`）。
///
/// 必须显式给：`flutter_cache_manager` 内部用 `getApplicationSupportDirectory()` 决定
/// 索引位置，而那条路径在 Windows 上由 exe 的 VERSIONINFO（`CompanyName\ProductName`）
/// 拼出来，指向 `%APPDATA%\Han1meWinPlus\Han1meWinPlus\` —— 与应用真正在用的
/// `%APPDATA%\han1me_win_plus\` 是两个目录。后果实测过：索引写进了那个历史目录，
/// 而图片本体在 `%TEMP%`，两边对不上账，清缓存清不干净、索引还时不时写失败
/// （`PathAccessException: 拒绝访问`）。详见 platform_paths.dart 的说明。
///
/// 惰性求值：`APPDATA` 要等进程起来才读得到，所以先给个 null，首次用到时再算。
String? _imageCacheIndexPath;

/// 封面图的磁盘缓存。
///
/// 图片站点（CDN77）的单张响应实测在 0.3–5s 之间抖（服务端回源慢），偶尔还会握手失败，
/// 客户端能做的就是别重复下载：`CacheManager` 默认只留 200 个对象，首页翻两屏就被挤掉。
/// 这里放宽到 2000 个（单张缩略图只有 20–50KB）、保留 30 天。
final appImageCacheManager = CacheManager(
  Config(
    'han1me_images',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 2000,
    // 索引落到应用自己的数据目录，别让它跟着 VERSIONINFO 跑。
    repo: JsonCacheInfoRepository(
      path: _imageCacheIndexPath ??= _resolveImageCacheIndexPath(),
    ),
  ),
);

String _resolveImageCacheIndexPath() {
  final appData = Platform.environment['APPDATA'];
  final base = (appData != null && appData.isNotEmpty)
      ? Directory(path.join(appData, 'han1me_win_plus'))
      : Directory.systemTemp;
  return path.join(base.path, 'han1me_images.json');
}

/// 易变参数：这些值由服务端按请求现算，不能进缓存 key。
///
/// `secure` 的形态是 `<签名>,<过期时间戳>`，后半段是**服务器处理该请求时**生成的
/// （实测三条记录的过期时间戳彼此只差几秒，而它们的抓取时间差了几百秒）。所以同一个
/// 视频每次抓页面拿到的封面 URL 都不同。
///
/// 后果实测过：缓存目录里 167 个文件只有 113 份唯一内容，**54 组是同一张图存了两份**，
/// 两组之间相隔约 23 分钟（两次启动各下载了一遍）。也就是说每次打开应用都要把首屏
/// 封面重新下一遍 —— 这正是「图片加载慢」里客户端能修的那部分。
///
/// 路径部分（如 `/image/thumbnail/406505h.jpg`）已经唯一标识了图片内容，用它做 key
/// 就够了；请求时仍然带上完整 URL（含签名），否则服务端会 403。
///
/// 名单刻意收窄：只列语义明确的签名参数，不用 `st`/`e`/`exp` 这类短名 —— 它们也可能
/// 是尺寸或画质参数，误去掉会让不同的图共用一个 key。目前数据里出现的只有 `secure`
/// （56/56 个 URL），其余是为将来接入其它源预留的。
const _volatileQueryParameters = {
  'secure',
  'token',
  'sign',
  'signature',
  'expires',
  'authkey',
};

/// 去掉易变参数后的 URL，用作缓存 key。
///
/// 解析失败时原样返回：宁可退化成「按完整 URL 缓存」，也不要用一个错误的 key
/// 让不同的图互相覆盖。
String imageCacheKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.queryParameters.isEmpty) return url;
  final kept = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    if (!_volatileQueryParameters.contains(key.toLowerCase())) kept[key] = value;
  });
  // 按字符串切出「不含查询串」的基址，而不是走 Uri.replace —— 后者几次三番
  // 留下孤立的 `?` 或 `#`（replace 把 null 当「不变」，传空串又会留下分隔符）。
  final withoutQuery = url.split('?').first.split('#').first;
  if (kept.isEmpty) return withoutQuery;
  // 保留的参数用 Uri 编码回查询串，保证与请求时一致。
  final query = Uri(queryParameters: kept).query;
  return '$withoutQuery?$query';
}

/// 头像这类网络图片也走同一个缓存，避免每次启动都重新下载一遍。
///
/// [cacheKey] 显式指定，不走默认的「整个 URL」：见 [imageCacheKey] 的说明。
///
/// [httpHeaders] 对需要防盗链的站点是**必需**的（Getchu 的图不带 Referer 直接
/// 403），传了才拿得到图。
ImageProvider appNetworkImage(
  String url, {
  Map<String, String>? httpHeaders,
}) =>
    CachedNetworkImageProvider(
      url,
      cacheKey: imageCacheKey(url),
      headers: httpHeaders,
      cacheManager: appImageCacheManager,
    );

/// 需要额外参数（解码尺寸等）时用这个，别直接 `new CachedNetworkImageProvider`。
///
/// 直接构造会退回默认的「按完整 URL 缓存」，于是带 `secure` 的封面每次都会重新下载 ——
/// 这正是 [imageCacheKey] 要解决的问题。所有加载网络图的地方都该走这里或
/// [appNetworkImage]，两个入口共享同一个 [appImageCacheManager]。
/// [cacheKeySuffix] 会给磁盘缓存键加后缀，**人脸检测那条路径必须用它**。
///
/// 检测和显示如果共用同一个 cacheKey，会撞进 flutter_cache_manager 的一个
/// 竞态：它的 `WebHelper._memCache` 按 key 去重，同一个 key 的**第二个**请求
/// 会被 push 进下载队列，等前一个完成后从队列里取出来执行时
/// `_memCache[key]!` 已经是 null（前一个在 `finally` 里把它删了），于是
/// 抛 Null check operator，那个 Future 没有人接 —— 订阅者既拿不到图也拿不到
/// 错误，界面就永远停在占位态。Getchu 页上「卡片只剩一块白板、连标题都不显示」
/// 就是这个：检测先拿同一 key 发了一次不带 Referer 的请求，403 收场后把
/// subject 删掉，随后显示层的排队请求正好撞上。
///
/// 加了后缀之后两边各走各的缓存条目，互不影响。
ImageProvider appCachedImage(
  String url, {
  int? maxWidth,
  int? maxHeight,
  Map<String, String>? httpHeaders,
  String? cacheKeySuffix,
}) {
  final baseKey = imageCacheKey(url);
  return CachedNetworkImageProvider(
    url,
    cacheKey: cacheKeySuffix == null ? baseKey : '$baseKey$cacheKeySuffix',
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    headers: httpHeaders,
    cacheManager: appImageCacheManager,
  );
}

/// [CachedNetworkImage] 的替代品：自动带上稳定的 [cacheKey]。
///
/// 各处加载封面都该用它，别直接 `CachedNetworkImage(...)` —— 后者默认按完整 URL
/// 缓存，带 `secure` 的封面于是每次启动都重新下载一遍（见 [imageCacheKey]）。
/// 这里把 [cacheManager] 也固定住，少一处可以写错的地方。
class AppCachedNetworkImage extends StatelessWidget {
  const AppCachedNetworkImage({
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.memCacheWidth,
    this.alignment = Alignment.center,
    this.faceFocus = false,
    this.faceCropMethod = CropMethod.mostFaces,
    this.httpHeaders,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.faceImageBuilder,
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
    super.key,
  });

  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final Alignment alignment;

  /// 是否按检出的人脸决定 [alignment]。
  ///
  /// 打开后：检测到脸 → 把脸圈进裁切窗口；没检到 → 顶部居中兜底
  /// （海报主体绝大多数压在上半张，居中裁常把脑袋切一半）。还没算完时
  /// 先用 [alignment]，算完自动刷新。
  ///
  /// 默认关闭：头像、漫画页这类不该按脸对齐的地方保持原样，只有明确的
  /// 「封面/海报」位置才打开。
  final bool faceFocus;
  final CropMethod faceCropMethod;

  final Map<String, String>? httpHeaders;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// 自定义图片层。加载完成后才会被调用，所以可以用它把「图到齐了」这件事
  /// 转告外层的其它内容（例如让标题和价格跟封面同时出现）。
  final ImageWidgetBuilder? imageBuilder;

  /// 和 [imageBuilder] 一样，但额外拿到算好的对齐方式。
  ///
  /// 传了 [imageBuilder] 就必然要自己造 `Image`，而 `Image` 的 [BoxFit.cover]
  /// 裁哪一块由它自己的 `alignment` 决定 —— 外面 [CachedNetworkImage] 的
  /// `alignment` 传不进去，[faceFocus] 就白开了。这些地方改用本回调。
  final FaceImageBuilder? faceImageBuilder;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  @override
  Widget build(BuildContext context) {
    if (!faceFocus) return _build(alignment);
    return _FaceFocusedImage(
      key: ValueKey<String>(imageUrl),
      image: this,
    );
  }

  /// [faceImageBuilder] 优先：它需要拿到 [resolved] 才能把裁切位置带上。
  ImageWidgetBuilder? _resolvedImageBuilder(Alignment resolved) {
    final faceBuilder = faceImageBuilder;
    if (faceBuilder == null) return imageBuilder;
    return (context, provider) => faceBuilder(context, provider, resolved);
  }

  Widget _build(Alignment resolved) => CachedNetworkImage(
        imageUrl: imageUrl,
        cacheKey: imageCacheKey(imageUrl),
        cacheManager: appImageCacheManager,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        alignment: resolved,
        httpHeaders: httpHeaders,
        placeholder: placeholder,
        errorWidget: errorWidget,
        imageBuilder: _resolvedImageBuilder(resolved),
        fadeInDuration: fadeInDuration,
        fadeOutDuration: fadeOutDuration,
      );
}

/// 和 [ImageWidgetBuilder] 同形，多一个算好的对齐方式。
typedef FaceImageBuilder = Widget Function(
  BuildContext context,
  ImageProvider provider,
  Alignment alignment,
);

/// [AppCachedNetworkImage.faceFocus] 的实现：按检出的人脸挑对齐方式。
///
/// 单独拆出来是为了让它**有状态** —— 人脸检测是异步的，结果回来时要能重建
/// 自己。直接在 [AppCachedNetworkImage] 里做会让所有封面（含头像、漫画页）
/// 都变成有状态组件，那些地方根本用不到。
class _FaceFocusedImage extends StatefulWidget {
  const _FaceFocusedImage({required this.image, super.key});

  final AppCachedNetworkImage image;

  @override
  State<_FaceFocusedImage> createState() => _FaceFocusedImageState();
}

class _FaceFocusedImageState extends State<_FaceFocusedImage> {
  final FaceFocusService _service = FaceFocusService.instance;

  Alignment _alignment = Alignment.center;

  /// 上次算对齐用的目标尺寸。尺寸变了（窗口缩放、卡片变宽）要重算。
  Size? _alignedFor;

  /// 这张图是否已经有检测结果（不管是「有人脸」还是「确认没人脸」）。
  bool _hasResult = false;

  @override
  void initState() {
    super.initState();
    _alignment = widget.image.alignment;
    _service.addListener(_onResult);
    // 首次走到这里就把模型和磁盘缓存预热起来；重复调用是幂等的。
    unawaited(_service.warmUp());
    // headers 要一起带上：Getchu 那类防盗链站点不带 Referer 会 403，
    // 检测这边拿不到图就会被错记成「没有脸」。
    _service.request(widget.image.imageUrl, httpHeaders: widget.image.httpHeaders);
  }

  @override
  void dispose() {
    _service.removeListener(_onResult);
    super.dispose();
  }

  void _onResult() {
    if (!mounted) return;
    // 服务是全局单例，任何一张图算完都会广播。这里只在**自己这张**刚从
    // 「没算过」变成「算完了」时重建一次，别让整屏封面互相触发。
    final has = _service.resultFor(widget.image.imageUrl) != null;
    if (has == _hasResult) return;
    setState(() {
      _hasResult = has;
      _alignedFor = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // 用布局约束而不是 findRenderObject：首帧还没布局时拿不到尺寸，
        // 而 LayoutBuilder 一上来就有可用空间，不会漏掉第一次计算。
        builder: (context, constraints) {
          final image = widget.image;
          final size = _targetSize(
            image.width,
            image.height,
            constraints,
          );
          if (size != null && size != _alignedFor) {
            _alignedFor = size;
            final resolved = faceAlignmentFor(
              image.imageUrl,
              size,
              method: image.faceCropMethod,
            );
            _alignment = resolved ?? image.alignment;

          }
          return image._build(_alignment);
        },
      );
}

/// 图片实际会占据的尺寸。
///
/// 优先用组件自己给的宽高；没给（封面常见的「撑满父级」写法）就用布局给的空间。
/// 都拿不到时返回 null —— 猜一个尺寸去算裁切只会算出错的框。
Size? _targetSize(
  double? explicitWidth,
  double? explicitHeight,
  BoxConstraints constraints,
) {
  var width = explicitWidth;
  var height = explicitHeight;
  // `width: double.infinity` 这种「撑满父级」的写法是有限值判断不出来的：
  // 拿它去算裁切比例会得到无穷大的宽高比，算出来的对齐是 NaN。
  if (width != null && !width.isFinite) width = null;
  if (height != null && !height.isFinite) height = null;
  width ??= constraints.maxWidth.isFinite ? constraints.maxWidth : null;
  height ??= constraints.maxHeight.isFinite ? constraints.maxHeight : null;
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  // 裁切窗口只跟宽高比有关，所以传显示尺寸即可；memCacheWidth 只影响解码
  // 精度，不影响取景。
  return Size(width, height);
}

/// 已经自己拿到 [ImageProvider] 时的人脸取景版本。
///
/// [AppCachedNetworkImage] 只能覆盖「还没开始加载」的地方。缓存页、播放列表
/// 这类卡片往往先算出一个 provider（本地文件优先、没有本地文件才退回网络），
/// 图片加载交给调用处自己管，此时仍按 [faceUrl] 的检测结果决定裁切位置。
///
/// [faceUrl] 为空（纯本地文件、不知道来源封面）时保持居中，不做任何事。
class FaceAlignedImage extends StatefulWidget {
  const FaceAlignedImage({
    required this.provider,
    required this.faceUrl,
    this.fit,
    this.alignment = Alignment.center,
    this.faceCropMethod = CropMethod.mostFaces,
    this.faceHttpHeaders,
    super.key,
  });

  final ImageProvider provider;
  final String? faceUrl;
  final BoxFit? fit;
  final Alignment alignment;
  final CropMethod faceCropMethod;

  /// 检测 [faceUrl] 时要带的请求头（防盗链站点必需）。
  final Map<String, String>? faceHttpHeaders;

  @override
  State<FaceAlignedImage> createState() => _FaceAlignedImageState();
}

class _FaceAlignedImageState extends State<FaceAlignedImage> {
  final FaceFocusService _service = FaceFocusService.instance;

  Alignment _alignment = Alignment.center;
  Size? _alignedFor;
  bool _hasResult = false;

  String? get _url => widget.faceUrl;

  @override
  void initState() {
    super.initState();
    _alignment = widget.alignment;
    _service.addListener(_onResult);
    final url = _url;
    if (url != null) {
      _service.request(url, httpHeaders: widget.faceHttpHeaders);
    }
  }

  @override
  void didUpdateWidget(covariant FaceAlignedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.faceUrl == widget.faceUrl) return;
    _alignedFor = null;
    _hasResult = false;
    final url = _url;
    if (url != null) {
      _service.request(url, httpHeaders: widget.faceHttpHeaders);
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onResult);
    super.dispose();
  }

  void _onResult() {
    if (!mounted) return;
    final url = _url;
    final has = url != null && _service.resultFor(url) != null;
    if (has == _hasResult) return;
    setState(() {
      _hasResult = has;
      _alignedFor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    Widget image(Alignment resolved) => Image(
          image: widget.provider,
          fit: widget.fit,
          alignment: resolved,
        );
    if (url == null) return image(widget.alignment);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _targetSize(null, null, constraints);
        if (size != null && size != _alignedFor) {
          _alignedFor = size;
          _alignment = faceAlignmentFor(
                url,
                size,
                method: widget.faceCropMethod,
              ) ??
              widget.alignment;
        }
        return image(_alignment);
      },
    );
  }
}
