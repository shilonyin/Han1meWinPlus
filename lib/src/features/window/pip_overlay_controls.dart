import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/play_window_title_target.dart';
import '../../core/playback_hotkey_target.dart';
import '../../../l10n/app_localizations.dart';

/// 画中画小窗中央那组大圆按钮：上一集 / 播放暂停 / 下一集。
///
/// 照 b 站小窗来（参考截图逐像素量过）：三个半透明黑圆浮在画面上、图标纯白。
/// 小窗里原来只有底部那一行 48px 小图标，缩到 380px 宽后既挤又难点；把主操作
/// 放大到中央更顺手，这也是参考实现的做法。
///
/// 注意：这里**不能用 Tooltip**。本组件挂在 [AppWindowFrame] 的浮层里，而那一层
/// 位于 MaterialApp.builder（Navigator 之外），没有 Overlay 祖先——Tooltip 会在
/// 第一次悬停时抛「No Overlay widget found」，把整块浮层换成灰色错误框。
/// 无障碍标签走 Semantics。[_BarButton] 里踩过同一个坑。
class PipOverlayControls extends StatelessWidget {
  const PipOverlayControls({super.key});

  /// 圆的直径。
  ///
  /// 参考实现（450 宽的小窗）量出来约 72 物理像素，折算到我们的 380 宽约 61，
  /// 取 62；再小就不好点了。
  static const double diameter = 62;

  /// 圆之间的间距。参考实现约 105-72=33 物理像素，折算后取 28。
  static const double gap = 28;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: PlayWindowTitleTarget.hasPrevious,
          builder: (context, enabled, _) => PipCircleButton(
            label: l10n.hotkeyActionPreviousEpisode,
            icon: Symbols.skip_previous_rounded,
            onPressed: enabled ? PlayWindowTitleTarget.previousEpisode : null,
          ),
        ),
        const SizedBox(width: gap),
        // 播放 / 暂停的图标跟着实际播放状态走（状态由播放页同步到 PlaybackHotkeyTarget）。
        ValueListenableBuilder<bool>(
          valueListenable: PlaybackHotkeyTarget.isPlaying,
          builder: (context, playing, _) => PipCircleButton(
            label: playing ? l10n.pause : l10n.play,
            icon: playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
            onPressed: () => PlaybackHotkeyTarget.togglePlay?.call(),
          ),
        ),
        const SizedBox(width: gap),
        ValueListenableBuilder<bool>(
          valueListenable: PlayWindowTitleTarget.hasNext,
          builder: (context, enabled, _) => PipCircleButton(
            label: l10n.hotkeyActionNextEpisode,
            icon: Symbols.skip_next_rounded,
            onPressed: enabled ? PlayWindowTitleTarget.nextEpisode : null,
          ),
        ),
      ],
    );
  }
}

/// 单个半透明圆按钮。
///
/// 配色取自参考实现：黑色 28% 不透明度叠在画面上（实测 254→183、202→145，
/// 两处都吻合 0.72 的透光率），图标纯白——深浅画面里都能看清。
class PipCircleButton extends StatelessWidget {
  const PipCircleButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;

  /// 为 null 表示不可用（比如没有上一集），圆变淡且不响应点击。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.black.withValues(alpha: enabled ? 0.28 : 0.16),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: PipOverlayControls.diameter,
            height: PipOverlayControls.diameter,
            child: Icon(
              icon,
              size: 30,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}
