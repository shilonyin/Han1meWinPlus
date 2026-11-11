import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
import '../../core/app_design_tokens.dart';
import '../shared/app_image_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/account.dart';
import '../../domain/models/library.dart';
import '../../data/local/watch_repository.dart';
import '../../data/local/library_repository.dart';
import '../library/library_page.dart';
import '../shared/press_scale.dart';
import 'account_controller.dart';
import '../../core/app_dialog.dart';
import '../shared/app_top_bar.dart';

/// 「我的」：顶部资料卡（头像 / 昵称 / 统计 + 账号操作），下面是清单页签。
///
/// 页签内容与「我的清单」页共用（[LibraryTabView]），所以侧栏里不再重复列一份。
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final account = ref.watch(accountProvider).valueOrNull;
    final library = ref.watch(libraryProvider).valueOrNull;
    final watch = ref.watch(watchProvider).valueOrNull;
    final continueItems = watch?.continueItems ?? const <WatchProgress>[];
    final histories = watch?.histories ?? const <WatchHistory>[];
    final artists = library?.artists ?? const <SubscribedArtist>[];
    final favorites = library?.favorites ?? const <FollowingVideo>[];
    final watchLater = library?.watchLater ?? const <FollowingVideo>[];
    // 只数最近 30 天的观看记录，和「观看统计」卡片上的口径一致。
    final monthAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final recentCount = histories.where((item) => item.createdAt >= monthAgo).length;
    // 平均好评率：rating 是 '100%' 这类字符串，取不到就按 0 处理。
    final ratings = favorites
        .map((item) => int.tryParse((item.rating ?? '').replaceAll('%', '').trim()))
        .whereType<int>()
        .toList(growable: false);
    final avgRating = ratings.isEmpty ? 0 : (ratings.reduce((a, b) => a + b) / ratings.length).round();
    return Scaffold(
      appBar: AppTopBar(
        title: Text(l10n.mine),
        actions: [
          PressScale(child: IconButton(tooltip: l10n.settings, onPressed: () => context.push('/settings'), icon: const Icon(Symbols.settings_rounded))),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          _ProfileCard(account: account, collectionCount: favorites.length, followCount: artists.length, watchedCount: histories.length),
          const SizedBox(height: 20),
          // 四个功能卡：我的关注 / 观看统计 / 稍后再看 / 我的评分。
          // 名称与副文案按设计稿，数值一律取真实本地数据，不写示例数字。
          LayoutBuilder(builder: (context, constraints) {
            const gap = 12.0;
            final w = (constraints.maxWidth - gap * 3) / 4;
            return Row(
              children: [
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.favorite_rounded, label: '我的关注', value: '${artists.length} 位作者', onTap: () => context.push('/library/subscriptions'))),
                SizedBox(width: gap),
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.bar_chart_rounded, label: '观看统计', value: '最近 30 天 $recentCount 条', onTap: () => context.push('/stats'))),
                SizedBox(width: gap),
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.watch_later_rounded, label: '稍后再看', value: '${watchLater.length} 部', onTap: () => context.push('/library'))),
                SizedBox(width: gap),
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.star_rounded, label: '我的评分', value: ratings.isEmpty ? '暂无评分' : '$avgRating% 平均', onTap: () => context.push('/library/favorites'))),
              ],
            );
          }),
          const SizedBox(height: 24),
          // 两栏：左「最近观看」缩略图网格 + 右「关注更新」。
          LayoutBuilder(builder: (context, constraints) {
            const gap = 24.0;
            final leftW = (constraints.maxWidth - gap) * 0.62;
            final rightW = constraints.maxWidth - gap - leftW;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: leftW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: '最近观看', extra: '共 ${continueItems.length} 条', onMore: () => context.push('/library/history')),
                      const SizedBox(height: 12),
                      _RecentWatchGrid(items: continueItems),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: rightW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: '关注更新', extra: '${artists.length} 位作者'),
                      const SizedBox(height: 12),
                      _UpdateCard(artists: artists.take(4).toList()),
                    ],
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 24),
          _TasteCard(favorites: favorites, avgRating: avgRating),
        ],
      ),
    );
  }
}

/// 顶部资料卡：白底圆角，左侧头像/昵称/站点，右侧三块灰色统计 + 退出登录。
///
/// 设计稿这一行把「收藏 / 关注 / 已看」做成三个独立的浅灰圆角块横排，
/// 而不是贴在昵称下面的一行小字；整卡也不铺品牌粉薄层。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({this.account, required this.collectionCount, required this.followCount, required this.watchedCount});

  final Account? account;
  final int collectionCount;
  final int followCount;
  final int watchedCount;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: account == null
          ? const _SignedOutProfile()
          : _SignedInProfile(account: account, collectionCount: collectionCount, followCount: followCount, watchedCount: watchedCount),
    );
  }
}

/// 已登录时的资料卡内容。
class _SignedInProfile extends ConsumerWidget {
  const _SignedInProfile({required this.account, required this.collectionCount, required this.followCount, required this.watchedCount});

  final Account account;
  final int collectionCount;
  final int followCount;
  final int watchedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hasAvatar = account.avatarUrl?.isNotEmpty == true;
    final name = account.name?.isNotEmpty == true ? account.name! : l10n.signedIn;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PressScale(child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => _openProfile(context, ref, account),
          child: CircleAvatar(radius: 30, backgroundColor: AppDesignTokens.fieldFill, backgroundImage: hasAvatar ? appNetworkImage(account.avatarUrl!) : null, child: hasAvatar ? null : const Icon(Symbols.person_rounded, size: 30)),
        )),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
              const SizedBox(height: 3),
              const Text('hanime1.com', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppDesignTokens.accentDeep)),
              const SizedBox(height: 3),
              Text('已同步 · 上次更新 10 分钟前', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _StatBlock(number: '$collectionCount', label: '收藏'),
        const SizedBox(width: 10),
        _StatBlock(number: '$followCount', label: '关注'),
        const SizedBox(width: 10),
        _StatBlock(number: '$watchedCount', label: '已看'),
        const SizedBox(width: 16),
        // 账号管理 / 编辑资料 / 改密码是真功能，但设计稿只露「退出登录」。
        // 收进这个菜单里，界面保持干净，功能也不丢。
        PopupMenuButton<String>(
          icon: const Icon(Symbols.more_horiz_rounded, size: 20, color: AppDesignTokens.inkSubtle),
          onSelected: (value) => switch (value) {
            'account' => unawaited(_showAccountSheet(context, ref)),
            'profile' => unawaited(_showEditProfile(context, account)),
            'password' => unawaited(_showChangePassword(context)),
            _ => null,
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(value: 'account', child: Text(l10n.accountManage)),
            PopupMenuItem<String>(value: 'profile', child: Text(l10n.editProfile)),
            PopupMenuItem<String>(value: 'password', child: Text(l10n.changePassword)),
          ],
        ),
        const SizedBox(width: 8),
        PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _confirmLogout(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Text(l10n.logout, style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtle)),
            ),
          ),
        ),
      ],
    );
  }
}

/// 资料卡右侧的一块统计：浅灰圆角底，上面数字、下面标签。
class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.md)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(number, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
      ],
    ),
  );
}

/// 未登录时的资料卡内容：占位头像 + 登录按钮。
class _SignedOutProfile extends StatelessWidget {
  const _SignedOutProfile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        const CircleAvatar(radius: 32, child: Icon(Symbols.person_rounded, size: 32)),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.signedOut, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(l10n.tapToLogin, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
        PressScale(child: FilledButton(onPressed: () => context.push('/login'), child: Text(l10n.login))),
      ],
    );
  }
}

/// 打开站内个人资料页，回来后刷新一下账号信息（昵称/头像可能改过）。
Future<void> _openProfile(BuildContext context, WidgetRef ref, Account account) async {
  await context.push('/account/profile/${account.id}');
  if (context.mounted) await ref.read(accountProvider.notifier).refresh();
}

/// 账号管理（切换 / 移除 / 新增账号）。
Future<void> _showAccountSheet(BuildContext context, WidgetRef ref) {
  final accounts = ref.read(accountsProvider).valueOrNull ?? const <Account>[];
  final active = ref.read(accountProvider).valueOrNull;
  return showModalBottomSheet<void>(context: context, barrierColor: Colors.transparent, showDragHandle: true, builder: (sheetContext) => _AccountSheet(accounts: accounts, active: active));
}

/// 编辑个人资料（昵称 / 邮箱）—— 弹出对话框，保存后自动关闭。
Future<void> _showEditProfile(BuildContext context, Account account) => showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.editProfile),
        // 对话框基准宽随文字缩放，放大后内容不被挤窄，上限取内容区宽保证小窗不溢出。
        content: SizedBox(
          width: AppResponsive.scaled(context, 360).clamp(
            0.0,
            AppResponsive.contentWidthFor(MediaQuery.sizeOf(context).width),
          ),
          child: SingleChildScrollView(
            child: _ProfileForm(
              account: account,
              onDone: () => Navigator.pop(dialogContext),
            ),
          ),
        ),
        actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(dialogContext)!.cancel)))],
      ),
    );

/// 更改密码 —— 同样弹对话框，保存后自动关闭。
Future<void> _showChangePassword(BuildContext context) => showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.changePassword),
        // 对话框基准宽随文字缩放，放大后内容不被挤窄，上限取内容区宽保证小窗不溢出。
        content: SizedBox(
          width: AppResponsive.scaled(context, 360).clamp(
            0.0,
            AppResponsive.contentWidthFor(MediaQuery.sizeOf(context).width),
          ),
          child: SingleChildScrollView(
            child: _PasswordForm(onDone: () => Navigator.pop(dialogContext)),
          ),
        ),
        actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(dialogContext)!.cancel)))],
      ),
    );

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.logout),
      content: Text(l10n.logoutConfirmation),
      actions: [
        PressScale(child: TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.cancel))),
        PressScale(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l10n.logout))),
      ],
    ),
  );
  if (confirmed == true) await ref.read(accountProvider.notifier).logout();
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet({required this.accounts, this.active});

  final List<Account> accounts;
  final Account? active;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(AppLocalizations.of(context)!.accountManage)),
            ...accounts.map(
              (item) => ListTile(
                leading: CircleAvatar(
                  backgroundImage: item.avatarUrl?.isNotEmpty == true ? appNetworkImage(item.avatarUrl!) : null,
                  child: item.avatarUrl?.isNotEmpty == true ? null : const Icon(Symbols.person_rounded),
                ),
                title: Text(item.name?.isNotEmpty == true ? item.name! : item.id ?? ''),
                subtitle: Text(item.email ?? item.id ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.id == active?.id) const Icon(Symbols.check_circle_rounded),
                    PressScale(child: IconButton(
                      icon: const Icon(Symbols.remove_circle_rounded),
                      tooltip: AppLocalizations.of(context)!.removeAccount,
                      onPressed: () async {
                        if (item.id == null) return;
                        await ref.read(accountProvider.notifier).remove(item);
                        if (context.mounted) Navigator.pop(context);
                      },
                    )),
                  ],
                ),
                onTap: item.id == active?.id
                    ? null
                    : () async {
                        await ref.read(accountProvider.notifier).activate(item);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Symbols.person_add_rounded),
              title: Text(AppLocalizations.of(context)!.addAccount),
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.push('/login');
              },
            ),
          ],
        ),
      );
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.account, this.onDone});
  final Account account;

  /// 保存成功后的回调（放在对话框里时用来关闭自己）。
  final VoidCallback? onDone;
  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.account.name);
  late final _email = TextEditingController(text: widget.account.email);
  @override
  void dispose() { _name.dispose(); _email.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [TextField(controller: _name, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.username)), TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.email)), const SizedBox(height: 12), PressScale(child: FilledButton(onPressed: () async { await ref.read(accountProvider.notifier).updateProfile(_name.text.trim(), _email.text.trim()); widget.onDone?.call(); }, child: Text(AppLocalizations.of(context)!.saveProfile)))]);
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm({this.onDone});

  /// 保存成功后的回调（放在对话框里时用来关闭自己）。
  final VoidCallback? onDone;
  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _old = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  @override
  void dispose() { _old.dispose(); _password.dispose(); _confirmation.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [TextField(controller: _old, obscureText: true, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.oldPassword)), TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.newPassword)), TextField(controller: _confirmation, obscureText: true, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.confirmNewPassword)), const SizedBox(height: 12), PressScale(child: FilledButton(onPressed: () async { await ref.read(accountProvider.notifier).updatePassword(_old.text, _password.text, _confirmation.text); widget.onDone?.call(); }, child: Text(AppLocalizations.of(context)!.changePassword)))]);
}

/// 快捷入口卡片。
class _QuickEntry extends StatelessWidget {
  const _QuickEntry({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 设计稿功能卡：白底圆角、左上一个淡粉图标块、标题 + 数值、右上角 ›。
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppDesignTokens.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, size: 18, color: AppDesignTokens.accentDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                    const SizedBox(height: 4),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
                  ],
                ),
              ),
              const Icon(Symbols.chevron_right_rounded, size: 16, color: Color(0xFFC4C4CE)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区标题（左标题 + 紧跟的计数灰字 + 可选右侧「全部 ›」）。设计稿 15 Bold。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.extra, this.onMore});

  final String title;
  final String? extra;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
        if (extra != null) ...[
          const SizedBox(width: 10),
          Text(extra!, style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
        ],
        const Spacer(),
        if (onMore != null)
          PressScale(
            child: InkWell(
              onTap: onMore,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('全部 ›', style: TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMuted)),
              ),
            ),
          ),
      ],
    );
  }
}

/// 「最近观看」：设计稿是 3 列缩略图网格，不是竖排列表。
///
/// 每格是一张封面 + 底部进度条，下面一行标题、一行进度与时间。
/// 数据来自 `continueItems`，本来就有封面、位置与总时长。
class _RecentWatchGrid extends StatelessWidget {
  const _RecentWatchGrid({required this.items});

  final List<WatchProgress> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
        alignment: Alignment.center,
        child: const Text('还没有观看记录', style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
      );
    }
    final shown = items.take(6).toList(growable: false);
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 14.0;
      final w = (constraints.maxWidth - gap * 2) / 3;
      return Wrap(
        spacing: gap,
        runSpacing: 14,
        children: [
          for (final item in shown) SizedBox(width: w, child: _RecentGridTile(item: item)),
        ],
      );
    });
  }
}

class _RecentGridTile extends StatelessWidget {
  const _RecentGridTile({required this.item});

  final WatchProgress item;

  @override
  Widget build(BuildContext context) {
    final pct = item.durationMs > 0 ? (item.positionMs / item.durationMs).clamp(0.0, 1.0) : 0.0;
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => context.push('/video/${item.videoCode}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppCachedNetworkImage(imageUrl: item.coverUrl ?? '', fit: BoxFit.cover, errorWidget: (c, u, e) => const ColoredBox(color: Color(0xFF3D3540))),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: 4,
                        child: Row(
                          children: [
                            Expanded(flex: (pct * 1000).round().clamp(1, 1000), child: const ColoredBox(color: AppDesignTokens.accent)),
                            Expanded(flex: ((1 - pct) * 1000).round().clamp(1, 1000), child: const ColoredBox(color: Color(0x59000000))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
            const SizedBox(height: 3),
            Text('${_fmtMs(item.positionMs)} / ${_fmtMs(item.durationMs)} · ${_relativeTime(item.updatedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// 「关注更新」：白卡里一列圆头像条目，头像用真实订阅作者头像。
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.artists});

  final List<SubscribedArtist> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
        alignment: Alignment.center,
        child: const Text('还没有关注任何作者', style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
      );
    }
    return Container(
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var i = 0; i < artists.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF2F2F6)),
            _UpdateRow(artist: artists[i]),
          ],
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.artist});

  final SubscribedArtist artist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppDesignTokens.fieldFill,
            backgroundImage: artist.avatarUrl?.isNotEmpty == true ? appNetworkImage(artist.avatarUrl!) : null,
            child: artist.avatarUrl?.isNotEmpty == true ? null : const Icon(Symbols.person_rounded, size: 16, color: AppDesignTokens.inkMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                const SizedBox(height: 4),
                const Text('有更新', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppDesignTokens.accentDeep)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「我的口味」：设计稿是横跨整页的一条 —— 左侧大号平均好评率，
/// 右侧一排评分分布条。
///
/// 这里不编造「纯爱 62% / 后宫 48%」这类口味标签：本地库没有题材字段。
/// 改成按收藏影片的**真实好评率**分五档统计，标签与数值都能对上数据。
class _TasteCard extends StatelessWidget {
  const _TasteCard({required this.favorites, required this.avgRating});

  final List<FollowingVideo> favorites;
  final int avgRating;

  @override
  Widget build(BuildContext context) {
    // 五档：100 / 90-99 / 80-89 / 70-79 / <70，统计每档占比。
    final buckets = List<int>.filled(5, 0);
    var counted = 0;
    for (final item in favorites) {
      final rating = int.tryParse((item.rating ?? '').replaceAll('%', '').trim());
      if (rating == null) continue;
      counted++;
      final index = rating >= 100 ? 0 : rating >= 90 ? 1 : rating >= 80 ? 2 : rating >= 70 ? 3 : 4;
      buckets[index]++;
    }
    final labels = const ['100%', '90-99%', '80-89%', '70-79%', '<70%'];
    return Container(
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('我的口味', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
              const SizedBox(width: 10),
              Text('基于 $counted 部收藏影片的好评率', style: const TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMuted)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$avgRating%', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppDesignTokens.accentDeep)),
                  const SizedBox(height: 2),
                  const Text('平均好评率', style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < 5; i++)
                      SizedBox(
                        width: 150,
                        child: _RatingBar(label: labels[i], ratio: counted == 0 ? 0.0 : buckets[i] / counted, count: buckets[i]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 口味条里的单个评分档：标签 + 进度条 + 百分比。
class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.label, required this.ratio, required this.count});

  final String label;
  final double ratio;
  final int count;

  @override
  Widget build(BuildContext context) {
    final pct = (ratio * 100).round();
    return Row(
      children: [
        SizedBox(width: 46, child: Text(label, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkMuted))),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: SizedBox(
              height: 7,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0xFFF2F2F6))),
                  FractionallySizedBox(widthFactor: ratio, child: const ColoredBox(color: AppDesignTokens.accentDeep)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 34, child: Text('$pct%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkSubtle))),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(fontSize: 9.5, color: AppDesignTokens.inkMuted)),
        ],
      ],
    );
  }
}

/// 毫秒 → mm:ss。
String _fmtMs(int ms) {
  final total = (ms / 1000).round();
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// 时间戳 → 「X 分钟前 / X 小时前 / X 天前」。
String _relativeTime(int epochMs) {
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  return '${diff.inDays} 天前';
}
