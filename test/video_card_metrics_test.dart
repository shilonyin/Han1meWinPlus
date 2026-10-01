import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/shared/video_card.dart';

void main() {
  group('视频卡片高度', () {
    // 详情区的实际内容：标题两行(40) + 间隙(2) + 作者(16) + 间隙(2) + 评分行(16) ≈ 76。
    // 预留高度必须贴近它，否则卡片底部会空出一块，加上投影就显得"下面还有一层"。
    const contentHeight = 76.0;

    test('横向卡片：详情区预留高度贴近实际内容，不留大片空白', () {
      final metrics = videoCardMetrics(
        viewportWidth: 1200,
        horizontal: true,
        cardsPerRow: 5,
        expanded: true,
      );
      final details = metrics.cardHeight - metrics.cardWidth * 9 / 16;
      expect(details, greaterThanOrEqualTo(contentHeight));
      // 余量控制在 12px 以内：够兜住字体度量误差，又不会空出一大块。
      expect(details, lessThanOrEqualTo(contentHeight + 12));
    });

    test('非 expanded（侧栏尺寸）同样不留大片空白', () {
      final metrics = videoCardMetrics(
        viewportWidth: 500,
        horizontal: true,
        cardsPerRow: 1,
        expanded: false,
      );
      final details = metrics.cardHeight - metrics.cardWidth * 9 / 16;
      expect(details, lessThanOrEqualTo(contentHeight + 12));
    });

    test('封面严格保持 16:9（不能为了消灭空白把封面拉变形）', () {
      final metrics = videoCardMetrics(
        viewportWidth: 1200,
        horizontal: true,
        cardsPerRow: 5,
        expanded: true,
      );
      final cover = metrics.cardWidth * 9 / 16;
      expect(
        metrics.cardHeight,
        closeTo(cover + (metrics.cardHeight - cover), 0.001),
      );
      // 卡片总高必须大于封面 + 内容，否则文字会被裁掉。
      expect(metrics.cardHeight, greaterThan(cover + contentHeight - 1));
    });

    test('独立详情页（非横向）不受本次改动影响', () {
      final metrics = videoCardMetrics(
        viewportWidth: 1200,
        horizontal: false,
        cardsPerRow: 5,
        expanded: true,
      );
      // 竖版卡片高度按 0.58 宽高比算，与详情区常量无关。
      expect(metrics.cardHeight, closeTo(metrics.cardWidth / .58, 0.001));
    });
  });
}
