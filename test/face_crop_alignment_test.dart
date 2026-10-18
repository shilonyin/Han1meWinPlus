import 'dart:ui';
import 'package:flutter/painting.dart' show applyBoxFit, BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/face/face_crop.dart';

void main() {
  test('cover 的源窗口等于 FaceCrop 选出的窗口', () {
    const cases = <List<Object>>[
      [Size(800, 1200), Size(400, 200)], // 竖图塞宽框
      [Size(1920, 720), Size(400, 500)], // 横图塞竖框
      [Size(640, 360), Size(1000, 200)],
      [Size(1000, 1000), Size(300, 100)],
    ];
    for (final c in cases) {
      final imageSize = c[0] as Size;
      final targetSize = c[1] as Size;
      final faces = <Rect>[
        Rect.fromLTWH(
          imageSize.width * 0.3,
          imageSize.height * 0.05,
          imageSize.width * 0.3,
          imageSize.width * 0.3,
        ),
      ];
      final window = FaceCrop.compute(
        CropMethod.mostFaces,
        imageSize,
        targetSize,
        faces: faces,
      );
      final alignment = FaceCrop.alignmentFor(window, imageSize);

      // 复现 Image 组件在 cover 下的取景：先算出源子矩形尺寸，再按 alignment 摆位。
      final fitted = applyBoxFit(BoxFit.cover, imageSize, targetSize);
      final rect = alignment.inscribe(fitted.source, Offset.zero & imageSize);

      expect(rect.left, closeTo(window.left, 1.5));
      expect(rect.top, closeTo(window.top, 1.5));
      expect(rect.width, closeTo(window.width, 1.5));
      expect(rect.height, closeTo(window.height, 1.5));

      // 脸必须落在窗口里（这才是功能本身的意义）。
      final face = faces.first;
      expect(rect.contains(face.center), isTrue,
          reason: 'face center ${face.center} not in $rect');
    }
  });
}