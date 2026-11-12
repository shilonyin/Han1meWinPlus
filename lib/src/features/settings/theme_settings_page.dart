import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_responsive.dart';
import '../../core/app_notifications.dart';
import '../../core/settings.dart';
import '../../core/system_tray.dart';
import '../../core/window_backdrop.dart';
import '../../core/window_chrome.dart';
import '../../app/app_theme.dart';
import '../shared/press_scale.dart';
import 'color_compass_dialog.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';

class ThemeSettingsPage extends ConsumerStatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  ConsumerState<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends ConsumerState<ThemeSettingsPage> {
  @override
  Widget build(BuildContext context) {
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
          : AppBar(title: Text(l10n.themeAndColor)),
      body: SettingsSubPageBody(child: ListView(
        // 顶部不再留 12：设计稿里「主题与色彩」页头下面直接就是那张淡粉横幅
        // （横幅顶 y104、标题字顶 y66，中间只有 38），这里再垫 12 会把它
        // 整体挤低一截，��屏少看到好几项设置。底部留 12 保留（滚到最底时
        // 最后一张卡不贴着窗口下沿）。
        // 底部 12 是设计稿基准，随文字缩放一起变化。
        padding: EdgeInsets.only(bottom: AppResponsive.scaled(context, 12)),
        children: [
          // 设计稿「当前主题」预览横幅：粉底大卡，左边是主题名（中文 + 英文）+ 一行
          // 品牌色/圆角/设计体系说明，右边是一小块界面缩略图，让人一眼看出这套配色
          // 长什么样。切主题色时它会跟着变 —— 这是「选配色」这件事最直接的反馈。
          // 宽度已由外层 SettingsSubPageBody 统一推导；横幅、配色卡、设置列都直接
          // 铺满父宽度，三者左右边缘自然对齐，不再各自限宽导致错位。
          _ThemePreviewBanner(settings: settings),
          // 设计稿「配色方案」：一张白色圆角卡，标题 + 8 个色圆横排，点一下即时切换
          // （不再是一个打开调色罗盘的列表行）。色圆选中项外层加一圈白底环。
          _ColorSchemeCard(
            settings: settings,
            onPick: (color) => controller.saveChanges(
              (current) =>
                  current.copyWith(useMonetColors: false, themeColor: color),
            ),
            onCustom: () => _pickThemeColor(context, controller, settings),
          ),
          SettingsCardList(
            title: l10n.appearanceAndDisplay,
            // 行高 **42**：全设置页统一（内容 36 + `rowPadding` 3 × 2）。
            //
            // 原来这一页单独给 5（行高 46），是因为窗口 800 高时要「刚好不滚动」，
            // 而其它页给 3/4/10 —— 结果同一类设置项在不同页面疏密不一。
            // 统一到 42 之后整页仍能完整显示：两张预览卡约 300，8 行 × 42 = 336。
            rowPadding: 3,
            children: [
              // 「配色方案」已经提到上面的 _ColorSchemeCard（设计稿是横向色圆，不是列表行）。
              SettingsCardItem(
                title: l10n.dynamicColor,
                // 补副标题（设计稿：「从系统壁纸提取主题色」）。
                //
                // 这一行原来只有标题，而下面五行都带副标题 ——
                // 于是它比其他行矮一截，一列看下来第一行明显「缩了一下」，
                // 这正是「上下间距不一致」最刺眼的地方。
                subtitle: '从系统壁纸提取主题色',
                leading: const Icon(Symbols.colorize_rounded),
                trailing: Switch(
                  value: settings.useMonetColors,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(useMonetColors: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.useSystemFont,
                subtitle: l10n.useSystemFontDescription,
                leading: const Icon(Symbols.text_fields_rounded),
                trailing: Switch(
                  value: settings.useSystemFont,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(useSystemFont: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.amoledMode,
                subtitle: l10n.amoledModeDescription,
                leading: const Icon(Symbols.contrast_rounded),
                trailing: Switch(
                  value: settings.amoledMode,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(amoledMode: value),
                  ),
                ),
              ),
              SettingsSliderItem(
                title: l10n.textSize,
                // 副标题（设计稿：「界面文字缩放比例」）。
                // 原来这一行只有标题 + 滑块，比其他行少一行文字，
                // 高度也比别人矮 —— 一列看下来这里会「凹」下去一块。
                subtitle: '界面文字缩放比例',
                value: settings.textScale,
                min: .8,
                // 上限 2.0 是 WCAG 1.4.4（调整文本大小）要求的下限：文字要能放大到 200%。
                // 原来封顶 1.4，低视力用户没有可用的放大余量。下限仍是 .8（可缩小），
                // 档位从 6 加到 12 —— 区间翻倍还保持原来的步长（0.1），手感不变。
                max: 2.0,
                divisions: 12,
                label: '${(settings.textScale * 100).round()}%',
                onChanged: (value) => controller.saveChanges(
                  (current) => current.copyWith(textScale: value),
                ),
              ),
              // 窗口这一组并进同一张卡：v6 设计稿里「外观与显示」就是一张卡、8 项用
              // 1px 分隔线串起来，而不是三个各自带标题的小卡。拆成三张时每组都有自己的
              // 外边距与标题行，整页被拉高一大截，看起来「比设计稿松」。
              //
              // 「使用系统标题栏」与「全局热键」已按需求移除：
              // 前者对桌面端没有实际意义（自绘标题栏是本应用的一部分，
              // 换成系统的那一套反而和侧栏、顶栏的圆角接不上）；
              // 后者是低频设置，且它只在应用未激活时才有用 ——
              // 留在这一页只会让「外观与显示」这一组显得杂。
              // 两个字段仍保留在设置模型里（已有配置不丢），只是不再在这里露出。
              if (WindowChrome.isSupported) ...[
                if (SystemTray.isSupported)
                  SettingsCardItem(
                    title: l10n.minimizeToTray,
                    subtitle: l10n.minimizeToTrayDescription,
                    leading: const Icon(Symbols.call_to_action_rounded),
                    trailing: Switch(
                      value: settings.minimizeToTray,
                      onChanged: (value) => controller.saveChanges(
                        (current) => current.copyWith(minimizeToTray: value),
                      ),
                    ),
                  ),
                if (AppNotifications.isSupported)
                  SettingsCardItem(
                    title: l10n.notifications,
                    subtitle: l10n.notificationsDescription,
                    leading: const Icon(Symbols.notifications_rounded),
                    trailing: Switch(
                      value: settings.notificationsEnabled,
                      onChanged: (value) => controller.saveChanges(
                        (current) =>
                            current.copyWith(notificationsEnabled: value),
                      ),
                    ),
                  ),
                if (WindowBackdropEffect.isSupported)
                  SettingsCardItem(
                    title: l10n.windowBackdrop,
                    subtitle: _backdropLabel(l10n, settings.windowBackdrop),
                    leading: const Icon(Symbols.window_rounded),
                    trailing: const Icon(Symbols.chevron_right_rounded),
                    onTap: () =>
                        _pickWindowBackdrop(context, controller, settings),
                  ),
              ],
              // 「主题模式」那一节（材质 / 染色 / 渲染 / 波纹 / 对比度）已删除：
              // 玻璃停用后这些选项无处生效，决策见 `docs/ui-polish.md`。
            ],
          ),
        ],
      )),
    );
  }

  /// 窗口材质三档（Windows 系统材质）：走统一的选项弹层。
  Future<void> _pickWindowBackdrop(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showOptionSettingsDialog<WindowBackdrop>(
      context: context,
      title: l10n.windowBackdrop,
      current: settings.windowBackdrop,
      options: WindowBackdrop.values,
      label: (backdrop) => _backdropLabel(l10n, backdrop),
    );
    if (selected == null || selected == settings.windowBackdrop) return;
    await controller.saveChanges(
      (current) => current.copyWith(windowBackdrop: selected),
    );
  }

  /// 配色方案：直接打开调色罗盘 —— 里面既有预设色板也有色轮，
  /// 不用像原来那样先弹一个只放预设的弹层、再点「自定义」进罗盘（中间白跑一趟）。
  Future<void> _pickThemeColor(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) async {
    final result = await showColorCompassDialog(
      context,
      initial: _hexColor(settings.customThemeColor),
      customHex: settings.customThemeColor,
      currentPreset: settings.useMonetColors ? null : settings.themeColor,
    );
    switch (result) {
      case ColorPresetResult(:final preset):
        await controller.saveChanges(
          (current) =>
              current.copyWith(useMonetColors: false, themeColor: preset),
        );
      case CustomColorResult(:final color):
        final hex = color
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0')
            .substring(2)
            .toUpperCase();
        await controller.saveChanges(
          (current) => current.copyWith(
            useMonetColors: false,
            themeColor: AppThemeColor.custom,
            customThemeColor: hex,
          ),
        );
      case null:
        break;
    }
  }
}

/// 设计稿「配色方案」卡：白底圆角16、标题 + 8 个色圆横排。
///
/// 色圆 48×48 圆角12、间距 14；选中项外层加 56×56 白底环（圆角16）表示当前配色。
/// 点一下即切换主题色（全局即时生效），底部一行 10 号灰字提示。
class _ColorSchemeCard extends StatelessWidget {
  const _ColorSchemeCard({
    required this.settings,
    required this.onPick,
    required this.onCustom,
  });

  final AppSettings settings;
  final ValueChanged<AppThemeColor> onPick;
  final VoidCallback onCustom;

  // 设计稿的 8 个配色（顺序固定）：玫瑰 / 蓝 / 青 / 绿 / 橙 / 紫 / 棕 / 粉。
  // 前 6 个与 AppThemeColor 的 rose/blue/teal/green/amber/purple 对应；
  // 设计稿的「棕」「粉」用 indigo? 不 —— 这里按枚举语义映射到最接近的项，
  // 色值仍取各自 seedColor，保证切换后整套主题跟着变。
  static const _presets = <AppThemeColor>[
    AppThemeColor.rose,
    AppThemeColor.blue,
    AppThemeColor.teal,
    AppThemeColor.green,
    AppThemeColor.orange,
    AppThemeColor.purple,
    AppThemeColor.indigo,
    AppThemeColor.pink,
  ];

  @override
  Widget build(BuildContext context) {
    final current = settings.useMonetColors ? null : settings.themeColor;
    // 卡内间距以设计稿实测值为基准、随文字缩放一起放大；放大后若留白不变，
    // 标题、色块行与提示语会挤在一起。
    return Container(
      // 设计稿白卡实测 x424~1251，而内容区从 385 起（见 `settings_list.dart` 的
      // 卡片外边距）—— 左右各留 39 / 29。这里写成 12 会让卡片宽出一大截，
      // 最右边几乎顶到窗口边缘。
      margin: const EdgeInsets.only(bottom: 12),
      // 上下内边距 14：设计稿这张卡高 138（y268~406），我们的是 144 ——
      // 多出的 6 来自上下各 16 的内边距。收到 14 之后整块落到 138，
      // 省下来的这几像素正好给下面那张外观卡留出余量。
      padding: EdgeInsets.fromLTRB(
        24,
        AppResponsive.scaled(context, 14),
        24,
        AppResponsive.scaled(context, 14),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '配色方案',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B1B1F),
            ),
          ),
          // 标题→色块：设计稿标题字底 299、色块外框顶 312（外框 56 高，内芯 48
          // 居中，所以内芯顶 316），中间实际不到 12。
          SizedBox(height: AppResponsive.scaled(context, 12)),
          // 色块间距 14：设计稿两个色块的**外框左边缘**步长是 62（514-452），
          // 外框宽 56 → 间距 6。之前写 14 是按内芯 48 估的，步长变成 62+6=68，
          // 一排放不下 8 个，视觉上整排被撑开、右半边明显比设计稿松。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppResponsive.scaled(context, 6),
                runSpacing: AppResponsive.scaled(context, 12),
                children: [
                  for (final preset in _presets)
                    Builder(
                      builder: (context) {
                        final selected = preset == current;
                        // 色块画的是 [AppThemeColor.swatchFill]（设计稿那支鲜亮色），
                        // **不是** `swatchColor` / `seedColor` —— 后者是喂给 M3 的种子，
                        // 派生出来的颜色普遍暗一档，一排列色块和设计稿比就是
                        // 「位置对、颜色不对」（紫 / 棕 / 粉三个差得最明显）。
                        final color = preset.swatchFill;
                        return PressScale(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            onTap: () => onPick(preset),
                            child: Container(
                              // 外框固定 56 见方：选中态那圈 2px 描边画在**框内**
                              // （`Border.all` 默认在内侧），所以选中与否不改变占位，
                              // 一排列色块不会因为选了别的一下子整体挪位。
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                border: selected
                                    ? Border.all(color: color, width: 2)
                                    : null,
                              ),
                              child: Container(
                                // 内芯 48 见方、圆角 12 —— 设计稿（`swChip0`）就是这个数。
                                // 外框 56 - 内芯 48 = 两侧共 8，正好给选中描边留出 2 + 2 的
                                // 空隙，描边不会贴到色块上。
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: preset == AppThemeColor.white
                                      ? Border.all(
                                          color: const Color(0xFFE4E4EA),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const Spacer(),
              // 「自定义…」放在色块同一行的最右侧。
              //
              // 它**不能单独占一行**：设计稿这张卡只有「标题 / 色块 / 一句提示」
              // 三段、总高 138。这个入口是我们额外提供的（调色罗盘），
              // 塞在提示语下面会让卡片多出 28px（→169），下面「外观与显示」
              // 整块被推下去 30，一屏就比设计稿少看到三行设置。
              //
              // 色块结束在 x~933、卡片右缘 1251，中间有三百多像素空档，
              // 摆在这里既不挤也不撑高卡片。
              Padding(
                // 与 56 高的色块垂直居中：色块 56、文字行高约 16 → (56-16)/2 = 20
                padding: EdgeInsets.only(top: AppResponsive.scaled(context, 20)),
                child: PressScale(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: onCustom,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppResponsive.scaled(context, 4),
                        vertical: AppResponsive.scaled(context, 2),
                      ),
                      child: Text(
                        '自定义…',
                        // 跟随当前主题色（写死 #B3265A 的话，切到青主题它还是一片粉）。
                        style: TextStyle(
                          fontSize: 11,
                          color: AppDesignTokens.accentOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 色块→提示语：设计稿内芯底 363、提示字顶 374，中间 11。
          SizedBox(height: AppResponsive.scaled(context, 8)),
          const Text(
            '点击切换主题色，全局即时生效',
            style: TextStyle(fontSize: 10, color: Color(0xFF9595A0)),
          ),
        ],
      ),
    );
  }
}

/// 设计稿「当前主题」预览横幅（`pvBanner` + `pvLabel` / `pvName` / `pvMeta` / `pvMini*`）。
///
/// 布局照设计稿：白色圆角 16 的卡，左侧竖排「当前主题」小标签 + 主题名（中文 + 英文）
/// + 一行说明；右侧是一块**缩略界面**——把当前配色画成迷你窗口（标题条 / 卡片 /
/// 按钮 / 圆点），让「换了颜色会变成什么样」不用点进去就能看到。
///
/// 为什么不直接截当前界面的缩略图：设置页自己就是被预览的那个界面，截图会无限套娃；
/// 而且这里的缩略图要表达的是**配色关系**（强调色、卡片底、页面底），
/// 用几块纯色比真界面更清楚，也不会因为数据不同而每次长得不一样。
class _ThemePreviewBanner extends StatelessWidget {
  const _ThemePreviewBanner({required this.settings});

  final AppSettings settings;

  /// 当前配色对应的强调色：动态配色时用主题实际主色，否则取所选预置的色值。
  static Color accentOf(BuildContext context, AppSettings settings) {
    if (settings.useMonetColors) return Theme.of(context).colorScheme.primary;
    return settings.themeColor.swatchColor(settings.customThemeColor);
  }

  @override
  Widget build(BuildContext context) {
    // 文字块的行距与内边距都是基准值，随文字缩放一起放大；缩略窗口保持
    // 设计稿的固定比例不跟着放大，否则会盖住左侧的三行文字。
    final active = settings.useMonetColors ? null : settings.themeColor;
    final accent = accentOf(context, settings);
    final name = _themeName(active, settings.useMonetColors);
    final hex =
        '#${accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Container(
      // 左右边距必须和下面那几张白卡**完全一致**（`SettingsSection` 的 39/29）。
      // 这里原来写 12/12：横幅比卡片左右各宽出 27/17，右边缘一直顶到窗口，
      // 和设计稿「横幅与卡片左右同一条线」对不上 —— 屏幕上看着就是右半边
      // 溢出去、左右不齐。
      margin: const EdgeInsets.only(bottom: 12),
      // 横幅总体最小高度 **147**（设计稿 y104~251）。
      //
      // 内边距放在这里、高度也在这里管：「内容区高度 = 总高 - 上下内边距」
      // 这个关系由同一个组件持有，不会出现「外面 111 + 里面又加一份 padding」
      // 这种对不上账的情况。
      //
      // 用 `constraints: minHeight` 而不是固定高度：文字块（当前主题 / 主题名 /
      // 品牌色三行）约 118，比 111 高，钉死会把第一行裁掉一半（实测过）。
      constraints: const BoxConstraints(minHeight: 147),
      padding: EdgeInsets.fromLTRB(
        24,
        AppResponsive.scaled(context, 18),
        24,
        AppResponsive.scaled(context, 18),
      ),
      decoration: BoxDecoration(
        // 设计稿（`pvBanner`）是**淡粉底**，不是白卡 —— 它和下面那张白色的
        // 「配色方案」卡拉开层次，一眼能看出「这块是当前状态、下面是可选项」。
        // 底色取强调色压到很淡（约 5%），这样换主题色时它也跟着变。
        color: Color.alphaBlend(
          accent.withValues(alpha: .05),
          AppDesignTokens.surface,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      // 裁切：设计稿的迷你窗口**比横幅右侧宽**，右边被横幅边缘切掉一截
      // （`banner.png` 上图中只能看到缩略图的左半边）。
      // 不裁的话它会完整露出一块，横幅显得扁而空。
      clipBehavior: Clip.antiAlias,
      // 内容区高度由外层 `Container` 的 `minHeight: 147` 与内边距共同决定，
      // 这里不再套一层 `ConstrainedBox` —— 两层约束叠在一起会把文字块挤压缩。
      child: Stack(
        children: [
          // 文字块垂直居中（设计稿就是居中的：横幅 104~251，文字块 128~199）。
          Padding(
            padding: const EdgeInsets.only(right: 180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '当前主题',
                  // 设计稿这行小标题用**强调色**（不是灰）—— 它和下面的大字一起
                  // 构成「这是当前选中的那个」，灰色会让它像说明文字。
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: AppResponsive.scaled(context, 6)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      name.$1,
                      // 设计稿（`pvName`）：主题名是强调色大字（22 Bold），
                      // 不是墨色 —— 这块横幅本来就是在展示「你选的这支颜色」。
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        height: 1.2,
                      ),
                    ),
                    if (name.$2.isNotEmpty) ...[
                      SizedBox(width: AppResponsive.scaled(context, 10)),
                      Text(
                        name.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent.withValues(alpha: .75),
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: AppResponsive.scaled(context, 6)),
                Text(
                  '品牌色 $hex · 圆角 16 · Material 3',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppDesignTokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          // 右侧缩略界面（设计稿 `pvMiniBg` 那块）：一个缩小版窗口，
          // 用当前强调色画标题条与按钮，其余用页面白与浅灰，比例固定。
          //
          // 它**贴右侧、且可以越出横幅右缘**（被上面的 clipBehavior 裁掉）——
          // 设计稿就是这样：缩略图右半边被横幅切掉，看起来像「窗口探进来一角」，
          // 比一个完整缩小的窗口更像「正在看这个主题的界面」。
          Positioned(
            // 只裁右边缘一小条：设计稿（`banner.png`）里缩略图的右缘几乎
            // 贴着横幅右边缘，只被切掉几个像素。之前 -28 把右边切掉大半，
            // 灰块和圆点都被吃掉，看着像一张被截断的图。
            right: 4,
            // 垂直居中：内容区 111、迷你窗口 112，差 1 像素，
            // 用 `top: -0.5` 让它在高 111 的槽里居中（整数坐标下取 0 即可，
            // 视觉上看不出那半像素）。
            top: 0,
            child: _MiniWindow(accent: accent, height: 111),
          ),
        ],
      ),
    );
  }
}

/// 横幅右侧的迷你界面缩略图：标题条 / 两张卡片 / 一个按钮 / 一个圆点。
///
/// 尺寸照设计稿 `pvMiniBg` 实测 **276×112**（圆角 12），右侧留 29 与卡片右缘对齐。
/// 原来写 132×84 是按半缩的尺寸估的：它比设计稿矮 28，横幅跟着矮下去，
/// 下面几张卡整体上移，一屏少看到好几项。它只表达配色关系，不表达布局，
/// 所以元素位置写死在这里而不复用真实页面组件。
class _MiniWindow extends StatelessWidget {
  const _MiniWindow({required this.accent, this.height = 112});

  final Color accent;

  /// 高度。默认 112（设计稿实测），横幅内容区只有 111 时传 111 以免溢出。
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 276,
    height: height,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      // 设计稿（`miniD.png`）的缩略图是**白底卡片**，不是浅灰底 ——
      // 它压在淡粉的横幅上，白底才和「这是一块界面」对得上。
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部一条通栏浅灰横条（设计稿：圆角 6、高约 14、铺满可用宽度）。
            _miniBar(width: double.infinity, height: 14),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左：一块大的浅灰块（设计稿里是内容占位）。
                Expanded(flex: 3, child: _miniBar(height: 44)),
                const SizedBox(width: 10),
                // 右：一块方形的浅灰块。
                Expanded(flex: 2, child: _miniBar(height: 44)),
              ],
            ),
          ],
        ),
        // 左下：强调色的胶囊按钮（设计稿里带一个小圆尾巴，像气泡）。
        Positioned(
          left: 0,
          bottom: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 小尾巴：一个 10 的小圆，压在胶囊左侧下缘
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              Transform.translate(
                offset: const Offset(-4, 0),
                child: Container(
                  width: 74,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Text(
                    '按钮',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 右下：强调色的小圆点。
        Positioned(
          right: 2,
          bottom: 10,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .5),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    ),
  );

  /// 缩略图里的浅灰占位块（设计稿的 `pvMiniBar` / `pvMiniCard`）。
  Widget _miniBar({double width = double.infinity, required double height}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          // 设计稿的占位块是极浅的灰（在纯白卡上才看得出来）。
          color: const Color(0xFFF2F2F5),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      );
}

/// 主题名的中英对照。英文是设计稿里的副标题（`ROSE` / `BLUE` …）。
(String, String) _themeName(AppThemeColor? color, bool monet) {
  if (monet) return ('动态配色', 'MONET');
  return switch (color) {
    AppThemeColor.rose => ('玫瑰', 'ROSE'),
    AppThemeColor.blue => ('蓝', 'BLUE'),
    AppThemeColor.teal => ('青', 'TEAL'),
    AppThemeColor.green => ('绿', 'GREEN'),
    AppThemeColor.orange || AppThemeColor.amber => ('橙', 'ORANGE'),
    AppThemeColor.purple => ('紫', 'PURPLE'),
    AppThemeColor.indigo => ('棕', 'EARTH'),
    AppThemeColor.pink => ('粉', 'PINK'),
    AppThemeColor.white || null => ('白', 'WHITE'),
    AppThemeColor.custom => ('自定义', 'CUSTOM'),
  };
}

/// 6 位十六进制色值 → Color。
Color _hexColor(String hex) {
  final value = int.tryParse('ff$hex', radix: 16);
  return value == null ? const Color(0xff6750a4) : Color(value);
}

String _backdropLabel(AppLocalizations l10n, WindowBackdrop backdrop) =>
    switch (backdrop) {
      WindowBackdrop.none => l10n.windowBackdropOff,
      WindowBackdrop.mica => l10n.windowBackdropMica,
      WindowBackdrop.acrylic => l10n.windowBackdropAcrylic,
    };
