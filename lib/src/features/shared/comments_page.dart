import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';

import '../../data/han1me_repository.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../account/account_controller.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import 'press_scale.dart';
import 'app_image_cache.dart';
import '../../core/app_dialog.dart';
import 'app_top_bar.dart';

enum CommentSort { latest, earliest, mostReplies, mostLikes, mostDislikes }

final contentCommentSortProvider = StateProvider.autoDispose.family<CommentSort, ({String id, String type})>((ref, target) => CommentSort.latest);

final contentCommentsProvider = FutureProvider.autoDispose.family<CommentPage, ({String id, String type})>((ref, target) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  ref.watch(accountProvider);
  final settings = await ref.watch(settingsProvider.future);
  return ref.watch(han1meRepositoryProvider).comments(settings.resolvedBaseUrl, target.id, type: target.type);
});

/// 评论项的字体尺度（设计稿实测）。
/// 名字 13 Bold、时间 10.5、正文 13、操作文字 11.5 —— 全页只用三种文字的灰，
/// 名字/正文走 ink，时间/说明走 inkMuted，操作按钮走 inkSubtle。
const _nameSize = 13.0;
const _timeSize = 10.5;
const _bodySize = 13.0;
const _actionSize = 11.5;

class CommentsPage extends ConsumerWidget {
  const CommentsPage({super.key, required this.id, required this.type, required this.title});
  final String id;
  final String type;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = (id: id, type: type);
    final l10n = AppLocalizations.of(context)!;
    final account = ref.watch(accountProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final sort = ref.watch(contentCommentSortProvider(target));
    final canWrite = account != null && settings?.commentsEnabled == true;
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackground,
      appBar: AppTopBar(
        backgroundColor: AppDesignTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Text(
          l10n.commentsTitle(title),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppDesignTokens.ink),
        ),
        actions: [
          if (settings?.commentsEnabled == true)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _SortButton(value: sort, onSelected: (value) => ref.read(contentCommentSortProvider(target).notifier).state = value),
            ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppDesignTokens.divider)),
      ),
      body: settings?.commentsEnabled != true
          ? Center(child: Text(l10n.commentsDisabled, style: const TextStyle(color: AppDesignTokens.inkMuted)))
          : ref.watch(contentCommentsProvider(target)).when(
              loading: () => const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) => Center(child: PressScale(child: FilledButton(onPressed: () => ref.invalidate(contentCommentsProvider(target)), child: Text(l10n.reload)))),
              data: (page) => page.comments.isEmpty
                  ? Center(child: Text(l10n.noComments, style: const TextStyle(color: AppDesignTokens.inkMuted)))
                  : _commentList(page, settings!.blockedCommentKeywords, settings.blockedCommentUsers, sort, target, ref),
            ),
      // 输入框已内联到列表顶部，底部只保留悬浮按钮作为快捷入口（保留原有功能）。
      floatingActionButton: canWrite ? FloatingActionButton(onPressed: () => _writeComment(context, ref, target), child: const Icon(Symbols.add_comment_rounded)) : null,
    );
  }

  List<Comment> _sort(List<Comment> comments, CommentSort sort) {
    final result = [...comments];
    result.sort((left, right) => switch (sort) {
      CommentSort.latest => right.id.compareTo(left.id),
      CommentSort.earliest => left.id.compareTo(right.id),
      CommentSort.mostReplies => (right.replyCount ?? 0).compareTo(left.replyCount ?? 0),
      CommentSort.mostLikes => (right.likesSum ?? 0).compareTo(left.likesSum ?? 0),
      CommentSort.mostDislikes => ((right.likesCount ?? 0) - (right.likesSum ?? 0)).compareTo((left.likesCount ?? 0) - (left.likesSum ?? 0)),
    });
    return result;
  }

  List<Comment> _visibleComments(List<Comment> comments, List<String> keywords, List<String> users) => comments.where((comment) => !keywords.any((keyword) => comment.content.toLowerCase().contains(keyword.toLowerCase())) && !users.any((user) => comment.username.toLowerCase().contains(user.toLowerCase()))).toList();

  Widget _commentList(CommentPage page, List<String> keywords, List<String> users, CommentSort sort, ({String id, String type}) target, WidgetRef ref) {
    final comments = _sort(_visibleComments(page.comments, keywords, users), sort);
    final canWrite = page.csrfToken != null && page.currentUserId != null;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      itemCount: comments.length + 1,
      itemBuilder: (context, index) => index == 0
          ? CommentComposer(enabled: canWrite, onSubmit: (text) => _postComment(ref, target, text))
          : CommentCard(comment: comments[index - 1], token: page.csrfToken, onChanged: () => ref.invalidate(contentCommentsProvider(target))),
    );
  }

  /// 内联输入框的发送逻辑：与 [_writeComment] 完全一致，只是文本来自输入框而不是弹窗。
  Future<void> _postComment(WidgetRef ref, ({String id, String type}) target, String text) async {
    if (text.isEmpty) return;
    final page = ref.read(contentCommentsProvider(target)).valueOrNull;
    if (page?.csrfToken == null || page?.currentUserId == null) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).postComment(settings.resolvedBaseUrl, page!.csrfToken!, page.currentUserId!, target.type, target.id, text);
    ref.invalidate(contentCommentsProvider(target));
  }

  Future<void> _writeComment(BuildContext context, WidgetRef ref, ({String id, String type}) target) async {
    final l10n = AppLocalizations.of(context)!;
    final text = await showAppDialog<String>(context: context, builder: (_) => CommentEditor(title: l10n.writeComment, hint: l10n.commentHint));
    if (text == null || text.isEmpty) return;
    await _postComment(ref, target, text);
  }
}

/// 页头的排序胶囊（设计稿右上角「最热 ▾」），浅底、无描边。
class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onSelected});
  final CommentSort value;
  final ValueChanged<CommentSort> onSelected;
  @override
  Widget build(BuildContext context) => MenuAnchor(
        builder: (context, controller, child) => PressScale(
          child: Material(
            color: AppDesignTokens.fieldFill,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: controller.open,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_label(context, value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppDesignTokens.inkSubtle)),
                  const SizedBox(width: 4),
                  const Icon(Symbols.expand_more_rounded, size: 16, color: AppDesignTokens.inkSubtle),
                ]),
              ),
            ),
          ),
        ),
        menuChildren: CommentSort.values.map((item) => MenuItemButton(onPressed: () => onSelected(item), child: Text(_label(context, item)))).toList(),
      );

  String _label(BuildContext context, CommentSort value) {
    final l10n = AppLocalizations.of(context)!;
    return switch (value) { CommentSort.latest => l10n.latest, CommentSort.earliest => l10n.earliest, CommentSort.mostReplies => l10n.mostReplies, CommentSort.mostLikes => l10n.mostLikes, CommentSort.mostDislikes => l10n.mostDislikes };
  }
}

/// 列表顶部的内联评论输入框（设计稿第一张白卡）：fieldFill 圆角输入 + 右侧发送胶囊。
/// 发送后清空输入框；逻辑仍走原来的 postComment。
class CommentComposer extends StatefulWidget {
  const CommentComposer({super.key, required this.onSubmit, this.enabled = true});
  final ValueChanged<String> onSubmit;
  final bool enabled;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Future<void>.sync(() => widget.onSubmit(text));
      if (mounted) _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppDesignTokens.fieldFill,
            child: Icon(Symbols.edit_note_rounded, size: 18, color: AppDesignTokens.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: _bodySize, color: AppDesignTokens.ink),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: widget.enabled ? l10n.commentHint : l10n.commentsDisabled,
                  hintStyle: const TextStyle(fontSize: _bodySize, color: AppDesignTokens.inkMuted),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          PressScale(
            child: Material(
              color: widget.enabled ? AppDesignTokens.accent : AppDesignTokens.fieldFill,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: widget.enabled ? _submit : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  child: Text(
                    l10n.send,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.enabled ? Colors.white : AppDesignTokens.inkMuted),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class CommentCard extends ConsumerWidget {
  const CommentCard({super.key, required this.comment, required this.token, required this.onChanged});
  final Comment comment;
  final String? token;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hasAvatar = comment.avatarUrl?.isNotEmpty == true;
    final initial = comment.username.isNotEmpty ? comment.username.characters.first : '?';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppDesignTokens.fieldFill,
          backgroundImage: hasAvatar ? appNetworkImage(comment.avatarUrl!) : null,
          child: hasAvatar ? null : Text(initial, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppDesignTokens.inkSubtle)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                child: Text(
                  comment.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: _nameSize, fontWeight: FontWeight.w700, color: AppDesignTokens.ink),
                ),
              ),
              if (comment.timeAgo != null) ...[
                const SizedBox(width: 8),
                Text(comment.timeAgo!, style: const TextStyle(fontSize: _timeSize, color: AppDesignTokens.inkMuted)),
              ],
            ]),
            const SizedBox(height: 6),
            Text(comment.content, style: const TextStyle(fontSize: _bodySize, height: 1.45, color: AppDesignTokens.ink)),
            const SizedBox(height: 6),
            Row(children: [
              _ActionText(
                label: comment.replyCount == null ? l10n.viewReplies : l10n.viewRepliesCount(comment.replyCount!),
                visible: comment.hasMoreReplies,
                onTap: () => _showReplies(context, ref),
              ),
              _ActionText(label: l10n.reply, visible: comment.id.isNotEmpty, onTap: token == null ? null : () => _reply(context, ref)),
              const Spacer(),
              _VotePill(
                icon: Symbols.thumb_up_rounded,
                filled: comment.liked,
                value: comment.likesSum?.toString() ?? comment.likeCount ?? '0',
                onTap: token == null ? null : () => _vote(ref, true),
              ),
            ]),
          ]),
        ),
        MenuAnchor(
          builder: (context, controller, child) => PressScale(child: IconButton(tooltip: l10n.more, onPressed: controller.open, icon: const Icon(Symbols.more_vert_rounded, size: 18, color: AppDesignTokens.inkMuted), visualDensity: VisualDensity.compact)),
          menuChildren: [
            MenuItemButton(onPressed: token == null ? null : () => _report(context, ref), leadingIcon: const Icon(Symbols.flag_rounded), child: Text(l10n.report)),
            MenuItemButton(onPressed: () => _filterUser(ref), leadingIcon: const Icon(Symbols.person_off_rounded), child: Text(l10n.filter)),
          ],
        ),
      ]),
    );
  }

  Future<void> _vote(WidgetRef ref, bool positive) async {
    if (token == null) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).voteComment(settings.resolvedBaseUrl, token!, comment, positive);
    onChanged();
  }

  Future<void> _reply(BuildContext context, WidgetRef ref) async {
    final text = await showAppDialog<String>(context: context, builder: (_) => CommentEditor(title: AppLocalizations.of(context)!.replyComment));
    if (text == null || text.isEmpty || token == null) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).replyComment(settings.resolvedBaseUrl, token!, comment.id, text);
    onChanged();
  }

  Future<void> _showReplies(BuildContext context, WidgetRef ref) async {
    final settings = await ref.read(settingsProvider.future);
    final page = await ref.read(han1meRepositoryProvider).replies(settings.resolvedBaseUrl, comment.id);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppDesignTokens.pageBackground,
      barrierColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) => SafeArea(child: ListView.builder(padding: const EdgeInsets.symmetric(vertical: 8), itemCount: page.comments.length, itemBuilder: (context, index) => CommentCard(comment: page.comments[index], token: token, onChanged: onChanged))),
    );
  }

  Future<void> _filterUser(WidgetRef ref) => ref.read(settingsProvider.notifier).saveChanges((current) => current.blockedCommentUsers.any((user) => user.toLowerCase() == comment.username.toLowerCase()) ? current : current.copyWith(blockedCommentUsers: [...current.blockedCommentUsers, comment.username]));

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final account = ref.read(accountProvider).valueOrNull;
    if (token == null || account?.id == null) return;
    final reasons = await _reportReasons(context);
    if (!context.mounted || reasons.isEmpty) return;
    final reason = await showAppDialog<String>(context: context, builder: (context) => SimpleDialog(title: Text(AppLocalizations.of(context)!.report), children: reasons.map((item) => SimpleDialogOption(onPressed: () => Navigator.pop(context, item), child: Text(item))).toList()));
    if (reason == null) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).reportComment(settings.resolvedBaseUrl, token!, account!.id!, comment, reason);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.reportSubmitted)));
  }

  Future<List<String>> _reportReasons(BuildContext context) async {
    // 语言在 await 之前算好：读资源是异步的，回来时再拿 context 取 locale 会踩跨 async gap 的坑。
    final Locale currentLocale = Localizations.localeOf(context);
    final json = await DefaultAssetBundle.of(context).loadString('assets/search_options/report_reason.json');
    final locale = currentLocale.languageCode == 'zh' ? (currentLocale.scriptCode == 'Hant' || currentLocale.countryCode == 'TW' ? 'zh-rTW' : 'zh-rCN') : 'en';
    return (jsonDecode(json) as List).whereType<Map>().map((item) => (item['lang'] as Map?)?[locale] as String? ?? item['reason_key'] as String? ?? '').where((item) => item.isNotEmpty).toList();
  }
}

/// 评论底部的文字操作（回复 / 举报 / 查看回复），11.5 灰、无按钮描边。
class _ActionText extends StatelessWidget {
  const _ActionText({required this.label, required this.visible, required this.onTap});
  final String label;
  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: _actionSize, color: AppDesignTokens.inkSubtle)),
        ),
      ),
    );
  }
}

/// 右侧的点赞胶囊（设计稿「♥ 42」浅底圆角胶囊）。
class _VotePill extends StatelessWidget {
  const _VotePill({required this.icon, required this.filled, required this.value, required this.onTap});
  final IconData icon;
  final bool filled;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: Material(
          color: AppDesignTokens.fieldFill,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, fill: filled ? 1 : 0, color: AppDesignTokens.accent),
                const SizedBox(width: 5),
                Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppDesignTokens.inkSubtle)),
              ]),
            ),
          ),
        ),
      );
}

class CommentEditor extends StatefulWidget {
  const CommentEditor({super.key, required this.title, this.hint});
  final String title;
  final String? hint;
  @override
  State<CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<CommentEditor> {
  final _controller = TextEditingController();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(controller: _controller, autofocus: true, minLines: 3, maxLines: 6, decoration: InputDecoration(hintText: widget.hint)),
        actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: Text(AppLocalizations.of(context)!.send)))],
      );
}
