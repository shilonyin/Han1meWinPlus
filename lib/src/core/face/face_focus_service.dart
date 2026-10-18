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

  /// 串行队列：宁可慢一点，也不要几个 isolate 同时啃图片把 CPU 打满。
  Future<void> _queue = Future<void>.value();

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
  void request(String url) {
    if (_unavailable) return;
    if (!_loaded) {
      // 模型还没加载完就来请求：等加载完再补排这一次。
      unawaited(warmUp().then((_) {
        if (_loaded) request(url);
      }));
      return;
    }
    final key = imageCacheKey(url);
    if (_cache.containsKey(key) || _pending.contains(key)) return;
    _pending.add(key);
    _queue = _queue.then((_) => _analyze(url, key)).catchError((Object error) {
      debugPrint('人脸检测失败：$error');
    });
  }

  Future<void> _analyze(String url, String key) async {
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
      final provider = appCachedImage(url, maxWidth: _maxEdge, maxHeight: _maxEdge);
      final image = await _decode(provider);
      if (image == null) {
        _remember(key, _FaceFocusEntry.empty(Size.zero));
        return;
      }
      final width = image.width;
      final height = image.height;
      final imageSize = Size(width.toDouble(), height.toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        _remember(key, _FaceFocusEntry.empty(imageSize));
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
      _pending.remove(key);
    }
  }

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
    return completer.future;
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

/// [FaceFocusService.resultFor] 的返回值。
@immutable
class FaceFocusResult {
  const FaceFocusResult({required this.imageSize, required this.faces});

  final Size imageSize;
  final List<FaceRect> faces;
}

/// 算好某张封面在 [targetSize] 里该用的对齐方式。
///
/// 返回 null 表示「没有人脸」或「还没算完」，调用方沿用原来的居中。
Alignment? faceAlignmentFor(
  String url,
  Size targetSize, {
  CropMethod method = CropMethod.mostFaces,
}) {
  final result = FaceFocusService.instance.resultFor(url);
  if (result == null || result.faces.isEmpty) return null;
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

  factory _FaceFocusEntry.empty(Size imageSize) =>
      _FaceFocusEntry(imageSize: imageSize, faces: const <FaceRect>[]);

  final Size imageSize;
  final List<FaceRect> faces;

  static _FaceFocusEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final width = value['w'];
    final height = value['h'];
    if (width is! num || height is! num) return null;
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