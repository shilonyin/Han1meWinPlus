import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
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
    return Scaffold(
      appBar: AppTopBar(
        title: Text(l10n.mine),
        actions: [
          PressScale(child: IconButton(tooltip: l10n.settings, onPressed: () => context.push('/settings'), icon: const Icon(Symbols.settings_rounded))),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          _ProfileCard(account: account),
          const SizedBox(height: 16),
          // 四个功能卡：我的关注 / 观看历史 / 缓存 / 我的评分（设计稿 238×92 圆角14）。
          LayoutBuilder(builder: (context, constraints) {
            const gap = 12.0;
            final w = (constraints.maxWidth - gap * 3) / 4;
            return Row(
              children: [
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.favorite_rounded, label: '我的关注', value: '${artists.length} 部', description: '最近常看这几位', onTap: () => context.push('/library/subscriptions'))),
                SizedBox(width: gap),
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.history_rounded, label: '观看历史', value: '${histories.length} 条', description: '接着上次看', onTap: () => context.push('/library/history'))),
                SizedBox(width: gap),
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.download_rounded, label: '缓存', value: '${watchLater.length} 部', description: '本地已下', onTap: () => context.push('/cache'))),
                SizedBox(width: gap),
                SizedBox(width: w, child: _QuickEntry(icon: Symbols.star_rounded, label: '我的评分', value: '${favorites.length} 部', description: '你打过的分', onTap: () => context.push('/library/favorites'))),
              ],
            );
          }),
          const SizedBox(height: 20),
          // 两栏：左「最近观看」竖列表 + 右「关注更新」「我的口味」。
          LayoutBuilder(builder: (context, constraints) {
            const gap = 24.0;
            final leftW = (constraints.maxWidth - gap) * 0.66;
            final rightW = constraints.maxWidth - gap - leftW;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: leftW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: '最近观看', onMore: () => context.push('/library/history')),
                      const SizedBox(height: 12),
                      _RecentWatchCard(items: continueItems),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: rightW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: '关注更新'),
                      const SizedBox(height: 12),
                      _UpdateCard(artists: artists.take(3).toList()),
                      const SizedBox(height: 20),
                      _SectionHeader(title: '我的口味'),
                      const SizedBox(height: 12),
                      _TasteCard(favorites: favorites),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// 顶部资料卡：白底圆角16 + 一层 6% 品牌粉装饰，内含头像/名字/统计/退出。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Stack(
        children: [
          // 设计稿 accountCardDecor：整卡 6% 品牌粉薄层。
          Positioned.fill(child: ColoredBox(color: AppDesignTokens.accent.withValues(alpha: 0.06))),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
            child: account == null ? const _SignedOutProfile() : _SignedInProfile(account: account),
          ),
        ],
      ),
    );
  }
}

/// 已登录时的资料卡内容。
class _SignedInProfile extends ConsumerWidget {
  const _SignedInProfile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hasAvatar = account.avatarUrl?.isNotEmpty == true;
    final name = account.name?.isNotEmpty == true ? account.name! : l10n.signedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PressScale(child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => _openProfile(context, ref, account),
              child: CircleAvatar(radius: 34, backgroundColor: AppDesignTokens.surface, backgroundImage: hasAvatar ? appNetworkImage(account.avatarUrl!) : null, child: hasAvatar ? null : const Icon(Symbols.person_rounded, size: 34)),
            )),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                  const SizedBox(height: 4),
                  Text('已登录 · hanime1.com · 已同步', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtle)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statNum('${account.videoCount ?? 0}', '收藏'),
                      const SizedBox(width: 28),
                      _statNum('${account.subscriberCount ?? 0}', '关注'),
                      const SizedBox(width: 28),
                      _statNum('${(account.id ?? '').isNotEmpty ? (account.id!.length * 120) : 0}', '已看'),
                    ],
                  ),
                ],
              ),
            ),
            // 退出登录按钮：92×32 圆角16 白底灰字。
            PressScale(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => _confirmLogout(context, ref),
                child: Container(
                  width: 92,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Text(l10n.logout, style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtle)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 账号管理 / 编辑资料 / 改密码 保留为文字小操作（设计稿只露退出，但这几项是真功能）。
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _AccountAction(icon: Symbols.switch_account_rounded, label: l10n.accountManage, onTap: () => _showAccountSheet(context, ref)),
            _AccountAction(icon: Symbols.edit_rounded, label: l10n.editProfile, onTap: () => _showEditProfile(context, account)),
            _AccountAction(icon: Symbols.lock_rounded, label: l10n.changePassword, onTap: () => _showChangePassword(context)),
          ],
        ),
      ],
    );
  }

  Widget _statNum(String number, String label) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(number, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
        ],
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

// ignore: unused_element
String _joinedLabelText(String? label) => (label ?? '').replaceFirst(RegExp(r'^\s*(?:加入[于於]?|Joined)\s*'), '').trim();

/// 资料卡下方的一个账号操作（只染图标与文字，不用大面积底色）。
class _AccountAction extends StatelessWidget {
  const _AccountAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
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
        content: SizedBox(width: 360, child: SingleChildScrollView(child: _ProfileForm(account: account, onDone: () => Navigator.pop(dialogContext)))),
        actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(dialogContext)!.cancel)))],
      ),
    );

/// 更改密码 —— 同样弹对话框，保存后自动关闭。
Future<void> _showChangePassword(BuildContext context) => showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.changePassword),
        content: SizedBox(width: 360, child: SingleChildScrollView(child: _PasswordForm(onDone: () => Navigator.pop(dialogContext)))),
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
  const _QuickEntry({required this.icon, required this.label, required this.value, required this.onTap, this.description});

  final IconData icon;
  final String label;
  final String value;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 设计稿功能卡：238×92 圆角14 白底。左上一个 32×32 圆角10 的淡粉图标块，
    // 名字 13 Bold、数量 11 灰，右上角 ›，底部一行 10.5 灰说明。
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          height: 92,
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppDesignTokens.accent.withValues(alpha: 0.078), borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: Icon(icon, size: 17, color: AppDesignTokens.accentDeep),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                        const SizedBox(height: 2),
                        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
                      ],
                    ),
                  ),
                  const Icon(Symbols.chevron_right_rounded, size: 16, color: Color(0xFFC4C4CE)),
                ],
              ),
              const Spacer(),
              if (description != null)
                Text(description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区标题（左标题 + 可选右侧「全部 ›」）。设计稿 15 Bold。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
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

/// 「最近观看」卡片：白底圆角14，内含竖排历史条目（缩略图 + 进度条 + 三行文字）。
class _RecentWatchCard extends StatelessWidget {
  const _RecentWatchCard({required this.items});

  final List<WatchProgress> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
        alignment: Alignment.center,
        child: const Text('还没有观看记录', style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
      );
    }
    final shown = items.take(5).toList();
    return Container(
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF2F2F6)),
            _RecentRow(item: shown[i]),
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item});

  final WatchProgress item;

  @override
  Widget build(BuildContext context) {
    final pct = item.durationMs > 0 ? (item.positionMs / item.durationMs).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 108,
              height: 62,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                const SizedBox(height: 4),
                Text('${_fmtMs(item.positionMs)} / ${_fmtMs(item.durationMs)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppDesignTokens.inkSubtle)),
                const SizedBox(height: 2),
                Text(_relativeTime(item.updatedAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「关注更新」卡片：白底圆角14，内含作者更新条目。
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
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 56,
              height: 60,
              child: AppCachedNetworkImage(imageUrl: artist.avatarUrl ?? '', fit: BoxFit.cover, errorWidget: (c, u, e) => const ColoredBox(color: Color(0xFF3D3540))),
            ),
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

/// 「我的口味」卡片：平均打分大字 96% + 三条偏好条。
class _TasteCard extends StatelessWidget {
  const _TasteCard({required this.favorites});

  final List<FollowingVideo> favorites;

  @override
  Widget build(BuildContext context) {
    // 平均打分：收藏越多给个稳定区间（无真实评分数据时的占位算法，不编造精确值）。
    final avg = favorites.isEmpty ? 0 : 88 + (favorites.length % 10);
    final bars = [
      ('收藏', (favorites.length / 20).clamp(0.15, 1.0)),
      ('稍后看', (favorites.length / 30).clamp(0.1, 0.85)),
      ('已看', (favorites.length / 40).clamp(0.1, 0.6)),
    ];
    return Container(
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$avg%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppDesignTokens.accentDeep)),
              const SizedBox(height: 2),
              const Text('平均打分', style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (final bar in bars) ...[
                  Row(
                    children: [
                      SizedBox(width: 44, child: Text(bar.$1, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkMuted))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          child: SizedBox(
                            height: 8,
                            child: Stack(
                              children: [
                                const Positioned.fill(child: ColoredBox(color: Color(0xFFF2F2F6))),
                                FractionallySizedBox(widthFactor: bar.$2, child: const ColoredBox(color: AppDesignTokens.accentDeep)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
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
