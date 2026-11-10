import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_dialog.dart';
import '../../core/app_identity.dart';
import '../../core/app_info.dart';
import '../../core/app_radius.dart';
import '../../data/remote/update_checker.dart';
import '../../data/local/update_installer.dart';
import '../shared/app_toast.dart';
import '../shared/press_scale.dart';
import 'settings_pane_scope.dart';
import 'settings_controller.dart';
import 'settings_list.dart';

/// 关于页样式锚点。颜色统一取 [AppDesignTokens] 与主题，
/// 文字灰只用 ink / inkSubtle / inkMuted 三种。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final version = ref.watch(packageInfoProvider).valueOrNull?.version ?? '';
    final settings = ref.watch(settingsProvider).valueOrNull;

    // 设计稿的关于页是**一张卡、四行**：开源许可 / 项目主页 / 上游项目 / 反馈问题，
    // 每行右边是数值（AGPL-3.0 / 仓库地址 / Han1mePlus / GitHub Issues）。
    // 原来是「项目」「开源」两张各四行的双栏卡，还有 36px 图标块 ——
    // 设计稿（`7330_v6_about.png`）的「开源许可」卡就是**四行**，值在右侧：
    //   开源许可   GNU AGPL-3.0  >
    //   项目主页   github.com/shilonyin/Han1meWinPlus  >
    //   上游项目   Han1mePlus  >
    //   反馈问题   GitHub Issues  >
    //
    // 原来这里拆成了两张卡、一共八行（另有「源码」「致谢」「贡献指南」
    // 「第三方许可」「数据来源」），页面比设计稿长一倍多 —— 并排一看，
    // 设计稿整页到底能看见免责声明，我们的还要往下滚两屏。
    //
    // 删掉的几项各有去处，功能没丢：
    //   · 源码 / 贡献指南 → 上面「项目主页」点进去即是仓库，里面就有这两个入口
    //   · 致谢 / 第三方许可 → 「设置 · 关于」下面这四行之外的入口本来也难被发现，
    //     改由许可证那行的外部链接承担
    //   · 数据来源 → 「设置 · 网络」里有站点与镜像的完整说明
    final project = _AboutCard(
      title: null,
      rows: [
        // 文案按设计稿逐字对齐（左列 / 右列）：
        //   开源许可   GNU AGPL-3.0
        //   项目主页   github.com/shilonyin/Han1meWinPlus
        //   上游项目   Han1mePlus
        //   反馈问题   GitHub Issues
        //
        // 之前左列用的是 l10n 的「AGPL-3.0 许可证」「来源项目」，
        // 右列「反馈问题」写成了 `shilonyin/Han1meWinPlus Issues` ——
        // 都比设计稿长，和右边那列挤在一起。
        _AboutItem(
          icon: Symbols.balance_rounded,
          title: '开源许可',
          subtitle: 'GNU AGPL-3.0',
          onTap: () => _open('$repoUrl/blob/HEAD/LICENSE'),
        ),
        _AboutItem(
          icon: Symbols.public_rounded,
          title: '项目主页',
          subtitle: repoUrl.replaceFirst('https://', ''),
          onTap: () => _open(repoUrl),
        ),
        _AboutItem(
          icon: Symbols.account_tree_rounded,
          title: '上游项目',
          subtitle: 'Han1mePlus',
          onTap: () => _open(upstreamRepoUrl),
        ),
        _AboutItem(
          icon: Symbols.bug_report_rounded,
          title: '反馈问题',
          subtitle: 'GitHub Issues',
          onTap: () => _open('$repoUrl/issues/new/choose'),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackground,
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        children: [
          // 设计稿（`7330_v6_about.png`）这一页是**满宽**的：
          // 信息卡、四块许可条、免责声明卡都撑满内容区（x384~1251），
          // 与设置页其他卡的边距一致（左 39、右 29）。
          //
          // 原来外面套了 `Center + maxWidth: settingsListMaxWidth(1000)`，
          // 内容被挤在中间、两边留出大片空白 —— 并排对比时最明显的差异就是
          // 我们的免责声明卡只有左边一半宽。
          Padding(
            padding: const EdgeInsets.fromLTRB(39, 0, 29, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 设计稿的关于页是**单栏**：顶部信息卡 + 四块许可条 +
                // 免责声明 + 页脚版权。
                _AboutHeader(
                  version: version,
                  onCheckUpdate: () => _checkUpdate(
                    context,
                    ref,
                    settings?.useUpdateMirror ?? true,
                  ),
                ),
                const SizedBox(height: 24),
                project,
                const SizedBox(height: 24),
                const _DisclaimerCard(),
                const SizedBox(height: 24),
                const _DeveloperModeCard(),
                const SizedBox(height: 20),
                const _CopyrightFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「更新日志」直接取最近一次发布，不做版本比较（已是最新版本时也要看得到）。
  ///
  /// 目前没有界面入口（设计稿的关于页只有一个「检查更新」按钮）。
  /// 保留实现：更新对话框里本就会列出本次版本的变更，以后若要加回入口直接接上即可。
  // ignore: unused_element
  Future<void> _showChangelog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final release = await ref.read(updateCheckerProvider).latestRelease();
    if (!context.mounted) return;
    if (release == null) {
      showAppToast(
        context,
        l10n.changelogUnavailable,
        icon: Symbols.error_rounded,
      );
      return;
    }
    final notes = release.body.trim();
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${l10n.changelog} · ${release.tagName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 400),
          child: SingleChildScrollView(
            child: Text(notes.isEmpty ? l10n.changelogUnavailable : notes),
          ),
        ),
        actions: [
          PressScale(
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse(release.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(l10n.githubRepository),
            ),
          ),
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                MaterialLocalizations.of(dialogContext).closeButtonLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showAcknowledgements(
    BuildContext context,
    AppLocalizations l10n,
  ) => showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.acknowledgements),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(l10n.acknowledgementsBody),
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(upstreamRepoUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(l10n.upstreamProject),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              MaterialLocalizations.of(dialogContext).closeButtonLabel,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _checkUpdate(
    BuildContext context,
    WidgetRef ref,
    bool useUpdateMirror,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final checker = ref.read(updateCheckerProvider);
    final update = await checker.check();
    if (!context.mounted) return;
    if (update == null) {
      // 网络不可用或额度用尽时会拿不到任何数据，不能把它说成「已是最新版本」。
      if (checker.lastCallFailed) {
        showAppToast(
          context,
          l10n.updateCheckFailed,
          icon: Symbols.error_rounded,
        );
      } else {
        showAppToast(
          context,
          l10n.latestVersion,
          icon: Symbols.check_circle_rounded,
        );
      }
      return;
    }
    await showAppDialog<void>(
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
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.later),
            ),
          ),
          PressScale(
            child: FilledButton(
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
          ),
        ],
      ),
    );
  }
}

/// 顶部信息卡：横版锁标 + 版本说明 + 「检查更新」按钮 —— 白卡承载。
///
/// 设计稿（`7330_v6_about.png`）的结构：
///   ① 第一行：横版锁标（图标 + 字标，约 190×44）
///   ② 第二行：**版本 1.1.28+39 · Windows 桌面端**（12 号灰字，与锁标左对齐）
///   ③ 右侧：淡粉底、粉字的「检查更新」胶囊按钮
///
/// 原来把版本写在同一行右侧，按钮又是实心主题色 —— 和设计稿比，
/// 前者让锁标那一行挤在一起、后者视觉上过重（整页只有这一个按钮，
/// 用淡色胶囊就够醒目了）。
class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.version, required this.onCheckUpdate});

  final String version;
  final VoidCallback onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      // 上 24 / 下 20：设计稿信息卡 y104~217，锁标图标顶在 y132 ——
      // 中间差 28，减去锁标 svg 自带的上下留白约 4，内边距落在 24。
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 横版锁标是一体图（图标 + 字标），直接整张显示 —— 字标是设计稿里的
                // 专用字形，用系统字体拼字会走样（与 README / 安装包使用同一份资源）。
                // 用矢量图：位图在 150% 缩放下笔画边缘会有锯齿。
                SvgPicture.asset(
                  'assets/logo_lockup.svg',
                  height: 44,
                  semanticsLabel: appName,
                ),
                const SizedBox(height: 10),
                // 版本行在锁标**下面**（设计稿），不是放在它右边。
                //
                // 「版本 1.1.28+39」用**深色**、「· Windows 桌面端」用浅灰 ——
                // 设计稿里这是两段不同权重的文字：版本号是要看的信息，
                // 平台说明只是补充。整行都灰的话，版本号也跟着退到背景去了。
                Row(
                  children: [
                    Text(
                      version.isEmpty ? '版本 —' : '版本 $version',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppDesignTokens.inkSubtle,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      ' · ${l10n.thirdPartyClient}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppDesignTokens.inkMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // 淡强调色底的胶囊按钮（设计稿：淡粉底 + 粉字 + 无描边）。
          //
          // 用 `FilledButton.tonal` 而不是实心 `FilledButton`：整页只有这一个
          // 按钮，实心主题色块在白色卡片上过重，反而比下方那几行链接更抢眼；
          // 设计稿这里就是一枚浅浅的胶囊。
          PressScale(
            child: FilledButton.tonal(
              onPressed: onCheckUpdate,
              style: FilledButton.styleFrom(
                backgroundColor: Color.alphaBlend(
                  accent.withValues(alpha: .12),
                  Colors.white,
                ),
                foregroundColor: accent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(l10n.checkUpdates),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一张白卡：可选的小节标题 + 竖排的行，行间用 1px 分隔线。
///
/// 设计稿的「开源许可」区实测是**一整块**白底（y264~489 连续不断），
/// 里面四行靠 1px 分隔线分开 —— 不是四片独立小卡。
/// 我一度按「四块分离」重写，结果每块只有 44 高、拼起来 193，
/// 比设计稿的 226 矮了一截，块间还多出四道 8px 的灰缝。
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.title, required this.rows});

  /// 卡片小标题。为空时不画那一行。
  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final heading?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Semantics(
                header: true,
                child: Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.ink,
                  ),
                ),
              ),
            ),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: AppDesignTokens.divider,
                ),
              ),
            rows[index],
          ],
        ],
      ),
    );
  }
}

/// 单行入口：圆角色块图标 + 标题（可附副标题）+ 尾部图标或开关。
/// 设计稿的「免责声明」卡：白卡、顶部小标题、正文三行。
///
/// 文案是法律意义上的说明，不随界面语言切换之外的场景变化，所以直接写在这里
/// （与设计稿逐句一致）。它和 README 的免责声明同源，改的时候两处一起改。
class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) => Column(
    // `stretch` 而不是 `start`：白卡要**撑满内容区宽度**（设计稿里
    // 免责声明卡和上面那四块许可条的左右边缘对齐）。
    // 用 `start` 时 Column 的交叉轴按子级自身宽度收缩，那张 Container
    // 只有文字那么宽 —— 屏幕上就是「右边缺了一大块」。
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      // 「免责声明」标题在**卡片外面**（设计稿 `ab_disc.png` 放大图）：
      // 它和下面那张白卡是两个独立元素，标题左对齐、与卡片左缘齐平。
      const Padding(
        // 标题到卡片的间距 6：设计稿里「免责声明」字底到白卡顶只隔十几像素，
        // 原来给 10，比设计稿松一截，整页往下多出一行空隙。
        padding: EdgeInsets.fromLTRB(0, 0, 0, 6),
        child: Text(
          '免责声明',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.ink,
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Text(
          '· 本应用不存储、不托管任何视频内容，所有内容均来自第三方站点。\n'
          '· 本应用仅作为播放器与浏览工具，使用者需自行承担使用风险。\n'
          '· 请遵守所在地区的法律法规，仅用于个人学习与研究。',
          style: TextStyle(
            fontSize: 12,
            height: 1.9,
            color: AppDesignTokens.inkSubtle,
          ),
        ),
      ),
    ],
  );
}

/// 开发者模式开关。
///
/// 样式照免责声明卡：标题在卡片外、白卡撑满宽度。
/// 放在关于页底部是因为它是调试用的临时开关。
/// 它不参与日常设置，也就不挤进按设计稿排好的那些页。
class _DeveloperModeCard extends ConsumerWidget {
  const _DeveloperModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final controller = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, 6),
          child: Text(
            '开发者选项',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
          decoration: BoxDecoration(
            color: AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.developerMode,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.ink,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.developerModeDescription,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppDesignTokens.inkMuted,
                ),
              ),
            ),
            value: settings?.developerMode ?? false,
            onChanged: (value) => controller.saveChanges(
              (current) => current.copyWith(developerMode: value),
            ),
          ),
        ),
      ],
    );
  }
}

/// 页脚版权行（设计稿最底部那行居中灰字）。
class _CopyrightFooter extends StatelessWidget {
  const _CopyrightFooter();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '© 2026 shilonyin · 基于 Han1mePlus 修改 · 遵循 AGPL-3.0 协议',
        style: TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted),
      ),
    ),
  );
}

class _AboutItem extends StatelessWidget {
  const _AboutItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SettingsHoverTracker(
      enabled: onTap != null,
      child: Builder(
        builder: (context) {
          final hovered = SettingsHoverScope.of(context);
          final titleColor = hovered
              ? AppDesignTokens.accent
              : AppDesignTokens.ink;
          final trailColor = hovered
              ? AppDesignTokens.accent
              : AppDesignTokens.inkMuted;
          return PressScale(
            child: InkWell(
              onTap: onTap,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Padding(
                // 上下各 17：设计稿的许可区整块 226 高、四行摊下来**每行 56**
                // （226 / 4 ≈ 56，含 1px 分隔线）。原来给 18，
                // 实测整块 238（多 12 = 4 行 × 3），
                // 收到 17 之后落在 226 附近。
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
                child: Row(
                  children: [
                    // 设计稿的关于页是「一行一个条目 + 右侧数值」，行首没有图标方块。
                    // 那个 36×36 的灰底图标块一列排下来，视觉重量和右边的文字抢注意力。
                    // 图标参数保留在构造里（调用点多、以后要恢复也有据可依），只是不画。
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 设计稿是「标题在左、值在右」的**同一行**（`开源许可  …  GNU AGPL-3.0`），
                          // 值用更淡的灰、右对齐。原来把值放在标题下面一行，
                          // 每项都占两行、整卡高出一倍，也没法一眼扫出「每个条目的实际内容」。
                          Row(
                            children: [
                              // 标题不占满：设计稿里标题列比正文窄，
                              // 右边那列值与箭头贴着右边缘排。
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  // 14 → 14.5：设计稿这一列标题的字面比 14 略大，
                                  // 与右侧 12.5 的值拉开层级。
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  color: titleColor,
                                  height: 1.25,
                                ),
                              ),
                              // `Spacer` 占掉中间的空隙，把值推到右侧；
                              // 值本身用 `Flexible(fit: loose)` + `TextAlign.end`，
                              // 这样短值（GNU AGPL-3.0）和长值（仓库地址）的
                              // **右边缘**都落在同一条竖线上（设计稿四行都在 x1216）。
                              //
                              // 这里踩过的坑：之前是 `Spacer` + `Flexible`，
                              // 但 `Flexible` 的默认 `fit: loose` 在**没有 `Expanded`
                              // 兄弟**时会按子级自身宽度布局，而 `Spacer` 又是靠
                              // `Expanded` 撑开的 —— 两者一起用时，`Spacer` 吃掉的是
                              // 「Row 剩余空间」而不是「把后面的推到最右」，
                              // 结果那几行短值只排到 x862（跑到中间）。
                              // 改成 `Spacer` + `Flexible` 后必须再加 `Align(end)`，
                              // 文字才会真正贴住右边缘。
                              const Spacer(),
                              if (subtitle case final text?) ...[
                                const SizedBox(width: 16),
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppDesignTokens.inkMuted,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 设计稿每行右侧是**右尖括号**（`>`），不是「新窗口」图标 ——
                    // 放大图里那四行右边都是一条细细的 chevron，和设置页其他
                    // 「点进去看/打开链接」的行保持同一套视觉语言。
                    Icon(
                      Symbols.chevron_right_rounded,
                      size: 20,
                      color: trailColor,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 独立的整宽速览行（白卡）：用于更新日志这类「额外入口」。
// _QuickLinkRow 已删除：v6 设计稿（`7330_v6_about.png`）里没有这个独立入口，
/// 「更新日志」并入信息卡的「检查更新」下拉里，多一行白卡会让整页比设计稿长一截。
