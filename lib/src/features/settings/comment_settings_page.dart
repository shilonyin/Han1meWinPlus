import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/settings.dart';
import '../shared/press_scale.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';
import '../shared/app_top_bar.dart';

class CommentSettingsPage extends ConsumerStatefulWidget {
  const CommentSettingsPage({super.key});

  @override
  ConsumerState<CommentSettingsPage> createState() =>
      _CommentSettingsPageState();
}

class _CommentSettingsPageState extends ConsumerState<CommentSettingsPage> {
  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  String? _subPage;

  @override
  Widget build(BuildContext context) {
    if (_subPage == 'keywords') {
      return SettingsSubPageScope(
        onBack: () => setState(() => _subPage = null),
        child: const CommentKeywordsPage(),
      );
    }
    if (_subPage == 'users') {
      return SettingsSubPageScope(
        onBack: () => setState(() => _subPage = null),
        child: const CommentUserFilterPage(),
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
          : AppBar(title: Text(l10n.commentSettings)),
      body: ListView(
        children: [
          // 设计稿顶部那张**粉色统计卡**：三格并排（评论总数 / 屏蔽词 / 屏蔽用户），
          // 每格一个醒目的大数字 + 下面一行小标签。
          //
          // 它给人一个「过滤在起什么作用」的量感 —— 只列开关的话，
          // 用户看不出自己到底攒了多少屏蔽词，也不会想到去清理。
          _CommentStatsCard(settings: settings),
          // 设计稿这张卡没有小标题（页头已经写着「评论设置 / 评论区与过滤规则」），
          // 再加一行「评论」只是重复。标题传 null 即不画那一行。
          SettingsCardList(
            children: [
              SettingsCardItem(
                title: l10n.enableComments,
                leading: const Icon(Symbols.forum_rounded),
                trailing: Switch(
                  value: settings.commentsEnabled,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(commentsEnabled: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.commentKeywordFilter,
                subtitle: l10n.commentKeywordFilterDescription,
                leading: const Icon(Symbols.block_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _subPage = 'keywords'),
              ),
              SettingsCardItem(
                title: l10n.commentUserFilter,
                subtitle: l10n.commentUserFilterDescription,
                leading: const Icon(Symbols.person_off_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _subPage = 'users'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设计稿顶部的评论统计卡：淡强调色底、三格并排、每格一个大数字 + 一行小标签。
///
/// 三个数字都来自真实设置（屏蔽词条数、屏蔽用户数），没有编造：
/// 「评论总数」本地拿不到（评论是远端拉取的），所以这一格显示屏蔽规则的
/// 生效范围说明 —— 与其写一个假的 1,286，不如写一个真实有意义的数。
class _CommentStatsCard extends StatelessWidget {
  const _CommentStatsCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final keywords = settings.blockedCommentKeywords.length;
    final users = settings.blockedCommentUsers.length;
    // 屏蔽规则是否在生效：评论总开关关掉时它们不起作用，数字旁边要能看出来。
    final active = settings.commentsEnabled;
    return Container(
      // 与白卡同一套外边距（`SettingsSection` 的 39/29）。
      margin: const EdgeInsets.fromLTRB(39, 0, 29, 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        // 淡强调色底：设计稿这张卡是粉色底、压在浅灰页面底上，
        // 靠底色把它和下面那张白卡区分成「概览」与「设置」两层。
        color: Color.alphaBlend(accent.withValues(alpha: .06), Colors.white),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          _Stat(label: '过滤词', value: '$keywords', accent: accent),
          _divider(accent),
          _Stat(label: '过滤用户', value: '$users', accent: accent),
          _divider(accent),
          _Stat(
            label: active ? '过滤已生效' : '评论已关闭',
            value: active ? '开' : '关',
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _divider(Color accent) => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: accent.withValues(alpha: .12),
  );
}

/// 统计卡里的一格：上面一个 22 号强调色大数字，下面一行 11 号灰标签。
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted),
        ),
      ],
    ),
  );
}

class CommentUserFilterPage extends ConsumerWidget {
  const CommentUserFilterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _CommentFilterEditor(
    title: AppLocalizations.of(context)!.commentUserFilter,
    label: AppLocalizations.of(context)!.username,
    values:
        ref.watch(settingsProvider).valueOrNull?.blockedCommentUsers ??
        const [],
    onChanged: (values) => ref
        .read(settingsProvider.notifier)
        .saveChanges(
          (current) => current.copyWith(blockedCommentUsers: values),
        ),
  );
}

class _CommentFilterEditor extends StatefulWidget {
  const _CommentFilterEditor({
    required this.title,
    required this.label,
    required this.values,
    required this.onChanged,
  });
  final String title;
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_CommentFilterEditor> createState() => _CommentFilterEditorState();
}

class _CommentFilterEditorState extends State<_CommentFilterEditor> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      leading: settingsSubPageBack(context),
      title: Text(widget.title),
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _input,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(labelText: widget.label),
          ),
          const SizedBox(height: 12),
          PressScale(
            child: FilledButton(
              onPressed: _add,
              child: Text(AppLocalizations.of(context)!.add),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.values
                .map(
                  (value) => InputChip(
                    label: Text(value),
                    onDeleted: () => widget.onChanged(
                      widget.values.where((item) => item != value).toList(),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
  );
  void _add() {
    final value = _input.text.trim();
    if (value.isEmpty || widget.values.contains(value)) return;
    widget.onChanged([...widget.values, value]);
    _input.clear();
  }
}

class CommentKeywordsPage extends ConsumerStatefulWidget {
  const CommentKeywordsPage({super.key});

  @override
  ConsumerState<CommentKeywordsPage> createState() =>
      _CommentKeywordsPageState();
}

class _CommentKeywordsPageState extends ConsumerState<CommentKeywordsPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: M3EContainedLoadingIndicator()),
      );
    }
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppTopBar(
        leading: settingsSubPageBack(context),
        title: Text(l10n.commentKeywordFilter),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _input,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(settings.blockedCommentKeywords),
              decoration: InputDecoration(labelText: l10n.keyword),
            ),
            const SizedBox(height: 12),
            PressScale(
              child: FilledButton(
                onPressed: () => _add(settings.blockedCommentKeywords),
                child: Text(l10n.add),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: settings.blockedCommentKeywords
                  .map(
                    (keyword) => InputChip(
                      label: Text(keyword),
                      onDeleted: () => ref
                          .read(settingsProvider.notifier)
                          .saveChanges(
                            (current) => current.copyWith(
                              blockedCommentKeywords: current
                                  .blockedCommentKeywords
                                  .where((item) => item != keyword)
                                  .toList(),
                            ),
                          ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _add(List<String> keywords) {
    final value = _input.text.trim();
    if (value.isEmpty || keywords.contains(value)) return;
    ref
        .read(settingsProvider.notifier)
        .saveChanges(
          (current) => current.copyWith(
            blockedCommentKeywords: [...current.blockedCommentKeywords, value],
          ),
        );
    _input.clear();
  }
}
