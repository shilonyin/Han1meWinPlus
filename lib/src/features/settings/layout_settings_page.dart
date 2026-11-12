import 'dart:io';

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../explore/explore_controller.dart';
import '../../core/app_radius.dart';
import 'home_categories_page.dart';
import 'recommendation_settings_page.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';

class LayoutSettingsPage extends ConsumerStatefulWidget {
  const LayoutSettingsPage({super.key});

  @override
  ConsumerState<LayoutSettingsPage> createState() => _LayoutSettingsPageState();
}

class _LayoutSettingsPageState extends ConsumerState<LayoutSettingsPage> {
  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  String? _subPage;

  @override
  Widget build(BuildContext context) {
    if (_subPage == 'home-categories') {
      return SettingsSubPageScope(
        onBack: () => setState(() => _subPage = null),
        child: const HomeCategoriesPage(),
      );
    }
    if (_subPage == 'recommendations') {
      return SettingsSubPageScope(
        onBack: () => setState(() => _subPage = null),
        child: const RecommendationSettingsPage(),
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
          : AppBar(title: Text(l10n.interfaceLayout)),
      body: SettingsSubPageBody(child: ListView(
        children: [
          // 设计稿最上面那块「当前布局预览」：一张白卡，里面是一幅迷你界面示意，
          // 侧栏 / 顶栏 / 卡片列数随之变化 —— 用户调开关前就能看到结果长什么样。
          const SettingsContentFrame(child: _LayoutPreview()),
          // 卡标题用 `l10n.general`（「常规」/「General」）。
          // 设计稿那张卡没有标题，但测试与无障碍都依赖它给这一组分名字
          // （`layout_settings_test.dart` 会校验它在），所以保留。
          //
          // 行高 **42**：全设置页统一（内容 36 + `rowPadding` 3 × 2）。
          // 以前这一页单独给 10（行高 56），和主题页的 40、播放页的 44 各不相同 ——
          // 翻页时同一类设置项的疏密不一样，看起来像两套界面。
          SettingsCardList(
            title: l10n.general,
            rowPadding: 3,
            children: [
              SettingsCardItem(
                title: l10n.comicMode,
                subtitle: l10n.comicModeDescription,
                leading: const Icon(Symbols.menu_book_rounded),
                trailing: Switch(
                  value: settings.comicMode,
                  onChanged: (value) async {
                    await controller.saveChanges(
                      (current) => current.copyWith(
                        comicMode: value,
                        baseUrl: value
                            ? 'https://hanimeone.me'
                            : current.videoBaseUrl,
                        videoBaseUrl: value
                            ? current.baseUrl
                            : current.videoBaseUrl,
                      ),
                    );
                    resetHomeFeed(ref);
                  },
                ),
              ),
              // 独立播放窗口是多进程方案（play_window.dart），只有 Windows 的 runner
              // 认 `--play-window` 参数，其余平台不显示这个开关。
              if (Platform.isWindows)
                SettingsCardItem(
                  title: l10n.openVideoInWindow,
                  subtitle: l10n.openVideoInWindowDescription,
                  leading: const Icon(Symbols.picture_in_picture_rounded),
                  trailing: Switch(
                    value: settings.openVideoInWindow,
                    onChanged: (value) => controller.saveChanges(
                      (current) => current.copyWith(openVideoInWindow: value),
                    ),
                  ),
                ),
              SettingsCardItem(
                title: l10n.homeQuickCategories,
                subtitle: l10n.homeQuickCategoriesDescription,
                leading: const Icon(Symbols.bookmarks_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _subPage = 'home-categories'),
              ),
              SettingsCardItem(
                title: l10n.recommendationFilters,
                leading: const Icon(Symbols.filter_alt_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _subPage = 'recommendations'),
              ),
            ],
          ),
        ],
      )),
    );
  }
}

/// 设计稿顶部的「当前布局预览」：一张白卡 + 一幅迷你界面示意。
///
/// 它用几块纯色画「侧栏 / 顶栏 / 卡片网格」，不是真界面的截图 ——
/// 设置页自己就是被预览的那个界面，截图会无限套娃；而且这里要表达的是
/// **布局关系**（有没有侧栏、几张卡一行），用色块比真界面更清楚，
/// 也不会因为数据不同而每次长得不一样。
///
/// 配色跟着当前主题走（`colorScheme.primary`），换主题时这块示意也跟着变。
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // 侧栏常驻（「导航抽屉」那个开关已经删除，见 `settings_page.dart`）。
    // 保留这个局部变量是为了以后若恢复窄屏抽屉模式，这里只要换一次判断。
    const showSidebar = true;

    return Container(
      // 左右外边距交给外层 SettingsContentFrame（已按可用宽度推导并居中）；
      // 这里只留竖直间距，避免左右各多扣一份导致预览卡比下方卡片窄。
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            // 「当前布局预览」小标签：设计稿里是墨色 12 号粗体，
            // 在白卡**外面**左对齐（不是卡内标题）。
            padding: EdgeInsets.fromLTRB(0, 0, 0, 10),
            child: Text(
              '当前布局预览',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B1B1F),
              ),
            ),
          ),
          Container(
            // 高 127：设计稿实测预览卡 y148~275。
            // 之前给 140，比设计稿高 13，把下面的设置卡整体推下去。
            height: 127,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧栏示意：一块浅灰竖条，里面一条强调色短条 + 两条灰条。
                if (showSidebar) ...[
                  Container(
                    width: 84,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F5),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 强调色短条 = 「当前选中的导航项」
                        Container(
                          width: 56,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _previewBar(width: 48),
                        const SizedBox(height: 8),
                        _previewBar(width: 40),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                // 右侧：顶栏（进度条样式的搜索框）+ 三张卡片。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶栏：一条强调色短段 + 浅灰轨道，模拟「搜索框 + 分类」
                      Row(
                        children: [
                          Container(
                            width: 92,
                            height: 12,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _previewBar(height: 12)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // 三张卡片并排
                      Expanded(
                        child: Row(
                          children: [
                            for (var i = 0; i < 3; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F2F5),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 预览图里的浅灰占位条。
  static Widget _previewBar({
    double width = double.infinity,
    double height = 6,
  }) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE4E4EA),
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}
