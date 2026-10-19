import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart'
    show Alignment, ImageConfiguration, ImageProvider, ImageStreamListener, Size;
import 'package:flutter/services.dart' show rootBundle;

import '../../data/local/json_store.dart';
import '../../features/shared/app_image_cache.dart';
import 'anime_face_cascade.dart';
import 'face_crop.dart';

/// 封面人脸检测的后台调度 + 结果缓存。
///
/// 拆成两段的原因：级联检测一张 1024 长边的封面要 400～600ms，直接跑会把
/// 界面冻住半秒以上。
///
/// 1. 主 isolate 只负责拿到解码好的位图 —— 图片本来就被 `CachedNetworkImage`
///    解码过一次，这里复用同一个 `ImageCache` 条目，几乎不额外花时间；
/// 2. 缩放 + 转灰度 + 跑级联全部丢进 [Isolate.run]。
///
/// 结果按 [imageCacheKey] 落盘到 `face_focus.json`，同一张封面只算一次。
/// 检测失败、解码失败一律当作「没有人脸」记下来，避免反复重试。
class FaceFocusService extends ChangeNotifier {
  FaceFocusService._();

  static final FaceFocusService instance = FaceFocusService._();

  /// 持久化文件名（落在 `%APPDATA%\\han1me_win_plus` 下）。
  static const String _storeFile = 'face_focus.json';

  /// 检测时把长边压到这个尺寸以内。级联参数（minSize=30）就是在这个尺度上
  /// 调出来的，原图直接跑会慢一个数量级。
  static const int _maxEdge = 1024;

  static const double _scaleFactor = 1.05;
  static const int _minSize = 30;
  static const int _minNeighbors = 5;

  static const String _cascadeAsset = 'assets/face/lbpcascade_animeface.xml';

  final JsonStore _store = JsonStore();

  /// key = [imageCacheKey(url)]，value = 框 + 原图尺寸。
  final Map<String, _FaceFocusEntry> _cache = <String, _FaceFocusEntry>{};

  /// 已排队或正在算的 key，防止同一张封面被重复提交。
  final Set<String> _pending = <String>{};

  /// 这次会话里下载/解码失败的 key。
  ///
  /// 失败的封面**不能**当成「没有人脸」写进磁盘缓存：那会把一次临时网络错误
  /// 永久固化成 0x0 尺寸的条目，之后这张图再也拿不到人脸对齐，也没有任何
  /// 重试机会。同理也不能不加限制地重排 —— 图真的挂了就是每次 build 都重试。
  /// 折中：只在本次会话内记住失败，下次启动再试一遍。
  final Set<String> _failed = <String>{};

  /// 待检测的封面，按提交顺序排队；[urgent] 的排在前面。
  ///
  /// 以前是纯串行的单链队列：首页一屏几十张封面排下来要几十秒，翻到第二张
  /// 时它还在队尾没轮到 —— 表现就是「人脸取景只有第一张生效」。现在两路
  /// 并发，并且允许插队：首屏一眼就能看到的大图（轮播横幅）先算。
  final List<_FaceJob> _jobs = <_FaceJob>[];

  /// 同时跑几个检测 isolate。两个已经能喂满常见四核；再多只是跟界面抢 CPU，
  /// 单张的耗时并不会变短。
  static const int _concurrency = 2;

  int _running = 0;

  Future<void>? _warmUp;
  String? _cascadeXml;
  bool _loaded = false;

  /// 模型没打进包（或资源读失败）：整个功能静默降级为「居中裁切」，
  /// 不要再排队、也不要每次 build 都重试。
  bool _unavailable = false;

  bool get isReady => _loaded;

  /// 读取磁盘缓存 + 载入级联模型。可重复调用，只会执行一次。
  Future<void> warmUp() => _warmUp ??= _load();

  Future<void> _load() async {
    _cascadeXml = await _loadCascade();
    if (_cascadeXml == null) {
      _unavailable = true;
      return;
    }
    try {
      final raw = await _store.read(_storeFile);
      raw.forEach((key, value) {
        final parsed = _FaceFocusEntry.fromJson(value);
        if (parsed != null) _cache[key] = parsed;
      });
    } catch (error) {
      debugPrint('人脸缓存读取失败：$error');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<String?> _loadCascade() async {
    try {
      return await rootBundle.loadString(_cascadeAsset);
    } catch (error, stack) {
      debugPrint('人脸模型加载失败：$error\n$stack');
      return null;
    }
  }

  /// 已缓存的检测结果；null 表示「还没算过」。
  ///
  /// 区分「没算过」和「算过但没人脸」很重要：前者要继续排队，后者要立刻
  /// 走兜底对齐，不能一直等。
  FaceFocusResult? resultFor(String url) {
    if (!_loaded) return null;
    final entry = _cache[imageCacheKey(url)];
    if (entry == null) return null;
    return FaceFocusResult(imageSize: entry.imageSize, faces: entry.faces);
  }

  /// 请求检测某张封面。已缓存或已在队列中的会被忽略。
  ///
  /// [urgent] 给首屏就能看到的大图（轮播横幅）用：插到待办队首，优先算完。
  void request(
    String url, {
    bool urgent = false,
    Map<String, String>? httpHeaders,
  }) {
    if (_unavailable) return;
    if (!_loaded) {
      // 模型还没加载完就来请求：等加载完再补排这一次。
      unawaited(warmUp().then((_) {
        if (_loaded) request(url, urgent: urgent, httpHeaders: httpHeaders);
      }));
      return;
    }
    final key = imageCacheKey(url);
    if (_cache.containsKey(key) ||
        _pending.contains(key) ||
        _failed.contains(key)) {
      return;
    }
    _pending.add(key);
    final job = _FaceJob(url, key, urgent: urgent, httpHeaders: httpHeaders);
    if (urgent) {
      // 插在最后一个 urgent 之后，同一批预排保持原本的顺序。
      var index = 0;
      while (index < _jobs.length && _jobs[index].urgent) {
        index++;
      }
      _jobs.insert(index, job);
    } else {
      _jobs.add(job);
    }
    _pump();
  }

  /// 预约一批封面，全部按插队处理。
  ///
  /// 轮播横幅要用的 —— 它一次只把**当前一屏**建出来（PageView 默认不预建
  /// 邻页），于是第二张起的封面要等用户真的翻过去才发起检测，再排在半屏
  /// 网格封面后面，翻过去时看到的还是居中裁切。开头就把这一批全排进去，
  /// 翻到第几张都已经算好了。
  void prefetch(
    Iterable<String> urls, {
    Map<String, String>? httpHeaders,
  }) {
    for (final url in urls) {
      request(url, urgent: true, httpHeaders: httpHeaders);
    }
  }

  /// 在并发额度内把待办的检测都拉起来。
  void _pump() {
    while (_running < _concurrency && _jobs.isNotEmpty) {
      final job = _jobs.removeAt(0);
      _running++;
      unawaited(
        _analyze(job.url, job.key, job.httpHeaders).catchError((Object error) {
          // _analyze 自己会吞掉异常；能走到这里的只有它没料到的错误。
          // 不清掉 _pending 的话这张封面会被永久标记为"在算"，再也不会重试。
          _pending.remove(job.key);
          debugPrint('人脸检测失败：$error');
        }).whenComplete(() {
          _running--;
          // 这一张算完可能又有新图入队，继续把额度填满。
          _pump();
        }),
      );
    }
  }

  Future<void> _analyze(
    String url,
    String key,
    Map<String, String>? httpHeaders,
  ) async {
    // 级联模型文本要先取到局部变量：`Isolate.run` 的闭包只允许捕获可发送
    // 的对象，直接读实例字段 `_cascadeXml` 会把整个 service 一起捕获进去。
    final xml = _cascadeXml;
    if (xml == null) {
      _pending.remove(key);
      return;
    }
    try {
      // 解码时就把长边压到 _maxEdge：封面原图可能是几千像素，全尺寸解码
      // 在内存里是几十 MB，而检测只需要 1024 以内。缩放在解码器里做，比先
      // 解全尺寸再拷贝出来省得多。
      // 宽高都给上限：只给 maxWidth 的话竖图（宽度本来就小于它）不会缩。
      // headers 必须和显示层完全一致：Getchu 这类防盗链站点在缺 Referer 时
      // 直接 403，检测这边拿不到图就会把这张封面错记成「没有人脸」。
      //
      // cacheKeySuffix 也必须给：检测和显示共用同一条 cacheKey 时会撞进
      // flutter_cache_manager 的并发队列竞态（详细说明见 appCachedImage 的注释），
      // 结果是显示层那张图永远停在占位态。加后缀＝各走各的缓存条目。
      final provider = appCachedImage(
        url,
        maxWidth: _maxEdge,
        maxHeight: _maxEdge,
        httpHeaders: httpHeaders,
        cacheKeySuffix: '#face',
      );
      final image = await _decode(provider);
      if (image == null) {
        // 拿不到图 ≠ 没有人脸。只记失败、不落盘，下次启动再来。
        _failed.add(key);
        _pending.remove(key);
        return;
      }
      final width = image.width;
      final height = image.height;
      final imageSize = Size(width.toDouble(), height.toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        // 解码成功但没有像素：当作「确认没有人脸」，用真实尺寸兜底。
        _remember(key, _FaceFocusEntry(imageSize: imageSize, faces: const []));
        return;
      }
      // 原图位图已经拷出来了，这份全尺寸解码结果没必要继续占着 ImageCache ——
      // 卡片自己用的是按 memCacheWidth 解码的小图，是另一份缓存条目。留着它只
      // 会挤占额度，让正在显示的封面被挤出去重新解码。
      // 位图已经拷出来了，这份解码结果没必要继续占着 ImageCache 的额度，
      // 让它挤掉正在显示的封面。evict 要打在**同一个** provider 上：
      // ImageCache 的键由 cacheKey/scale/maxWidth/maxHeight 共同决定。
      unawaited(provider.evict());
      final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final rects = await Isolate.run(
        () => _detectJob(<Object?>[
          TransferableTypedData.fromList(<Uint8List>[rgba]),
          width,
          height,
          xml,
          _maxEdge,
          _scaleFactor,
          _minSize,
          _minNeighbors,
        ]),
      );
      _remember(
        key,
        _FaceFocusEntry(
          imageSize: imageSize,
          faces: <FaceRect>[
            for (var i = 0; i + 3 < rects.length; i += 4)
              FaceRect(rects[i], rects[i + 1], rects[i + 2], rects[i + 3]),
          ],
        ),
      );
    } catch (error, stack) {
      debugPrint('人脸检测异常：$error\n$stack');
      _failed.add(key);
      _pending.remove(key);
    }
  }

  /// 解码上限。超过就按「这次没算成」处理，绝不写进缓存。
  ///
  /// 没有超时的话，一次卡住的下载会让这张封面永远停在「排队中」，后面的
  /// 封面跟着堵（每张都在等一个可能永远不回来的 Future）。
  static const Duration _decodeTimeout = Duration(seconds: 20);

  Future<ui.Image?> _decode(ImageProvider provider) {
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    // 超时后补完成 null 并摘掉监听，避免这条流一直挂着。
    return completer.future.timeout(_decodeTimeout, onTimeout: () {
      stream.removeListener(listener);
      return null;
    });
  }

  void _remember(String key, _FaceFocusEntry entry) {
    _cache[key] = entry;
    _pending.remove(key);

    notifyListeners();
    unawaited(_persist());
  }

  /// 整份快照写盘。结果只增不改，直接全量覆盖即可。
  Future<void> _persist() async {
    try {
      await _store.write(_storeFile, <String, dynamic>{
        for (final entry in _cache.entries) entry.key: entry.value.toJson(),
      });
    } catch (error) {
      debugPrint('人脸缓存写入失败：$error');
    }
  }
}

/// 排队中的一次检测。
class _FaceJob {
  const _FaceJob(
    this.url,
    this.key, {
    this.urgent = false,
    this.httpHeaders,
  });

  final String url;
  final String key;
  final Map<String, String>? httpHeaders;

  /// 首屏就能看到的大图，插队优先算。
  final bool urgent;
}

/// [FaceFocusService.resultFor] 的返回值。
@immutable
class FaceFocusResult {
  const FaceFocusResult({required this.imageSize, required this.faces});

  final Size imageSize;
  final List<FaceRect> faces;
}

/// 算好某张封面在 [targetSize] 里该用的对齐方式。
///
/// 返回 null 只表示「这张还没算完」，调用方先沿用原来的居中、算完再刷。
///
/// **算完确认没有人脸时不再返回 null** —— 那时走 [CropMethod.mostFaces] 内部的
/// 兜底 [FaceCrop.topMiddleCrop]，顶部对齐。之前的写法在这里提前 return，把
/// 「多半张海报主体压在上半部分」这个信息一起丢了：没人脸的封面于是永远居中，
/// 跟没开这个功能一模一样。
Alignment? faceAlignmentFor(
  String url,
  Size targetSize, {
  CropMethod method = CropMethod.mostFaces,
}) {
  final result = FaceFocusService.instance.resultFor(url);
  if (result == null) return null;
  if (targetSize.width <= 0 || targetSize.height <= 0) return null;
  if (result.imageSize.width <= 0 || result.imageSize.height <= 0) return null;
  return FaceCrop.alignmentForFaces(
    imageSize: result.imageSize,
    targetSize: targetSize,
    faces: <ui.Rect>[
      for (final face in result.faces)
        ui.Rect.fromLTWH(face.left, face.top, face.width, face.height),
    ],
    method: method,
  );
}

class _FaceFocusEntry {
  const _FaceFocusEntry({required this.imageSize, required this.faces});

  final Size imageSize;
  final List<FaceRect> faces;

  static _FaceFocusEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final width = value['w'];
    final height = value['h'];
    if (width is! num || height is! num) return null;
    // 0x0 是旧版本在「图没取到」时写下的错误条目。它会让 faceAlignmentFor
    // 一直返回 null（当作还没算完），这张封面从此再也拿不到对齐，直接丢掉。
    if (width <= 0 || height <= 0) return null;
    final faces = <FaceRect>[];
    final raw = value['f'];
    if (raw is List) {
      for (final item in raw) {
        if (item is List && item.length >= 4) {
          final l = item[0];
          final t = item[1];
          final w = item[2];
          final h = item[3];
          if (l is num && t is num && w is num && h is num) {
            faces.add(
              FaceRect(l.toDouble(), t.toDouble(), w.toDouble(), h.toDouble()),
            );
          }
        }
      }
    }
    return _FaceFocusEntry(
      imageSize: Size(width.toDouble(), height.toDouble()),
      faces: faces,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'w': imageSize.width,
        'h': imageSize.height,
        'f': <List<int>>[
          for (final face in faces)
            <int>[
              face.left.round(),
              face.top.round(),
              face.width.round(),
              face.height.round(),
            ],
        ],
      };
}

/// 后台 isolate 入口：缩放 → 灰度 → 级联检测，返回扁平的 (l, t, w, h)。
///
/// 必须是顶层函数，[Isolate.run] 才能把它发过去。
List<double> _detectJob(List<Object?> args) {
  final rgba = (args[0]! as TransferableTypedData).materialize().asUint8List();
  final width = args[1]! as int;
  final height = args[2]! as int;
  final xml = args[3]! as String;
  final maxEdge = args[4]! as int;
  final scaleFactor = args[5]! as double;
  final minSize = args[6]! as int;
  final minNeighbors = args[7]! as int;

  final longEdge = width > height ? width : height;
  final ratio = longEdge > maxEdge ? maxEdge / longEdge : 1.0;
  final smallWidth = (width * ratio).round();
  final smallHeight = (height * ratio).round();

  // 最近邻缩放到目标尺寸，顺手转灰度 —— 一步完成，省一次遍历。
  // 采样方式与批量探针保持一致，否则同一张图在探针和实际运行里可能给出不同框。
  final gray = Uint8List(smallWidth * smallHeight);
  final inv = 1 / ratio;
  final sameSize = ratio == 1.0;
  for (var y = 0; y < smallHeight; y++) {
    final srcRow = (sameSize ? y : (y * inv).floor()) * width * 4;
    final dstRow = y * smallWidth;
    for (var x = 0; x < smallWidth; x++) {
      final offset = srcRow + (sameSize ? x : (x * inv).floor()) * 4;
      gray[dstRow + x] = (0.299 * rgba[offset] +
              0.587 * rgba[offset + 1] +
              0.114 * rgba[offset + 2])
          .round();
    }
  }

  final cascade = AnimeFaceCascade.parse(xml);
  final faces = cascade.detect(
    gray,
    smallWidth,
    smallHeight,
    scaleFactor: scaleFactor,
    minSize: minSize,
    minNeighbors: minNeighbors,
  );

  // 检测是在缩略图上做的，坐标要按比例放回原图。
  return <double>[
    for (final face in faces) ...[
      face.left * inv,
      face.top * inv,
      face.width * inv,
      face.height * inv,
    ],
  ];
}