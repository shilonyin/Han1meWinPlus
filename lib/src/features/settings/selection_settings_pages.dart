import 'package:material_symbols_icons/symbols.dart';
import '../shared/press_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/settings.dart';
import '../../data/remote/jav/jav_site.dart';
import '../account/account_controller.dart';
import '../explore/explore_controller.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'site_groups_page.dart';
import 'settings_pane_scope.dart';

/// 站点选择：默认站点与 AV 视频源放在同一个单选项弹层里。
///
/// 「内容少 → 弹层」的典型：原先为选一行地址要跳一个独立页面，不划算。AV 源与 hanime1
/// 是两套完全不同的站点（账号/评论/清单都不通用），所以切换后要重置首页、并让账号按新
/// 站点重新解析。
Future<void> showSitePicker(
  BuildContext context,
  WidgetRef ref,
  AppSettings settings, {
  VoidCallback? onManageGroups,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final current = settings.comicMode
      ? 'https://hanimeone.me'
      : settings.baseUrl;
  // 分组来自用户配置（没配置过时就是「按类型自动分组」的结果），空分组不进弹层。
  final groups = [
    for (final group in await ref.read(siteGroupsProvider.future))
      if (group.hosts.isNotEmpty) group,
  ];
  // 分组要 await 读出来，回来之后 context 可能已经失效（用户已经退出这一页）。
  if (!context.mounted) return;
  final hints = <String, String>{
    for (final site in javSites)
      if (site.requiresVerification) site.baseUrl: l10n.javSourceVerification,
  };
  final selected = await showOptionSettingsDialog<String>(
    context: context,
    title: l10n.site,
    current: current,
    groups: [
      for (final group in groups)
        OptionSettingGroup(
          title: siteGroupName(group, l10n),
          options: group.hosts,
        ),
    ],
    label: (value) => siteHostLabel(value, l10n),
    optionDescription: (value) => hints[value] ?? '',
    // 分组管理与「选站点」本来就是同一件事的两半（名字、顺序、谁在哪一组），所以入口
    // 直接放在这份列表下面，而不是另开一张设置卡片 —— 否则用户得在两个入口之间猜。
    footer: onManageGroups == null
        ? null
        : Builder(
            builder: (dialogContext) => Align(
              alignment: Alignment.centerLeft,
              child: PressScale(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    onManageGroups();
                  },
                  icon: const Icon(Symbols.tune_rounded, size: 18),
                  label: Text(l10n.siteGroups),
                ),
              ),
            ),
          ),
  );
  if (selected == null || selected == current) return;
  await ref
      .read(settingsProvider.notifier)
      .saveChanges(
        (settings) => settings.copyWith(
          baseUrl: selected,
          videoBaseUrl: settings.comicMode ? settings.videoBaseUrl : selected,
          useCustomMirrorSite: false,
          customMirrorSite: '',
        ),
      );
  ref.invalidate(accountProvider);
  resetHomeFeed(ref);
}

/// 新番预告的数据源：默认站点的预告表常年不可用，所以默认选「自动」，
/// 由 `PreviewsPage` 在加载失败时换到 Getchu。
class PreviewSourceSettingsPage extends ConsumerWidget {
  const PreviewSourceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current =
        ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto';
    return _RadioSettingsPage<String>(
      title: l10n.previewSource,
      current: current,
      options: const ['auto', 'default', 'getchu'],
      label: (value) => switch (value) {
        'getchu' => l10n.previewSourceGetchu,
        'default' => l10n.previewSourceDefault,
        _ => l10n.previewSourceAuto,
      },
      description: (value) => switch (value) {
        'getchu' => l10n.previewSourceGetchuDescription,
        'default' => l10n.previewSourceDefaultDescription,
        _ => l10n.previewSourceAutoDescription,
      },
      onChanged: (value) => ref
          .read(settingsProvider.notifier)
          .saveChanges((settings) => settings.copyWith(previewSource: value)),
    );
  }
}

class _RadioSettingsPage<T> extends StatelessWidget {
  const _RadioSettingsPage({
    required this.title,
    required this.current,
    required this.options,
    required this.label,
    required this.onChanged,
    this.description,
  });

  final String title;
  final T current;
  final List<T> options;
  final String Function(T value) label;
  final String Function(T value)? description;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 设计稿（`previewSrc.png`）这张页**不是**一列设置行，而是**一叠独立卡片**：
          // 每张卡 64 高、圆角 12、带左侧图标 + 标题 + 说明 + 右侧单选圈，
          // 选中那张描一圈强调色并把圆点填实。
          //
          // 原来用的是 `SettingsTile.radioTile`：一行行挤在同一张白卡里、
          // 行与行之间只有 1px 分隔线 —— 三个选项看着像同一张表的三行，
          // 用户感受不到「这是三选一」。
          for (var i = 0; i < options.length; i++)
            Padding(
              // 卡片间距 25、单卡高 96：设计稿实测三张卡占 y104~199 / 224~319 /
              // 344~，每张 **96 高**、中间隔 **25**。原来给 12 / 76，一叠下来
              // 比设计稿短一大截，三张卡挤在一起、看不出是三个独立选项。
              padding: EdgeInsets.fromLTRB(39, i == 0 ? 0 : 25, 29, 0),
              child: PressScale(
                child: Material(
                  color: AppDesignTokens.surfaceOf(context),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    onTap: () => onChanged(options[i]),
                    child: Container(
                      height: 96,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        // 选中态：一圈 1.5 的强调色描边（设计稿那张卡就是细描边，
                        // 不是实心填充 —— 填充会把三张卡里最显眼的那张变成一整块彩色）。
                        border: Border.all(
                          color: options[i] == current
                              ? accent
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 左侧图标块：淡强调色底 + 强调色图标
                          // 尺寸 44：设计稿里图标块几乎顶到卡片上下各 26 的余量，
                          // 96 - 44 = 52，上下各 26 —— 比原来 38 的块更饱满。
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                accent.withValues(alpha: .10),
                                Colors.white,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              _iconFor(options[i]),
                              size: 22,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label(options[i]),
                                  style: TextStyle(
                                    // 15 号粗体：设计稿的选项名比副标题明显一号，
                                    // 扫一眼先看到「自动 / 默认 / Getchu」这三个词。
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppDesignTokens.inkOf(context),
                                  ),
                                ),
                                if (description != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    description!(options[i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppDesignTokens.inkMutedOf(context),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 右侧单选圈：选中时实心圆点
                          _RadioCircle(
                            selected: options[i] == current,
                            color: accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 底部说明（设计稿卡片下面那一行 11 号灰字）。
          Padding(
            padding: const EdgeInsets.fromLTRB(39, 14, 29, 24),
            child: Text(
              '数据源可在「设置 · 网络」里单独配置代理。',
              style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMutedOf(context)),
            ),
          ),
        ],
      ),
    );
  }

  /// 每个选项的图标。目前只有预览数据源这一页用到，按值名映射即可；
  /// 未知值给一个中性图标，不至于渲染成空白。
  IconData _iconFor(T value) => switch ('$value') {
    'auto' => Symbols.auto_awesome_rounded,
    'default' => Symbols.public_rounded,
    'getchu' => Symbols.image_rounded,
    _ => Symbols.radio_button_checked_rounded,
  };
}

/// 单选圈：未选中是空心灰圈，选中是强调色实心圆点。
class _RadioCircle extends StatelessWidget {
  const _RadioCircle({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected
            ? color
            : AppDesignTokens.inkSubtleOf(context).withValues(alpha: .45),
        width: selected ? 2 : 1.5,
      ),
    ),
    child: selected
        ? Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          )
        : null,
  );
}
