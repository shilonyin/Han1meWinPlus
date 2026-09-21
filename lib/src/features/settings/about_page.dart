import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_identity.dart';
import '../../core/app_info.dart';
import '../../data/remote/update_checker.dart';
import '../../data/local/update_installer.dart';
import '../shared/app_toast.dart';
import 'settings_controller.dart';
import 'settings_list.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final version = ref.watch(packageInfoProvider).valueOrNull?.version ?? '';
    final settings = ref.watch(settingsProvider).valueOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final project = _AboutSection(
      title: l10n.projectSection,
      children: [
        _AboutItem(icon: Icons.code, title: l10n.sourceCode, onTap: () => _open(repoUrl)),
        _AboutItem(icon: Icons.account_tree_outlined, title: l10n.upstreamProject, onTap: () => _open(upstreamRepoUrl)),
        _AboutItem(icon: Icons.bug_report_outlined, title: l10n.reportIssue, onTap: () => _open('$repoUrl/issues/new/choose')),
        _AboutItem(icon: Icons.language_outlined, title: l10n.dataSource, subtitle: l10n.dataSourceDescription, onTap: () => _open(dataSourceUrl)),
      ],
    );
    final openSource = _AboutSection(
      title: l10n.openSourceSection,
      children: [
        _AboutItem(icon: Icons.volunteer_activism_outlined, title: l10n.acknowledgements, inApp: true, onTap: () => _showAcknowledgements(context, l10n)),
        _AboutItem(icon: Icons.fork_right_outlined, title: l10n.contributing, onTap: () => _open('$repoUrl/pulls')),
        _AboutItem(icon: Icons.balance_outlined, title: l10n.agplLicense, onTap: () => _open('$repoUrl/blob/win/LICENSE')),
        _AboutItem(icon: Icons.description_outlined, title: l10n.thirdPartyLicenses, inApp: true, onTap: () => context.push('/settings/license')),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: settingsListMaxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AboutHeader(version: version, onCheckUpdate: () => _checkUpdate(context, ref, settings?.useUpdateMirror ?? true), onChangelog: () => _showChangelog(context, ref, l10n)),
                    const SizedBox(height: 26),
                    if (wide)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: project), const SizedBox(width: 16), Expanded(child: openSource)])
                    else ...[
                      project,
                      const SizedBox(height: 20),
                      openSource,
                    ],
                    const SizedBox(height: 16),
                    _AboutSection(
                      title: l10n.updateSection,
                      children: [
                        _AboutItem(
                          icon: Icons.autorenew_outlined,
                          title: l10n.autoCheckUpdates,
                          trailing: Switch(value: settings?.autoUpdate ?? true, onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(autoUpdate: value))),
                          onTap: () => ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(autoUpdate: !(settings?.autoUpdate ?? true))),
                        ),
                        _AboutItem(
                          icon: Icons.route_outlined,
                          title: l10n.useUpdateMirror,
                          subtitle: l10n.useUpdateMirrorDescription,
                          trailing: Switch(value: settings?.useUpdateMirror ?? true, onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(useUpdateMirror: value))),
                          onTap: () => ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(useUpdateMirror: !(settings?.useUpdateMirror ?? true))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「更新日志」直接取最近一次发布，不做版本比较（已是最新版本时也要看得到）。
  Future<void> _showChangelog(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final release = await ref.read(updateCheckerProvider).latestRelease();
    if (!context.mounted) return;
    if (release == null) {
      showAppToast(context, l10n.changelogUnavailable, icon: Icons.error_outline);
      return;
    }
    final notes = release.body.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${l10n.changelog} · ${release.tagName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 400),
          child: SingleChildScrollView(child: Text(notes.isEmpty ? l10n.changelogUnavailable : notes)),
        ),
        actions: [
          TextButton(onPressed: () => launchUrl(Uri.parse(release.htmlUrl), mode: LaunchMode.externalApplication), child: Text(l10n.githubRepository)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel)),
        ],
      ),
    );
  }

  Future<void> _showAcknowledgements(BuildContext context, AppLocalizations l10n) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.acknowledgements),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Text(l10n.acknowledgementsBody)),
          actions: [
            TextButton(onPressed: () => launchUrl(Uri.parse(upstreamRepoUrl), mode: LaunchMode.externalApplication), child: Text(l10n.upstreamProject)),
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel)),
          ],
        ),
      );

   Future<void> _checkUpdate(BuildContext context, WidgetRef ref, bool useUpdateMirror) async {
    final l10n = AppLocalizations.of(context)!;
    final checker = ref.read(updateCheckerProvider);
    final update = await checker.check();
    if (!context.mounted) return;
    if (update == null) {
      // 网络不可用或额度用尽时会拿不到任何数据，不能把它说成「已是最新版本」。
      if (checker.lastCallFailed) {
        showAppToast(context, l10n.updateCheckFailed, icon: Icons.error_outline);
      } else {
        showAppToast(context, l10n.latestVersion, icon: Icons.check_circle_outline);
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.newVersionAvailable(update.tagName)),
        content: Text(
          update.downloadUrl.isEmpty
              ? l10n.noInstallableApk
              : update.body.isEmpty
              ? l10n.newVersionReleased
              : update.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.later),
          ),
          FilledButton(
            onPressed: update.downloadUrl.isEmpty
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    await UpdateInstaller(Dio()).downloadAndInstall(
                      update.downloadUrl,
                      (_) {},
                      useMirror: useUpdateMirror,
                    );
                  },
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }
}

/// 顶部：应用名 / 版本 / 一句话简介 + 检查更新与更新日志按钮。
class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.version, required this.onCheckUpdate, required this.onChangelog});

  final String version;
  final VoidCallback onCheckUpdate;
  final VoidCallback onChangelog;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 横版锁标：图标在文字左侧（与 README / 安装包使用同一份资源）
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', width: 48, height: 48, filterQuality: FilterQuality.high),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appName, style: theme.textTheme.headlineMedium?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w700)),
                  if (version.isNotEmpty) ...[const SizedBox(height: 2), Text(version, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline))],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(l10n.thirdPartyClient, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 18),
        Row(
          children: [
            FilledButton.icon(onPressed: onCheckUpdate, icon: const Icon(Icons.refresh, size: 18), label: Text(l10n.checkUpdates)),
            const SizedBox(width: 8),
            TextButton(onPressed: onChangelog, child: Text(l10n.changelog)),
          ],
        ),
      ],
    );
  }
}

/// 一组带标题的卡片，仅首尾行使用大圆角，和设置页的分组样式一致。
class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Semantics(header: true, child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))),
        ),
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 4),
          _AboutRow(topRadius: index == 0 ? 16 : 4, bottomRadius: index == children.length - 1 ? 16 : 4, child: children[index]),
        ],
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.child, required this.topRadius, required this.bottomRadius});

  final Widget child;
  final double topRadius;
  final double bottomRadius;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius), bottom: Radius.circular(bottomRadius)),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
}

/// 单行入口：圆角色块图标 + 标题（可附副标题）+ 尾部图标或开关。
class _AboutItem extends StatelessWidget {
  const _AboutItem({required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.inApp = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// true 表示在应用内跳转（用右箭头），否则是外部链接（用新窗口图标）。
  final bool inApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: colorScheme.onSecondaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface)),
                  if (subtitle case final text?) ...[
                    const SizedBox(height: 2),
                    Text(text, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? Icon(inApp ? Icons.chevron_right : Icons.open_in_new, size: 18, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
