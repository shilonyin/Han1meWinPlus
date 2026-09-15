import 'package:flutter/material.dart';

import '../shared/app_image_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/account.dart';
import '../library/library_page.dart';
import '../shared/underline_tab_strip.dart';
import 'account_controller.dart';

/// 「我的」：顶部资料卡（头像 / 昵称 / 统计 + 账号操作），下面是清单页签。
///
/// 页签内容与「我的清单」页共用（[LibraryTabView]），所以侧栏里不再重复列一份。
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  /// 0 稍后观看 / 1 喜欢的影片 / 2 播放清单 / 3 我的订阅。
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final account = ref.watch(accountProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mine)),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: _ProfileCard(account: account)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: UnderlineTabStrip(labels: [l10n.watchLater, l10n.favoriteVideos, l10n.playlists, l10n.subscriptions], index: _tab, onSelected: (index) => setState(() => _tab = index)),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: LibraryTabView(key: ValueKey(_tab), index: _tab)),
        ],
      ),
    );
  }
}

/// 顶部资料卡：左侧头像 + 昵称/统计，右侧「账户资料」入口，下面一排账号操作。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: account == null ? const _SignedOutProfile() : _SignedInProfile(account: account),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasAvatar = account.avatarUrl?.isNotEmpty == true;
    final name = account.name?.isNotEmpty == true ? account.name! : l10n.signedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () => _openProfile(context, ref, account),
              child: CircleAvatar(radius: 32, backgroundImage: hasAvatar ? appNetworkImage(account.avatarUrl!) : null, child: hasAvatar ? null : const Icon(Icons.person, size: 32)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('@${account.id}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
                  const SizedBox(height: 10),
                  Text(l10n.subscriberVideoCount(account.subscriberCount ?? 0, account.videoCount ?? 0), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(l10n.joinedDate(_joinedLabelText(account.joinedLabel)), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openProfile(context, ref, account),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Text(l10n.accountProfile), const Icon(Icons.chevron_right, size: 18)]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _AccountAction(icon: Icons.switch_account_outlined, label: l10n.accountManage, onTap: () => _showAccountSheet(context, ref)),
            _AccountAction(icon: Icons.edit_outlined, label: l10n.editProfile, onTap: () => _showEditProfile(context, account)),
            _AccountAction(icon: Icons.lock_outline, label: l10n.changePassword, onTap: () => _showChangePassword(context)),
            _AccountAction(icon: Icons.logout, label: l10n.logout, onTap: () => _confirmLogout(context, ref)),
          ],
        ),
      ],
    );
  }
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
        const CircleAvatar(radius: 32, child: Icon(Icons.person_outline, size: 32)),
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
        FilledButton(onPressed: () => context.push('/login'), child: Text(l10n.login)),
      ],
    );
  }
}

/// 站点给的加入时间是「加入於 3年前」这种自带前缀的文本，而本地文案里已经带了
/// 「加入于」，直接用会渲染成「加入于 加入於 3年前」，这里只取出时长部分。
String _joinedLabelText(String? label) => (label ?? '').replaceFirst(RegExp(r'^\s*(?:加入[于於]?|Joined)\s*'), '').trim();

/// 资料卡下方的一个账号操作（只染图标与文字，不用大面积底色）。
class _AccountAction extends StatelessWidget {
  const _AccountAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
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
  return showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => _AccountSheet(accounts: accounts, active: active));
}

/// 编辑个人资料（昵称 / 邮箱）—— 弹出对话框，保存后自动关闭。
Future<void> _showEditProfile(BuildContext context, Account account) => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.editProfile),
        content: SizedBox(width: 360, child: SingleChildScrollView(child: _ProfileForm(account: account, onDone: () => Navigator.pop(dialogContext)))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(dialogContext)!.cancel))],
      ),
    );

/// 更改密码 —— 同样弹对话框，保存后自动关闭。
Future<void> _showChangePassword(BuildContext context) => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.changePassword),
        content: SizedBox(width: 360, child: SingleChildScrollView(child: _PasswordForm(onDone: () => Navigator.pop(dialogContext)))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(dialogContext)!.cancel))],
      ),
    );

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.logout),
      content: Text(l10n.logoutConfirmation),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l10n.logout)),
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
                  child: item.avatarUrl?.isNotEmpty == true ? null : const Icon(Icons.person_outline),
                ),
                title: Text(item.name?.isNotEmpty == true ? item.name! : item.id ?? ''),
                subtitle: Text(item.email ?? item.id ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.id == active?.id) const Icon(Icons.check_circle),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: AppLocalizations.of(context)!.removeAccount,
                      onPressed: () async {
                        if (item.id == null) return;
                        await ref.read(accountProvider.notifier).remove(item);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
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
              leading: const Icon(Icons.person_add_alt_1_outlined),
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
  Widget build(BuildContext context) => Column(children: [TextField(controller: _name, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.username)), TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.email)), const SizedBox(height: 12), FilledButton(onPressed: () async { await ref.read(accountProvider.notifier).updateProfile(_name.text.trim(), _email.text.trim()); widget.onDone?.call(); }, child: Text(AppLocalizations.of(context)!.saveProfile))]);
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
  Widget build(BuildContext context) => Column(children: [TextField(controller: _old, obscureText: true, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.oldPassword)), TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.newPassword)), TextField(controller: _confirmation, obscureText: true, decoration: InputDecoration(labelText: AppLocalizations.of(context)!.confirmNewPassword)), const SizedBox(height: 12), FilledButton(onPressed: () async { await ref.read(accountProvider.notifier).updatePassword(_old.text, _password.text, _confirmation.text); widget.onDone?.call(); }, child: Text(AppLocalizations.of(context)!.changePassword))]);
}