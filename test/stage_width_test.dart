// 回归测试：播放页内容区宽度。
//
// 这个布局前后踩了两轮坑，本文件把最终的结论锁死：
//
//  第一轮：内容区有固定 1600 上限 + 居中。2560x1440 最大化时舞台宽被卡在 1600、
//  播放区仅 1263，16:9 画面只有约 710 高，被塞进 1440 高的舞台居中 ——
//  上下各约 365px 黑边、两侧各空 480px。用户拿 b 站对比后指出「最大化界面有问题」。
//
//  第二轮：把上限改成按屏幕动态放大后，**收起侧栏时仍居中留边**，于是视频两边
//  又多出一段黑边。用户：「视频本身就已经有黑边了还在这基础加一段」。
//
//  最终结论：**应用层不额外留任何黑边**，内容区始终铺满可用宽度。
//  画面比例不匹配时由播放器自己居中留黑 —— 那才是必要的那一层。
//  谁再把「居中 + 宽度上限」加回来，本文件应该变红。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/video/video_page_layout.dart';

void main() {
  group('内容区始终铺满：应用层不留额外黑边', () {
    test('各种宽度下都等于可用宽度（展开侧栏）', () {
      for (final w in [800.0, 1280.0, 1600.0, 1920.0, 2560.0, 3440.0]) {
        expect(
          stageWidthFor(availableWidth: w, sidebarCollapsed: false),
          w,
          reason: '宽 $w：展开侧栏时应铺满，不应留下黑边',
        );
      }
    });

    test('各种宽度下都等于可用宽度（收起侧栏）—— 这条是本轮修复的核心', () {
      for (final w in [800.0, 1280.0, 1600.0, 1920.0, 2560.0, 3440.0]) {
        expect(
          stageWidthFor(availableWidth: w, sidebarCollapsed: true),
          w,
          reason: '宽 $w：收起侧栏也必须铺满，否则视频两边会多出一段应用层黑边',
        );
      }
    });

    test('2560 最大化：收起侧栏时不再收窄（回归防护）', () {
      final closed = stageWidthFor(availableWidth: 2560, sidebarCollapsed: true);
      expect(
        closed,
        2560,
        reason: '收起侧栏若收窄到 2320，居中后两侧各留 120px 黑边 —— 正是用户报的双层黑边',
      );
    });

    test('展开与收起宽度一致（侧栏状态不再影响内容区宽度）', () {
      for (final w in [1280.0, 1920.0, 2560.0]) {
        final open = stageWidthFor(availableWidth: w, sidebarCollapsed: false);
        final closed = stageWidthFor(availableWidth: w, sidebarCollapsed: true);
        expect(open, closed, reason: '宽 $w：侧栏状态不应改变内容区宽度');
      }
    });

    test('极端超宽屏同样铺满，不受任何上限约束', () {
      expect(stageWidthFor(availableWidth: 5120, sidebarCollapsed: true), 5120);
      expect(stageWidthFor(availableWidth: 5120, sidebarCollapsed: false), 5120);
    });

    test('零与负宽度不抛异常', () {
      expect(stageWidthFor(availableWidth: 0, sidebarCollapsed: true), 0);
      expect(stageWidthFor(availableWidth: 0, sidebarCollapsed: false), 0);
      expect(stageWidthFor(availableWidth: -50, sidebarCollapsed: true), lessThanOrEqualTo(0));
    });
  });

  group('布局常量仍然合理', () {
    test('侧栏宽度上限保持在 b 站量级（不会被拉到很宽）', () {
      // 侧栏实际宽度 = (stageWidth * .26).clamp(kSidebarMinWidth, kSidebarWidth)，
      // 铺满后 stageWidth 变大，靠 clamp 的上限兜住，不会越拉越宽。
      expect(kSidebarWidth, lessThanOrEqualTo(400));
      expect(kSidebarMinWidth, lessThanOrEqualTo(kSidebarWidth));
    });
  });
}
