import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show Alignment;

/// 裁剪方式。语义与参考实现 PRPR（原 UWP `BooruViewer.Services.CropBitmap`）一致。
enum CropMethod {
  /// 不裁，整图缩放。
  none,

  /// 居中裁：横图裁左右、竖图裁上下。
  center,

  /// 顶部居中裁：横图裁左右居中、竖图从顶部留。
  topMiddle,

  /// 只要最大的那张脸。
  biggestFace,

  /// 在装得下的前提下尽量多留脸。
  mostFaces,
}

/// 封面裁剪计算：给定原图尺寸、目标显示尺寸、检测到的人脸框，算出该取原图的哪一块。
///
/// 逐行移植自 PRPR 的 `app/lib/services/crop.dart`（其本身移植自
/// `BooruViewer\\Services\\CropBitmap.cs`）。保持分支顺序与浮点运算顺序不变，
/// 这样同一张图 + 同一组人脸框能得到与参考实现一致的结果。
///
/// 这里之所以不直接照抄、而是加 [alignmentFor]：本项目所有封面最终都走
/// `CachedNetworkImage` 的 `BoxFit.cover + alignment` 渲染，拿不到自定义裁剪矩形。
/// [alignmentFor] 把裁剪窗口换算成等价的 [Alignment] —— `BoxFit.cover` 的
/// `applyBoxFit` 取出的源区域比例恒等于目标框比例，窗口本身又至少有一边顶满原图，
/// 所以两者是同一个矩形，换算无损。
class FaceCrop {
  FaceCrop._();

  /// 居中裁剪：按目标宽高比决定裁掉左右还是上下。
  static Rect centerCrop(Size imageSize, Size requiredSize) {
    final imageRatio = imageSize.width / imageSize.height;
    final requiredRatio = requiredSize.width / requiredSize.height;

    if (imageRatio > requiredRatio) {
      final newWidth = imageSize.height * requiredRatio;
      final left = (imageSize.width - newWidth) / 2;
      return Rect.fromLTWH(left, 0, newWidth, imageSize.height);
    }
    final newHeight = imageSize.width / requiredRatio;
    final top = (imageSize.height - newHeight) / 2;
    return Rect.fromLTWH(0, top, imageSize.width, newHeight);
  }

  /// 顶部居中裁剪：横图裁左右居中；竖图从顶部裁，让内容留在上半部分。
  ///
  /// 这是无人脸时的兜底，也是「人脸没检出来」时最稳的默认值 —— 海报的主体
  /// （脸、标题）绝大多数压在上半张，居中裁常把人的头切掉一半。
  static Rect topMiddleCrop(Size imageSize, Size requiredSize) {
    final imageRatio = imageSize.width / imageSize.height;
    final requiredRatio = requiredSize.width / requiredSize.height;

    if (imageRatio > requiredRatio) {
      final newWidth = imageSize.height * requiredRatio;
      final left = (imageSize.width - newWidth) / 2;
      return Rect.fromLTWH(left, 0, newWidth, imageSize.height);
    }
    final newHeight = imageSize.width / requiredRatio;
    return Rect.fromLTWH(0, 0, imageSize.width, newHeight);
  }

  /// 贪心裁剪：在保证装下尽可能多的脸的前提下，让裁剪窗口尽量贴合人脸区域。
  ///
  /// 1. 没有人脸 → 退化为 [topMiddleCrop]；
  /// 2. 脸按尺寸降序排序（横图按宽、竖图按高）；
  /// 3. 循环剔除最小的脸，直到剩余脸能全部装进窗口；
  /// 4. 装得下 → 按人脸包围盒贴合；
  ///    装不下（单张最大的脸都超出窗口）→ 以最大脸中心开窗。
  static Rect greedyCrop(
    Size imageSize,
    Size requiredSize,
    List<Rect> faces,
  ) {
    if (faces.isEmpty) return topMiddleCrop(imageSize, requiredSize);

    final isImageTooWide = imageSize.width / imageSize.height >
        requiredSize.width / requiredSize.height;

    final working = List<Rect>.of(faces);

    if (isImageTooWide) {
      working.sort((a, b) => b.width.compareTo(a.width));
    } else {
      working.sort((a, b) => b.height.compareTo(a.height));
    }

    // 窗口在该方向上的长度是固定的：横图受限于高，竖图受限于宽。
    final windowExtent = isImageTooWide
        ? imageSize.height * requiredSize.width / requiredSize.height
        : imageSize.width * requiredSize.height / requiredSize.width;

    while (working.length > 1) {
      if (_fitsInWindow(working, windowExtent, isImageTooWide)) break;
      working.removeLast();
    }

    if (!_fitsInWindow(working, windowExtent, isImageTooWide)) {
      return cropAroundCenter(imageSize, requiredSize, working.first.center);
    }

    return isImageTooWide
        ? _optimizedCropH(imageSize, requiredSize, working)
        : _optimizedCropV(imageSize, requiredSize, working);
  }

  /// 人脸在某个方向上的跨度是否不超过窗口长度。
  static bool _fitsInWindow(
    List<Rect> faces,
    double windowExtent,
    bool isImageTooWide,
  ) {
    if (faces.isEmpty) return false;
    final double minEdge;
    final double maxEdge;
    if (isImageTooWide) {
      minEdge = faces.map((f) => f.left).reduce(math.min);
      maxEdge = faces.map((f) => f.right).reduce(math.max);
    } else {
      minEdge = faces.map((f) => f.top).reduce(math.min);
      maxEdge = faces.map((f) => f.bottom).reduce(math.max);
    }
    return (maxEdge - minEdge) <= windowExtent;
  }

  /// 横图版贴合：窗口宽度固定（= 高度 × 目标比例），左右留白按人脸包围盒的
  /// 左右剩余空间比例分配。
  static Rect _optimizedCropH(
    Size imageSize,
    Size requiredSize,
    List<Rect> faces,
  ) {
    final left = faces.map((f) => f.left).reduce(math.min);
    final right = faces.map((f) => f.right).reduce(math.max);

    final finalWidth =
        imageSize.height * requiredSize.width / requiredSize.height;

    final leftSpace = left;
    final rightSpace = imageSize.width - right;
    final totalSpace = leftSpace + rightSpace;

    // 两侧都没有余量时（贴边）直接左对齐，避免除零。
    final leftRightRatio = totalSpace <= 0 ? 0.0 : leftSpace / totalSpace;

    final overflow = finalWidth - (right - left);
    final leftFinalSpace = left - overflow * leftRightRatio;

    return Rect.fromLTWH(leftFinalSpace, 0, finalWidth, imageSize.height);
  }

  /// 竖图版贴合：窗口高度固定，上下留白按比例分配。
  static Rect _optimizedCropV(
    Size imageSize,
    Size requiredSize,
    List<Rect> faces,
  ) {
    final top = faces.map((f) => f.top).reduce(math.min);
    final bottom = faces.map((f) => f.bottom).reduce(math.max);

    final finalHeight =
        imageSize.width * requiredSize.height / requiredSize.width;

    final topSpace = top;
    final bottomSpace = imageSize.height - bottom;
    final totalSpace = topSpace + bottomSpace;

    final topBottomRatio = totalSpace <= 0 ? 0.0 : topSpace / totalSpace;

    final overflow = finalHeight - (bottom - top);
    final topFinalSpace = top - overflow * topBottomRatio;

    return Rect.fromLTWH(0, topFinalSpace, imageSize.width, finalHeight);
  }

  /// 以指定点为中心开窗，窗口按目标宽高比取最大。结果夹紧到图片边界内。
  static Rect cropAroundCenter(
    Size imageSize,
    Size requiredSize,
    Offset center,
  ) {
    final imageRatio = imageSize.width / imageSize.height;
    final requiredRatio = requiredSize.width / requiredSize.height;

    final double w;
    final double h;
    if (imageRatio > requiredRatio) {
      h = imageSize.height;
      w = h * requiredRatio;
    } else {
      w = imageSize.width;
      h = w / requiredRatio;
    }

    var left = center.dx - w / 2;
    var top = center.dy - h / 2;

    left = left.clamp(0.0, math.max(0.0, imageSize.width - w));
    top = top.clamp(0.0, math.max(0.0, imageSize.height - h));

    return Rect.fromLTWH(left, top, w, h);
  }

  /// 按方式分派。人脸框为空时 [CropMethod.mostFaces] / [CropMethod.biggestFace]
  /// 都退化为 [topMiddleCrop]。
  static Rect compute(
    CropMethod method,
    Size imageSize,
    Size requiredSize, {
    List<Rect> faces = const <Rect>[],
  }) {
    switch (method) {
      case CropMethod.none:
        return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      case CropMethod.center:
        return centerCrop(imageSize, requiredSize);
      case CropMethod.topMiddle:
        return topMiddleCrop(imageSize, requiredSize);
      case CropMethod.biggestFace:
        if (faces.isEmpty) return topMiddleCrop(imageSize, requiredSize);
        final biggest = faces
            .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
        return greedyCrop(imageSize, requiredSize, <Rect>[biggest]);
      case CropMethod.mostFaces:
        if (faces.isEmpty) return topMiddleCrop(imageSize, requiredSize);
        return greedyCrop(imageSize, requiredSize, faces);
    }
  }

  /// 把人脸坐标从「检测时用的缩略图尺寸」映射回「原图尺寸」。
  ///
  /// 检测在长边压到 1024 的缩略图上跑（快一个数量级），框必须按比例放大才能
  /// 用于原图裁剪。
  static List<Rect> scaleFaces(List<Rect> faces, Size from, Size to) {
    if (from.width <= 0 || from.height <= 0) return faces;
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    return faces
        .map((f) => Rect.fromLTWH(
              f.left * sx,
              f.top * sy,
              f.width * sx,
              f.height * sy,
            ))
        .toList();
  }

  /// 把裁剪窗口换算成 [Alignment]，供 `BoxFit.cover` 的图片直接使用。
  ///
  /// `Alignment.inscribe` 把尺寸为窗口的源区域放进整图时，水平偏移是
  /// `(imageWidth - windowWidth) * (x + 1) / 2`，反解即得：
  /// `x = windowLeft / (imageWidth - windowWidth) * 2 - 1`。
  /// 窗口在某一方向上顶满整图时该轴上没有可移动余量，取 0（等价居中）。
  static Alignment alignmentFor(Rect window, Size imageSize) {
    final slackX = imageSize.width - window.width;
    final slackY = imageSize.height - window.height;
    final x = slackX > 0.001
        ? ((window.left / slackX) * 2 - 1).clamp(-1.0, 1.0)
        : 0.0;
    final y = slackY > 0.001
        ? ((window.top / slackY) * 2 - 1).clamp(-1.0, 1.0)
        : 0.0;
    return Alignment(x, y);
  }

  /// 一步到位：原图尺寸 + 目标显示尺寸 + 人脸框 → 该用的 [Alignment]。
  ///
  /// [faces] 必须是**原图坐标系**下的框（缩略图上检出的先过 [scaleFaces]）。
  static Alignment alignmentForFaces({
    required Size imageSize,
    required Size targetSize,
    required List<Rect> faces,
    CropMethod method = CropMethod.mostFaces,
  }) {
    final window = compute(method, imageSize, targetSize, faces: faces);
    return alignmentFor(window, imageSize);
  }
}
