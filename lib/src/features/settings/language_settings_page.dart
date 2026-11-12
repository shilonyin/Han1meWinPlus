import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/press_scale.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/settings.dart';
import 'settings_controller.dart';
import 'settings_pane_scope.dart';
import 'settings_sub_page.dart';

/// 语言设置页。
///
/// 视觉对齐 v6 设计稿（`s_lang.png`）：
/// - 页头「语言」19–20 Bold + 右侧说明文字；
/// - 每个语言项是**独立白卡**（圆角 16、stroke 描边），不是整组一张卡；
/// - 选中项用 accentDeep 描边 + 实心勾，未选中项描边用 stroke；
/// - 每项两行：主标题（ink）+ 副标题（inkSubtle 单档小灰）；
/// - 底部一行提示文字。
///
/// 这里没有套 `SettingsCardList`：它承载的是「整组一张卡 + 行间分隔线」的形态，
/// 而设计稿这一页是「一项一张独立浮卡」，两者不是一套皮肤，所以本页自绘卡片。
/// 语言切换逻辑/持久化/路由完全沿用原实现，只改视觉。
class LanguageSettingsPage extends ConsumerWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current =
        ref.watch(settingsProvider).valueOrNull?.language ?? AppLanguage.system;

    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.languageSettings)),
      body: SettingsSubPageBody(child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // 宽度已由外层 SettingsSubPageBody 统一推导，这里不再套 Center + 1000，
          // 否则两层各限一次，宽窗口下卡片比横幅窄一截、左右不齐。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                    // 分栏模式下页头由 `_SettingsPanes` 统一画（标题 + 副标题），
                    // 这里再画一次会重复成「语言 / 界面与内容的显示语言」两行。
                    if (!embeddedInSettingsPanes(context))
                      _PageHeader(
                        title: l10n.languageSettings,
                        subtitle: '界面与内容的显示语言',
                      ),
                    if (!embeddedInSettingsPanes(context))
                      const SizedBox(height: 16),
                    _LanguageOptionCard(
                      title: l10n.systemDefault,
                      subtitle: l10n.followSystem,
                      selected: current == AppLanguage.system,
                      onTap: () => _select(ref, AppLanguage.system),
                    ),
                    const SizedBox(height: 12),
                    _LanguageOptionCard(
                      title: l10n.simplifiedChinese,
                      subtitle: 'Simplified Chinese',
                      selected: current == AppLanguage.simplifiedChinese,
                      onTap: () => _select(ref, AppLanguage.simplifiedChinese),
                    ),
                    const SizedBox(height: 12),
                    _LanguageOptionCard(
                      title: l10n.traditionalChinese,
                      subtitle: 'Traditional Chinese',
                      selected: current == AppLanguage.traditionalChinese,
                      onTap: () => _select(ref, AppLanguage.traditionalChinese),
                    ),
                    const SizedBox(height: 12),
                    _LanguageOptionCard(
                      title: l10n.english,
                      subtitle: '英语',
                      selected: current == AppLanguage.english,
                      onTap: () => _select(ref, AppLanguage.english),
                    ),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '切换后界面与内容语言将立即更新',
                        style: TextStyle(
                          color: AppDesignTokens.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  void _select(WidgetRef ref, AppLanguage next) {
    ref
        .read(settingsProvider.notifier)
        .saveChanges((settings) => settings.copyWith(language: next));
  }
}

/// 页头：19–20 Bold 主标题 + 右侧说明。
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppDesignTokens.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          subtitle,
          style: const TextStyle(color: AppDesignTokens.inkMuted, fontSize: 13),
        ),
      ],
    );
  }
}

/// 单个语言选项：独立白卡。选中项 accentDeep 描边 + 实心勾。
class _LanguageOptionCard extends StatelessWidget {
  const _LanguageOptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          hoverColor: AppDesignTokens.navSelectedWash,
          splashColor: Colors.transparent,
          highlightColor: AppDesignTokens.navSelectedWash,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: selected
                    ? AppDesignTokens.accentOf(context)
                    : AppDesignTokens.stroke,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppDesignTokens.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppDesignTokens.inkSubtle,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SelectionBadge(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧选择标记：选中为 accentDeep 实心圆+白勾，未选中为空心描边圆。
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppDesignTokens.stroke, width: 2),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 跟随主题色（见 `AppDesignTokens.accentOf` 的说明）。
        color: AppDesignTokens.accentOf(context),
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}
