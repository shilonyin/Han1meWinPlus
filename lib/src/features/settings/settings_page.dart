import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_responsive.dart';
import '../../core/app_shell.dart';
import '../shared/press_scale.dart';
import 'about_page.dart';
import 'comment_settings_page.dart';
import 'hotkey_settings_page.dart';
import 'language_settings_page.dart';
import 'layout_settings_page.dart';
import 'log_settings_page.dart';
import 'network_settings_page.dart';
import 'playback_settings_page.dart';
import 'selection_settings_pages.dart';
import 'settings_list.dart';
import 'settings_pane_scope.dart';
import 'storage_settings_page.dart';
import 'theme_settings_page.dart';
import 'webdav_settings_page.dart';
import '../shared/app_top_bar.dart';

/// One entry in the settings navigation, used by both layouts.
class _SettingsEntry {
  const _SettingsEntry(
    this.icon,
    this.label,
    this.page,
    this.route, {
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget page;
  final String route;

  /// 页头标题行右侧的页面专属控件（例如日志页的「复制全部日志」按钮）。
  ///
  /// 分栏模式的标题行由 `_SettingsPanes` 统一画；子页自己再画一行按钮的话，
  /// 按钮会掉到标题下方、和标题不在同一行。把按钮交给外层页头即可对齐。
  final Widget? trailing;
}

/// 各设置分类的页头副标题：**与标题同一行、排在标题右侧**的灰字
/// （设计稿 `hdrs.png` 一排对比：「快捷键  应用内与全局快捷键」……）。
///
/// **「主题与色彩」和「关于」没有副标题** —— 设计稿里这两页只有一行标题，
/// 标题右边是空的。一开始我按「所有页都有副标题」统一处理，结果这两页
/// 各多出一截灰字，和设计稿一比就很显眼。这里按页取舍，不搞一刀切。
///
/// key 是路由的最后一段，与 `?pane=` 用的是同一套标识。
const _settingsSubtitles = <String, String>{
  'layout': '漫画模式、播放窗口与首页入口',
  'playback': '播放器与窗口行为',
  'hotkeys': '应用内与全局快捷键',
  'network': '代理、Hosts 与连接诊断',
  'webdav': '云同步与备份配置',
  'previews': '选择新番预告的数据来源',
  'comments': '评论区与过滤规则',
  'language': '界面与内容的显示语言',
  'storage': '下载、本地媒体与备份',
  'logs': '运行环境与调试信息',
};

/// Grouped only where the group adds meaning; order matches the reading order
/// of the old single-column list.
List<(String, List<_SettingsEntry>)> _settingsSections(AppLocalizations l10n) =>
    [
      (
        l10n.appearance,
        [
          _SettingsEntry(
            Symbols.palette_rounded,
            l10n.themeAndColor,
            const ThemeSettingsPage(),
            '/settings/theme',
          ),
          _SettingsEntry(
            Symbols.dashboard_customize_rounded,
            l10n.interfaceLayout,
            const LayoutSettingsPage(),
            '/settings/layout',
          ),
        ],
      ),
      (
        l10n.playback,
        [
          _SettingsEntry(
            Symbols.smart_display_rounded,
            l10n.playbackSettings,
            const PlaybackSettingsPage(),
            '/settings/playback',
          ),
          _SettingsEntry(
            Symbols.keyboard_rounded,
            l10n.settingsHotkeys,
            const HotkeySettingsPage(),
            '/settings/hotkeys',
          ),
        ],
      ),
      (
        l10n.network,
        [
          _SettingsEntry(
            Symbols.language_rounded,
            l10n.networkSettings,
            const NetworkSettingsPage(),
            '/settings/network',
          ),
          _SettingsEntry(
            Symbols.cloud_sync_rounded,
            l10n.webDavSettings,
            const WebDavSettingsPage(),
            '/settings/webdav',
          ),
        ],
      ),
      (
        l10n.content,
        [
          _SettingsEntry(
            Symbols.calendar_month_rounded,
            l10n.previewSource,
            const PreviewSourceSettingsPage(),
            '/settings/previews',
          ),
          _SettingsEntry(
            Symbols.forum_rounded,
            l10n.commentSettings,
            const CommentSettingsPage(),
            '/settings/comments',
          ),
          _SettingsEntry(
            Symbols.translate_rounded,
            l10n.languageSettings,
            const LanguageSettingsPage(),
            '/settings/language',
          ),
        ],
      ),
      (
        l10n.storage,
        [
          _SettingsEntry(
            Symbols.sd_storage_rounded,
            l10n.storage,
            const StorageSettingsPage(),
            '/settings/storage',
          ),
        ],
      ),
      (
        l10n.other,
        [
          _SettingsEntry(
            Symbols.receipt_long_rounded,
            l10n.logs,
            const LogSettingsPage(),
            '/settings/logs',
            // 设计稿：标题「日志 运行环境与调试信息」与「复制全部日志」同一行。
            trailing: const CopyLogsButton(),
          ),
          _SettingsEntry(
            Symbols.info_rounded,
            l10n.about,
            const AboutPage(),
            '/settings/about',
          ),
        ],
      ),
    ];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.initialPane});

  /// 打开时落在哪个分类（路由里的 `?pane=theme`）。为空时落在第一个。
  ///
  /// 用途：`--preview=/settings?pane=theme` 逐页截图；也方便别的页面直接深链到
  /// 某个设置分类。匹配的是分类对应路由的**最后一段**（`theme`、`layout`…）。
  final String? initialPane;

  /// Below this width the two panes do not fit, so the categories fall back to
  /// a plain pushed list.
  static const double minPaneWidth = settingsPaneMinWidth;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= minPaneWidth
      ? _SettingsPanes(initialPane: initialPane)
      : const _SettingsCategoryList();
}

/// Wide layout: categories on the left, the selected page on the right.
class _SettingsPanes extends StatefulWidget {
  const _SettingsPanes({this.initialPane});

  /// 初始选中的分类（路由 `?pane=` 的最后一段），为空时用第一个。
  final String? initialPane;

  @override
  State<_SettingsPanes> createState() => _SettingsPanesState();
}

class _SettingsPanesState extends State<_SettingsPanes> {
  var _group = 0;
  var _item = 0;
  var _appliedInitialPane = false;

  /// 把 `?pane=theme` 解析成 (group, item)。只在第一次 build 时做一次：
  /// 之后用户自己点导航就不能再被它拽回去。
  ///
  /// 放在 build 里而不是 initState：`AppLocalizations.of(context)` 依赖
  /// Localizations 祖先，initState 阶段还拿不到（会抛）。
  void _applyInitialPaneIfNeeded(BuildContext context) {
    if (_appliedInitialPane) return;
    _appliedInitialPane = true;
    final pane = widget.initialPane;
    if (pane == null || pane.isEmpty) return;
    final sections = _settingsSections(AppLocalizations.of(context)!);
    for (var g = 0; g < sections.length; g++) {
      for (var i = 0; i < sections[g].$2.length; i++) {
        // 路由形如 `/settings/theme`，取最后一段比对。
        final segments = sections[g].$2[i].route.split('/');
        if (segments.last == pane) {
          _group = g;
          _item = i;
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _applyInitialPaneIfNeeded(context);
    final l10n = AppLocalizations.of(context)!;
    final sections = _settingsSections(l10n);
    final selected = sections[_group].$2[_item];
    return Scaffold(
      // 底不要设在这里：设计稿的左栏（侧栏 + 设置分类）是白色，只有**右侧内容区**
      // 是 #F4F4F7 —— 白卡压在浅灰上才有边界。所以颜色加在下面的 Expanded 上。
      //
      // 顶部留白 28（窗口按钮悬浮带高度）：这一页没有 AppBar，内容会直接顶到窗口
      // 最上沿，右上角的「最小化 / 最大化 / 关闭」就会压在分类导航的「外观」上面。
      // 设计稿里二级导航的第一个分组在 y107，与这里留出的 28 + 内边距对得上。
      body: Padding(
        padding: const EdgeInsets.only(
          top: AppDesignTokens.windowControlsHeight,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              // 设计稿二级导航栏宽 **208**（x176~384），条目/分组按此排布。
              //
              // 原来写 188：那是照更早一版设计稿（x196~384）估的。v6 把二级导航
              // 左边界推到 176（紧贴侧栏右缘），宽度就从 188 变成 208 —— 少了 20 的话
              // 内容区整体左移，右边的卡片也跟着宽出一截，整页和设计稿对不上。
              width: 208,
              child: ListView(
                // 顶部留白 60：**以选中项的粉色底为锚点反推**。
                //
                // 设计稿「主题与色彩」那一条的淡粉底在 y124~155；上一次实测
                // （padding 89）落在 y153~186，整体低 29 → 89 - 29 = 60。
                //
                // 用选中项当锚点而不是分组标题，是因为标题的字号、行高改动都会
                // 连带影响它的位置，而条目的高度（32）和粉底是稳定的。
                // 60 是设计稿锚点反推的基准，顶部/底部留白随文字缩放一起变化。
                padding: EdgeInsets.fromLTRB(
                  4,
                  AppResponsive.scaled(context, 60),
                  0,
                  AppResponsive.scaled(context, 12),
                ),
                children: [
                  for (var group = 0; group < sections.length; group++) ...[
                    Padding(
                      // 分组标题的上下留白按设计稿实测反推：
                      //   上一组最后一项 → 本组标题 = 66~69，减去条目自身 36 → 30~33（上）
                      //   本组标题 → 第一项 = 37，减去 11 号字的行高与条目内边距 → 约 6（下）
                      // 所以上 32 / 下 6。
                      //
                      // 原来上边距是 16，组与组之间只隔了 43 —— 设计稿是 66，
                      // 每过一组就少 23，五组下来整列导航比设计稿短了一百多，
                      // 叠加图里那一串双影就是这么来的。
                      //
                      // 第一组由 ListView 顶部 padding 单独对齐，所以这里要减掉
                      // 那一份 16（否则「外观」会被推到 y152，比设计稿低 16）。
                      // 分组标题上留白 24：设计稿（`navside.png` 并排对比）里
                      // 「 界面布局 → 播放 」这一段的空白明显比我们小。
                      // 同时分组标题字号从 11 提到 12 —— 设计稿的「外观 / 播放 / 网络」
                      // 比同一栏里的条目文字更醒目，11 号看着像脚注。
                      padding: EdgeInsets.fromLTRB(
                        24,
                        AppResponsive.scaled(context, group == 0 ? 16 : 22),
                        20,
                        AppResponsive.scaled(context, 4),
                      ),
                      child: Semantics(
                        header: true,
                        child: DefaultTextStyle.merge(
                          // 分组标题用主题色（用户选哪支配色，这里就是哪支）。
                          style: TextStyle(
                            // 12 号：设计稿的分组标题（「外观」「播放」「网络」…）
                            // 比下面的条目（13 号灰）更粗、更醒目，字号与条目基本同档；
                            // 原来 11 号 + 0.2 字距看着像一行脚注，分组层级出不来。
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppDesignTokens.accentOf(context),
                            letterSpacing: 0.2,
                          ),
                          child: Text(sections[group].$1),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppResponsive.scaled(context, 12),
                      ),
                      // 设计稿没有「分组卡」的底 —— 条目本身就是透明行，只有选中项铺淡粉底。
                      child: Column(
                        children: [
                          for (
                            var item = 0;
                            item < sections[group].$2.length;
                            item++
                          )
                            _NavItem(
                              icon: sections[group].$2[item].icon,
                              label: sections[group].$2[item].label,
                              selected: group == _group && item == _item,
                              onTap: () => setState(() {
                                _group = group;
                                _item = item;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // 右侧内容区的底：#F4F4F7（设计稿 `pageBackground`）。左栏保持透明白
              // —— 白卡压在浅灰上才看得出边界，压在纯白上就糊成一片。
              child: ColoredBox(
                color: AppDesignTokens.pageBackground,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 设计稿页头：**标题与副标题在同一行**（`sub.png` 放大图）——
                    // 左「界面布局」20 Bold，右边紧跟一行 13 号灰字
                    // 「漫画模式、播放窗口与首页入口」。副标题不是换行写在下面。
                    //
                    // 之前把它渲染成标题下面的一整行，页头因此高出一行，
                    // 整页内容下沉 12~14、一屏少看到一项；后来干脆删掉，
                    // 结果每一页的说明文字都没了。现在按设计稿放回**同一行右侧**：
                    // 既恢复信息，又不多占高度。
                    //
                    // 上边距 33：设计稿标题字顶在 y66，窗口本体从 y0 开始 ——
                    // 中间那 66 里，28 是外层 Padding 让给窗口按钮悬浮带的，
                    // 剩下 38 再减去标题行自身的行高余量，落在 33 上正好。
                    // 下边距 10：设计稿标题字底 y85、横幅顶 y104，中间 19。
                    // 页头与下面的横幅、设置列用同一个可用宽度限宽居中，
                    // 2560 窗口里才不会一个贴左边、一个缩在中间。
                    SettingsContentFrame(
                      child: Padding(
                        // 水平留白按窗口宽度分档；上下 33/10 是设计稿基准，
                        // 随文字缩放一起放大，避免放大后标题贴到窗口按钮带。
                        padding: EdgeInsets.fromLTRB(
                          AppResponsive.gutterFor(
                            MediaQuery.sizeOf(context).width,
                          ),
                          AppResponsive.scaled(context, 33),
                          AppResponsive.gutterFor(
                            MediaQuery.sizeOf(context).width,
                          ),
                          AppResponsive.scaled(context, 10),
                        ),
                        child: Row(
                          // 22 的基线差：20 号标题与 13 号灰字按基线对齐看起来才整齐，
                          // 用 `CrossAxisAlignment.baseline` 会把 Row 撑到标题的行高，
                          // 这里用 `end` + 一点下移更稳（两者的行盒都按自身字号算）。
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              selected.label,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppDesignTokens.ink,
                              ),
                            ),
                            if (_settingsSubtitles[selected.route.split('/').last]
                                case final subtitle?) ...[
                              SizedBox(
                                width: AppResponsive.scaled(context, 12),
                              ),
                              // 副标题必须 flex: 0：默认 flex: 1 会和后面的 Spacer
                              // 平分剩余宽度，把页头右侧的 trailing 按钮（如「复制全部
                              // 日志」）顶到整行中间、而不是紧贴内容区右缘。
                              Flexible(
                                flex: 0,
                                child: Padding(
                                  // 让副标题的基线贴到标题基线上：
                                  // 20 号字的底部到基线还有约 5px 的 descender
                                  // 余量，13 号字只要 3，所以往下补 2（基准随文字缩放）。
                                  padding: EdgeInsets.only(
                                    bottom: AppResponsive.scaled(context, 2),
                                  ),
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppDesignTokens.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            // 页面专属控件推到最右，与标题同一行。
                            if (selected.trailing != null) ...[
                              const Spacer(),
                              selected.trailing!,
                            ],
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey(selected.route),
                        child: selected.page,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _hovered;
    // 选中 / 悬停都用主题色（用户选的配色，见 `accentOf`）。
    final accent = AppDesignTokens.accentOf(context);
    final foreground = highlighted ? accent : AppDesignTokens.inkSubtle;
    return MouseRegion(
      // 命中测试按**整行的原始矩形**做，不受子级缩放影响。
      // 按下时整行会缩到 .96，若命中区跟着缩，鼠标停在边缘就会
      // 「离开 → 进入」反复触发，文字跟着闪 —— 这也是
      // `PressScale` 里把 `transformHitTests` 关掉的原因。
      opaque: true,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PressScale(
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            // 条目行高 32：设计稿并排对比（`navside.png`）里相邻两项的
            // 文字基线距约 38，减去 13 号字的行高余量约 6 就是 32。
            // 原来 36，整列下来多出一百多像素，一屏少看到「存储 / 其他」两组。
            // 32 是设计稿基准，随文字缩放一起放大，放大后行高才装得下条目文字。
            height: AppResponsive.scaled(context, 32),
            child: Row(
              children: [
                // 设计稿选中竖条：3×20，常驻占位避免跳动；颜色跟随主题。
                SizedBox(
                  width: 3,
                  child: widget.selected
                      ? Center(
                          child: Container(
                            width: 3,
                            height: AppResponsive.scaled(context, 20),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                          ),
                        )
                      : null,
                ),
                SizedBox(width: AppResponsive.scaled(context, 9)),
                Expanded(
                  child: Container(
                    // 设计稿选中项：淡粉整行底 160×32 圆角8。
                    // 32 与左右 12 都是基准，随文字缩放一起放大，条目文字才不会贴边。
                    height: AppResponsive.scaled(context, 32),
                    padding: EdgeInsets.symmetric(
                      horizontal: AppResponsive.scaled(context, 12),
                    ),
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? AppDesignTokens.navSelectedWash
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(widget.icon, size: 16, color: foreground),
                        SizedBox(width: AppResponsive.scaled(context, 10)),
                        Expanded(
                          child: Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: foreground,
                              fontWeight: widget.selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: AppResponsive.scaled(context, 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Narrow layout: the original single-column list of categories.
class _SettingsCategoryList extends ConsumerWidget {
  const _SettingsCategoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // 与宽窗布局一致：分类标题用中性强文本色，不跟选中项抢主题色。
    Text sectionTitle(String value) => Text(
      value,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
    );
    final sections = _settingsSections(l10n);
    return Scaffold(
      appBar: AppTopBar(
        leading: permanentNavigationDrawer(context)
            ? null
            : PressScale(
                child: IconButton(
                  // 抽屉入口在窄窗（<600 逻辑像素）才出现，图标是个汉堡，光看图标
                  // 猜不出点开是什么；补 tooltip 让鼠标有提示、读屏有名字。
                  tooltip: l10n.navigationDrawer,
                  onPressed: openAppDrawer,
                  icon: const Icon(Symbols.menu_rounded),
                ),
              ),
        title: Text(l10n.settings),
      ),
      body: SettingsList(
        contentPadding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        // 窄屏单栏也按可用宽度限宽，窗口拉宽时不让分类列表一条条铺到边缘。
        maxWidth: settingsContentWidth(MediaQuery.sizeOf(context).width),
        sections: [
          for (final section in sections)
            SettingsSection(
              title: sectionTitle(section.$1),
              // 与宽窗的设置页一致：行高 42（36 + 3 × 2）。
              rowPadding: 3,
              tiles: [
                for (final entry in section.$2)
                  SettingsTile.navigation(
                    leading: Icon(entry.icon),
                    title: Text(entry.label),
                    value: const Icon(Symbols.chevron_right_rounded),
                    onPressed: (context) => context.push(entry.route),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
