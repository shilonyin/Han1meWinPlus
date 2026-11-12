import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import 'settings_controller.dart';
import 'keyframes_page.dart';
import 'player_settings_page.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends ConsumerState<PlaybackSettingsPage> {
  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）：
  /// push 会把左侧分类栏整个盖住，退出后还得重新点一次分类才能回来。
  String? _subPage;

  @override
  Widget build(BuildContext context) {
    if (_subPage == 'player') {
      return SettingsSubPageScope(
        onBack: () => setState(() => _subPage = null),
        child: const PlayerSettingsPage(),
      );
    }
    if (_subPage == 'keyframes') {
      return SettingsSubPageScope(
        onBack: () => setState(() => _subPage = null),
        child: const KeyframesPage(),
      );
    }
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: M3EContainedLoadingIndicator()),
      );
    }
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.playbackSettings)),
      body: SettingsSubPageBody(child: ListView(
        children: [
          // 设计稿（`pb1.png` / `pb2.png`）：**两张卡**，第一张没有标题（9 项），
          // 第二张标题是「窗口」（3 项），最底下一行灰字注释。
          //
          // 关键是**每一行都不带副标题**：设计稿的行里只有「标题 + 右侧值」
          // （`默认清晰度  1080P >`、`自动连播下一集  [开关]`），一行到底。
          // 我们的实现给几乎每个条目都塞了 `subtitle`（"Player、画质与记忆进度"
          // 这种说明），每行被撑成两行 —— 9 项就多出三百多像素，
          // 一屏只能看到原来的一半，整页看起来比设计稿松一倍。
          // 那些说明文字设计稿放在**页面最底下的注释行**，不是每行都写。
          SettingsCardList(
            // 播放页设计稿每行 **44**（分隔线 166/210/254…），比主题页的 40 松 4。
            rowPadding: 3,
            children: [
              SettingsCardItem(
                title: l10n.playerSettings,
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _subPage = 'player'),
              ),
              SettingsMenuItem(
                title: l10n.preferredQuality,
                value: settings.preferredQuality,
                options: const [480, 720, 1080],
                label: (value) => '${value}p',
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(preferredQuality: value),
                ),
              ),
              SettingsCardItem(
                title: l10n.resumePlayback,
                trailing: Switch(
                  value: settings.resumePlayback,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(resumePlayback: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.autoPlayOnOpen,
                trailing: Switch(
                  value: settings.autoPlayOnOpen,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(autoPlayOnOpen: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.incognitoPlayback,
                trailing: Switch(
                  value: settings.incognitoPlayback,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(incognitoPlayback: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.autoPlayNext,
                trailing: Switch(
                  value: settings.autoPlayNext,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(autoPlayNext: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.loopPlayback,
                trailing: Switch(
                  value: settings.loopPlayback,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(loopPlayback: value),
                  ),
                ),
              ),
              SettingsMenuItem(
                title: l10n.defaultPlaybackSpeed,
                value: settings.defaultPlaybackSpeed,
                options: const [.5, .75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0],
                label: (value) =>
                    '${value.toStringAsFixed(value == value.roundToDouble() ? 1 : 2)}×',
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(defaultPlaybackSpeed: value),
                ),
              ),
              SettingsMenuItem(
                title: l10n.longPressPlaybackSpeed,
                value: settings.longPressPlaybackSpeed,
                options: const [1.0, 1.5, 2.0, 2.5, 3.0],
                label: (value) =>
                    '${value.toStringAsFixed(value == value.roundToDouble() ? 1 : 2)}×',
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(longPressPlaybackSpeed: value),
                ),
              ),
              SettingsMenuItem(
                title: l10n.seekSensitivity,
                value: settings.seekSensitivity,
                options: const [.1, .2, .3, .4, .5, .6, .7, .8, .9, 1.0],
                label: (value) =>
                    l10n.seekSensitivityValue((value * 100).round()),
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(seekSensitivity: value),
                ),
              ),
              SettingsCardItem(
                title: l10n.keyframesEnabled,
                trailing: Switch(
                  value: settings.keyframesEnabled,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(keyframesEnabled: value),
                  ),
                ),
              ),
            ],
          ),
          SettingsCardList(
            title: '窗口',
            rowPadding: 3,
            children: [
              // 设计稿第二张卡是「窗口」组，右侧显示「已开启 / 关闭 >」而不是开关。
              // 这里用现有的 `openVideoInWindow`（独立播放窗口）——
              // 设计稿里的三项（只允许一个窗口 / 默认置顶 / 关闭时保留位置）
              // 在设置模型里还没有对应字段，先把这一组落到现在真实存在的那一项上，
              // 不凭空造开关（那会让用户在界面上看到一个点了没用的项）。
              SettingsMenuItem(
                title: l10n.openVideoInWindow,
                value: settings.openVideoInWindow,
                options: const [true, false],
                label: (value) => value ? '已开启' : '关闭',
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(openVideoInWindow: value),
                ),
              ),
              SettingsMenuItem(
                title: l10n.playerControlsTimeout,
                value: settings.playerControlsTimeoutSeconds,
                options: const [2, 3, 4, 5, 6, 8, 10, 15],
                label: (value) => l10n.seconds(value),
                onSelected: (value) => controller.saveChanges(
                  (current) =>
                      current.copyWith(playerControlsTimeoutSeconds: value),
                ),
              ),
            ],
          ),
          // 页脚注释（设计稿最底下一行 11 号灰字）。
          Padding(
            padding: const EdgeInsets.fromLTRB(39, 4, 29, 24),
            child: Text(
              '「独立播放窗口」开启后，视频会在单独的窗口里播放，关闭主窗口不会中断。',
              style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMutedOf(context)),
            ),
          ),
        ],
      )),
    );
  }
}
