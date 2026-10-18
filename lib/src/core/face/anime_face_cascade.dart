import 'dart:typed_data';

/// 一张人脸在原图像素坐标系下的外接矩形。
class FaceRect {
  const FaceRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get area => width * height;

  /// 跨 isolate 传递统一用 Float64List：每张脸 4 个 double。
  ///
  /// 不直接传对象：dart:ui 的类型没有跨 isolate 传递的保证，
  /// 而 Float64List 是标准库类型，任何 isolate 都能安全接收。
  static Float64List encode(List<FaceRect> faces) {
    final data = Float64List(faces.length * 4);
    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      final offset = i * 4;
      data[offset] = face.left;
      data[offset + 1] = face.top;
      data[offset + 2] = face.width;
      data[offset + 3] = face.height;
    }
    return data;
  }

  static List<FaceRect> decode(Float64List data) {
    final faces = <FaceRect>[];
    for (var i = 0; i + 3 < data.length; i += 4) {
      faces.add(FaceRect(data[i], data[i + 1], data[i + 2], data[i + 3]));
    }
    return faces;
  }

  @override
  String toString() =>
      'FaceRect(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)})';
}

/// lbpcascade_animeface.xml 的纯 Dart 实现。
///
/// 只实现这个模型真正用到的分支：BOOST + LBP 特征 + 每棵树只有一个 stump
/// （模板里的 maxDepth=1）。判定语义对齐 OpenCV 4.x 的
/// modules/objdetect/src/cascadedetect.cpp 中的 predictCategoricalStump
/// 和 LBPEvaluator::OptFeature::calc，因此检出结果与 cv2 基本一致。
///
/// 之所以自己写而不是引 opencv_dart：后者会在构建期下载并编译一整套 OpenCV
/// 静态库，而这里只需要「灰度图 + 积分图 + 二十阶段 LBP 级联」这一小撮功能。
class AnimeFaceCascade {
  AnimeFaceCascade._(this._features, this._stumps, this._stages);

  /// 级联窗口固定 24x24，与 XML 里的 height/width 一致。
  static const int _winSize = 24;

  final List<_LbpFeature> _features;
  final List<_Stump> _stumps;
  final List<_Stage> _stages;

  /// OpenCV XML 格式（opencv_storage/cascade）的解析入口。
  ///
  /// 不引 XML 解析库：这份文件结构固定、只取四类节点，正则足够且快得多。
  factory AnimeFaceCascade.parse(String xml) {
    final stagesBlock =
        RegExp(r'<stages>([\s\S]*?)</stages>').firstMatch(xml)?.group(1);
    final featuresBlock =
        RegExp(r'<features>([\s\S]*?)</features>').firstMatch(xml)?.group(1);
    if (stagesBlock == null || featuresBlock == null) {
      throw const FormatException('级联文件缺少 stages 或 features 节点');
    }

    final features = <_LbpFeature>[
      for (final match in _rectPattern.allMatches(featuresBlock))
        _LbpFeature(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          int.parse(match.group(4)!),
        ),
    ];
    if (features.isEmpty) {
      throw const FormatException('级联文件里没有特征矩形');
    }

    final stumps = <_Stump>[];
    final stages = <_Stage>[];
    // 每个 stage 以注释 <!-- stage N --> 开头，按它切块最稳。
    for (final chunk in stagesBlock.split(_stageCommentPattern).skip(1)) {
      final thresholdText = _stageThresholdPattern.firstMatch(chunk)?.group(1);
      if (thresholdText == null) continue;

      final subsets = _internalNodesPattern
          .allMatches(chunk)
          .map((match) => match.group(1)!.trim().split(_whitespacePattern))
          .toList();
      final leaves = _leafValuesPattern
          .allMatches(chunk)
          .map((match) => match.group(1)!.trim().split(_whitespacePattern))
          .toList();
      if (subsets.length != leaves.length) {
        throw const FormatException('级联文件的 internalNodes 与 leafValues 数量不一致');
      }

      final first = stumps.length;
      for (var i = 0; i < subsets.length; i++) {
        final nodes = subsets[i];
        final leaf = leaves[i];
        if (nodes.length < 11 || leaf.length < 2) {
          throw const FormatException('级联文件的弱分类器节点数不足');
        }
        stumps.add(
          _Stump(
            int.parse(nodes[2]),
            Int32List.fromList([
              for (var bit = 0; bit < 8; bit++) int.parse(nodes[3 + bit]),
            ]),
            double.parse(leaf[0]),
            double.parse(leaf[1]),
          ),
        );
      }
      stages.add(
        _Stage(
          first,
          subsets.length,
          // OpenCV 在读取时统一减掉一个极小值，避免浮点相等误判。
          double.parse(thresholdText) - 1e-5,
        ),
      );
    }
    if (stages.isEmpty) {
      throw const FormatException('级联文件里没有可用的 stage');
    }
    return AnimeFaceCascade._(features, stumps, stages);
  }

  int get stageCount => _stages.length;

  int get stumpCount => _stumps.length;

  int get featureCount => _features.length;

  /// 在 [gray]（单通道、行优先、宽 [width] 高 [height]）上跑多尺度检测。
  ///
  /// 返回原图坐标系下的人脸框，已按 [minNeighbors] 去掉只被少量窗口命中的噪声。
  List<FaceRect> detect(
    Uint8List gray,
    int width,
    int height, {
    double scaleFactor = 1.05,
    int minSize = 24,
    int minNeighbors = 3,
    double eps = 0.2,
  }) {
    if (width < _winSize || height < _winSize) return const <FaceRect>[];
    if (gray.length < width * height) {
      throw ArgumentError(
        '灰度数据长度不足：需要 ${width * height}，实际 ${gray.length}',
      );
    }

    final candidates = <FaceRect>[];
    final features = _features;
    for (var factor = 1.0;; factor *= scaleFactor) {
      final window = (_winSize * factor).round();
      // 和 OpenCV 一样：窗口超出图像就结束整个金字塔。
      if (window > width || window > height) break;
      // 太小的窗口不可能有人脸，跳过能省掉金字塔尾部的绝大部分扫描。
      if (window < minSize) continue;

      final scaledWidth = (width / factor).round();
      final scaledHeight = (height / factor).round();
      if (scaledWidth < _winSize || scaledHeight < _winSize) break;

      final step = factor >= 2 ? 1 : 2;
      final scaled =
          _resize(gray, width, height, scaledWidth, scaledHeight, factor);
      final integral = _integral(scaled, scaledWidth, scaledHeight);
      final stride = scaledWidth + 1;
      final offsets = _featureOffsets(features, stride);

      for (var y = 0; y + _winSize <= scaledHeight; y += step) {
        final rowBase = y * stride;
        for (var x = 0; x + _winSize <= scaledWidth; x += step) {
          if (!_matches(integral, offsets, rowBase + x)) continue;
          final size = _winSize * factor;
          candidates.add(FaceRect(x * factor, y * factor, size, size));
        }
      }
    }
    return _groupCandidates(candidates, eps, minNeighbors);
  }

  /// 把每个特征的 16 个积分图取样点展开成「相对 stride 的扁平偏移」。
  ///
  /// 4x4 网格里第 (col, row) 个点的坐标是 (x + col*w, y + row*h)。
  /// 每层图像尺寸不同，所以偏移只能逐层算一次。
  static Int32List _featureOffsets(List<_LbpFeature> features, int stride) {
    final offsets = Int32List(features.length * 16);
    for (var i = 0; i < features.length; i++) {
      final feature = features[i];
      final base = i * 16;
      for (var row = 0; row < 4; row++) {
        final dy = feature.y + row * feature.height;
        for (var col = 0; col < 4; col++) {
          offsets[base + row * 4 + col] =
              dy * stride + feature.x + col * feature.width;
        }
      }
    }
    return offsets;
  }

  /// 单个窗口的级联判定：任一 stage 不通过就直接返回 false。
  bool _matches(Int32List integral, Int32List offsets, int base) {
    final stumps = _stumps;
    for (final stage in _stages) {
      var sum = 0.0;
      final end = stage.first + stage.count;
      for (var i = stage.first; i < end; i++) {
        final stump = stumps[i];
        final offset = stump.feature * 16;

        final a0 = integral[base + offsets[offset]];
        final a1 = integral[base + offsets[offset + 1]];
        final a2 = integral[base + offsets[offset + 2]];
        final a3 = integral[base + offsets[offset + 3]];
        final a4 = integral[base + offsets[offset + 4]];
        final a5 = integral[base + offsets[offset + 5]];
        final a6 = integral[base + offsets[offset + 6]];
        final a7 = integral[base + offsets[offset + 7]];
        final a8 = integral[base + offsets[offset + 8]];
        final a9 = integral[base + offsets[offset + 9]];
        final a10 = integral[base + offsets[offset + 10]];
        final a11 = integral[base + offsets[offset + 11]];
        final a12 = integral[base + offsets[offset + 12]];
        final a13 = integral[base + offsets[offset + 13]];
        final a14 = integral[base + offsets[offset + 14]];
        final a15 = integral[base + offsets[offset + 15]];

        // 中心格。区域和 = 左上 - 右上 - 左下 + 右下。
        final center = a5 - a6 - a9 + a10;
        // 八个方向各占一位，比较是 >=（相等记作 1），与 OpenCV 一致。
        var code = 0;
        if (a0 - a1 - a4 + a5 >= center) code |= 128;
        if (a1 - a2 - a5 + a6 >= center) code |= 64;
        if (a2 - a3 - a6 + a7 >= center) code |= 32;
        if (a6 - a7 - a10 + a11 >= center) code |= 16;
        if (a10 - a11 - a14 + a15 >= center) code |= 8;
        if (a9 - a10 - a13 + a14 >= center) code |= 4;
        if (a8 - a9 - a12 + a13 >= center) code |= 2;
        if (a4 - a5 - a8 + a9 >= center) code |= 1;

        // subset 是 256 位位图：该位为 1 取 left，否则取 right。
        sum += ((stump.subset[code >> 5] >> (code & 31)) & 1) != 0
            ? stump.left
            : stump.right;
      }
      if (sum < stage.threshold) return false;
    }
    return true;
  }

  /// 贪心聚类：把同一个物体的多个命中窗口合成一个框。
  ///
  /// 同一张脸会在相邻几层金字塔和相邻几列扫描位置重复命中，这些框大小差一个
  /// 缩放步长、中心点却几乎重合。所以判同类看的是「中心距离相对框尺寸」，
  /// 而不是 OpenCV 那种同层比较 left/top —— 后者在小尺度上会把同一张脸拆成
  /// 好几个框。合并后按命中次数过 [minNeighbors] 的门。
  static List<FaceRect> _groupCandidates(
    List<FaceRect> candidates,
    double eps,
    int minNeighbors,
  ) {
    if (candidates.isEmpty) return const <FaceRect>[];
    final sorted = List<FaceRect>.of(candidates)
      ..sort((a, b) => b.area.compareTo(a.area));

    final clusters = <List<FaceRect>>[];
    for (final candidate in sorted) {
      var merged = false;
      for (final cluster in clusters) {
        final anchor = cluster.first;
        // 用较小框的尺寸做容差基准：大框套小框时不能放宽到把两张脸并成一张。
        final reference =
            candidate.width < anchor.width ? candidate.width : anchor.width;
        final tolerance = eps * 2 * reference;
        final dx = candidate.centerX - anchor.centerX;
        final dy = candidate.centerY - anchor.centerY;
        if (dx * dx + dy * dy <= tolerance * tolerance) {
          cluster.add(candidate);
          merged = true;
          break;
        }
      }
      if (!merged) clusters.add(<FaceRect>[candidate]);
    }

    final faces = <FaceRect>[];
    for (final cluster in clusters) {
      if (cluster.length < minNeighbors) continue;
      var left = 0.0;
      var top = 0.0;
      var width = 0.0;
      var height = 0.0;
      for (final rect in cluster) {
        left += rect.left;
        top += rect.top;
        width += rect.width;
        height += rect.height;
      }
      final count = cluster.length;
      faces.add(
        FaceRect(left / count, top / count, width / count, height / count),
      );
    }
    return faces;
  }

  /// 双线性缩小到目标尺寸。
  ///
  /// [factor] 是原图与缩放后的比值（源坐标 = 目标坐标 * factor）。
  static Uint8List _resize(
    Uint8List src,
    int srcWidth,
    int srcHeight,
    int dstWidth,
    int dstHeight,
    double factor,
  ) {
    if (srcWidth == dstWidth && srcHeight == dstHeight) return src;
    final dst = Uint8List(dstWidth * dstHeight);
    for (var y = 0; y < dstHeight; y++) {
      final sourceY = y * factor;
      final y0 = sourceY.toInt();
      final y1 = y0 + 1 < srcHeight ? y0 + 1 : srcHeight - 1;
      final fy = sourceY - y0;
      final row0 = y0 * srcWidth;
      final row1 = y1 * srcWidth;
      final dstRow = y * dstWidth;
      for (var x = 0; x < dstWidth; x++) {
        final sourceX = x * factor;
        final x0 = sourceX.toInt();
        final x1 = x0 + 1 < srcWidth ? x0 + 1 : srcWidth - 1;
        final fx = sourceX - x0;
        final top = src[row0 + x0] * (1 - fx) + src[row0 + x1] * fx;
        final bottom = src[row1 + x0] * (1 - fx) + src[row1 + x1] * fx;
        dst[dstRow + x] =
            (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
      }
    }
    return dst;
  }

  /// 积分图，尺寸 (width + 1) x (height + 1)，左上角补一列/行 0。
  static Int32List _integral(Uint8List src, int width, int height) {
    final stride = width + 1;
    final sum = Int32List(stride * (height + 1));
    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      final srcRow = y * width;
      final dstRow = (y + 1) * stride;
      final prevRow = y * stride;
      for (var x = 0; x < width; x++) {
        rowSum += src[srcRow + x];
        sum[dstRow + x + 1] = sum[prevRow + x + 1] + rowSum;
      }
    }
    return sum;
  }

  static final RegExp _rectPattern =
      RegExp(r'<rect>\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*</rect>');
  static final RegExp _stageCommentPattern =
      RegExp(r'<!--\s*stage\s+\d+\s*-->');
  static final RegExp _stageThresholdPattern =
      RegExp(r'<stageThreshold>\s*([^<]+?)\s*</stageThreshold>');
  static final RegExp _internalNodesPattern =
      RegExp(r'<internalNodes>\s*([^<]+?)\s*</internalNodes>');
  static final RegExp _leafValuesPattern =
      RegExp(r'<leafValues>\s*([^<]+?)\s*</leafValues>');
  static final RegExp _whitespacePattern = RegExp(r'\s+');
}

class _LbpFeature {
  const _LbpFeature(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

class _Stump {
  const _Stump(this.feature, this.subset, this.left, this.right);

  final int feature;

  /// 256 个 LBP 码的位图，8 个 32 位整数。
  final Int32List subset;
  final double left;
  final double right;
}

class _Stage {
  const _Stage(this.first, this.count, this.threshold);

  final int first;
  final int count;
  final double threshold;
}
