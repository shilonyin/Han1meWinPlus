import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_dialog.dart';
import '../../core/app_logger.dart';
import '../../core/app_radius.dart';
import '../shared/app_toast.dart';
import '../shared/press_scale.dart';
import 'log_local_data_card.dart';
import 'settings_controller.dart';
import 'settings_pane_scope.dart';
import 'settings_sub_page.dart';

/// 「日志」：查看、导出、清空应用日志。
///
/// 存在的理由很直接：这个应用是 GUI 子系统程序，从终端启动读不到 `debugPrint`，
/// 于是每次排查问题都要临时改代码埋诊断、重新编译、请用户复现。有了常驻日志之后，
/// 出问题时用户在这里点一下导出、把 zip 发过来就行。
///
/// 视觉按设计稿 `p_log.png`（1280×800）重做：白底卡片 + 圆角 16 + 三档文字灰，
/// 页头标题 19-20 Bold，日志正文用等宽字体。日志的读取/导出/清理逻辑原样保留。
class LogSettingsPage extends ConsumerStatefulWidget {
  const LogSettingsPage({super.key});

  @override
  ConsumerState<LogSettingsPage> createState() => _LogSettingsPageState();
}

class _LogSettingsPageState extends ConsumerState<LogSettingsPage> {
  int? _size;
  List<File> _files = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final logger = AppLogger.instance;
    final files = await logger.files();
    final size = await logger.size();
    if (mounted) {
      setState(() {
        _files = files;
        _size = size;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final embedded = embeddedInSettingsPanes(context);
    // 设计稿第四格是「网络」：当前代理模式 + 内置 Hosts 是否启用。
    // 从设置里读真实值，不写死「直连」这类示例字符串。
    final settings = ref.watch(settingsProvider).valueOrNull;
    final networkLabel = settings == null
        ? '—'
        : '${_proxyLabel(settings.proxyMode)} · '
              '${settings.useBuiltInHosts ? '内置 Hosts 已启用' : '内置 Hosts 未启用'}';
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackground,
      appBar: embedded ? null : AppBar(title: Text(l10n.logs)),
      body: SettingsSubPageBody(child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          // 分栏模式下标题与右侧按钮由 `_SettingsPanes` 统一画在同一行；
          // 只有独立路由（窄窗 / 深链）才由本页自己画完整页头。
          if (!embedded)
            _PageHeader(title: l10n.logs, subtitle: l10n.logsDescription),
          const SizedBox(height: 20),
          _EnvironmentCard(
            files: _files,
            size: _size,
            networkLabel: networkLabel,
          ),
          const SizedBox(height: 20),
          // 设计稿在「运行环境」下面紧跟一块**最近日志**（时间 / 级别 / 正文的
          // 实时列表）。原来这一页只有「日志文件」列表 —— 用户想看刚刚发生了什么，
          // 还得先打开文件、再从头翻到尾，而且新日志不会自己出现。
          _RecentLogsCard(
            onExport: () => unawaited(_export()),
            onOpenFolder: () => unawaited(_openFolder()),
            onClear: () => unawaited(_clear()),
          ),
          const SizedBox(height: 20),
          // 设计稿底部那排「本地数据」卡（人脸缓存 / 观看历史 / 图片缓存）。
          // 数值来自实际落盘文件，没有的显示 0 —— 不写死示例数字。
          const LogLocalDataSection(),
        ],
      )),
    );
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  /// 与网络设置页三档按钮同一套措辞。
  static String _proxyLabel(String mode) => switch (mode) {
    'custom' => '自定义代理',
    'system' => '跟随系统',
    _ => '直连',
  };

  /// 导出成一个 zip。
  ///
  /// 打包而不是直接给 `.log`：轮转后的历史文件要一起交给开发者，单文件带不全。
  /// 内容在**写入时**就已经脱敏（见 [AppLogger.redact]），所以这里不必再过一遍。
  Future<void> _export() async {
    final bytes = await AppLogger.instance.exportZip();
    if (bytes.isEmpty) {
      if (mounted) showAppToast(context, _l10n.noLogsToExport);
      return;
    }
    final name =
        'han1me-logs-${DateTime.now().toIso8601String().substring(0, 19).replaceAll(RegExp(r'[:\-T]'), '')}.zip';
    final target = await FilePicker.platform.saveFile(
      dialogTitle: _l10n.exportLogs,
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: Uint8List.fromList(bytes),
    );
    if (!mounted) return;
    if (target == null) return;
    showAppToast(context, _l10n.logsExported);
  }

  Future<void> _openFolder() async {
    final directory = AppLogger.instance.directory;
    if (directory == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [directory.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [directory.path]);
      } else {
        await Process.run('xdg-open', [directory.path]);
      }
    } catch (_) {
      if (mounted) showAppToast(context, _l10n.logsFolderUnavailable);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.clearLogs),
        content: Text(_l10n.clearLogsDescription),
        actions: [
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_l10n.cancel),
            ),
          ),
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_l10n.clear),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.instance.clear();
    await _reload();
    if (mounted) showAppToast(context, _l10n.logsCleared);
  }
}

// ── 视觉组件 ────────────────────────────────────────────────────────

/// 设计稿的「最近日志」：白卡，标题行 + 一块等宽字体的实时列表。
///
/// 数据来自 [AppLogger.recent]（内存里的环形缓冲，最近 200 条）。
/// 用 `ValueListenableBuilder` 监听 `recentRevision` 重绘 ——
/// 有新日志时列表自己滚到底，用户不需要手动刷新。
///
/// 为什么读内存而不是读文件：落盘是异步排队的，刚发生的日志要晚一拍才写进去，
/// 而且每来一行都重读整个文件既慢又会让列表跳动。
class _RecentLogsCard extends StatelessWidget {
  const _RecentLogsCard({this.onExport, this.onOpenFolder, this.onClear});

  /// 设计稿只画了「全部」胶囊，导出 / 打开文件夹 / 清空没有位置。
  /// 这些是真实功能不能删，收进标题行右侧的一个小菜单里，既不占一行、
  /// 也不破坏设计稿的版面。
  final VoidCallback? onExport;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onClear;

  /// 最多显示多少行。设计稿那块面板大约 6 行高，再多就把下面的卡全挤出去了。
  static const _visible = 6;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppLogger.instance.recentRevision,
      builder: (context, _, __) {
        final all = AppLogger.instance.recent;
        // 取最后 N 条：列表是追加式的，最新的在最下面，
        // 屏幕上要看到的是「刚刚发生的那几条」。
        final entries = all.length > _visible
            ? all.sublist(all.length - _visible)
            : all;
        return _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题行：左「最近日志」、右「全部」胶囊（设计稿就是这样）。
              Row(
                children: [
                  Text(
                    '最近日志',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.ink,
                    ),
                  ),
                  const Spacer(),
                  _Pill(label: '全部'),
                  const SizedBox(width: 8),
                  // 「更多」里放导出 / 打开文件夹 / 清空 —— 设计稿没画这些，
                  // 但功能要留。用小菜单而不是再排一条卡，版面才和设计稿一致。
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: const Icon(
                      Symbols.more_horiz_rounded,
                      size: 18,
                      color: AppDesignTokens.inkMuted,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      switch (value) {
                        case 'export':
                          onExport?.call();
                        case 'folder':
                          onOpenFolder?.call();
                        case 'clear':
                          onClear?.call();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'export', child: Text('导出日志')),
                      PopupMenuItem(value: 'folder', child: Text('打开日志文件夹')),
                      PopupMenuItem(value: 'clear', child: Text('清空日志')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    '暂无日志。应用运行时的信息会实时出现在这里。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.inkMuted,
                    ),
                  ),
                )
              else
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 时间列：等宽字体、固定宽度，几行才对得齐
                        SizedBox(
                          width: 62,
                          child: Text(
                            entry.timeLabel,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppDesignTokens.inkMuted,
                            ),
                          ),
                        ),
                        // 级别列：警告与错误染色，扫一眼就能找到出问题的那几行
                        SizedBox(
                          width: 46,
                          child: Text(
                            entry.level.label,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: switch (entry.level) {
                                LogLevel.error => const Color(0xFFC62828),
                                LogLevel.warning => const Color(0xFFB26A00),
                                _ => AppDesignTokens.inkSubtle,
                              },
                            ),
                          ),
                        ),
                        // 正文列
                        Expanded(
                          child: Text(
                            entry.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.4,
                              color: AppDesignTokens.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// 「复制全部日志」主按钮。
///
/// 抽成公开组件是因为分栏模式下页头由 `_SettingsPanes` 统一画：标题、
/// 副标题和这个按钮必须在**同一行**，不能让子页自己另起一行画按钮。
/// 它自己读日志并写剪贴板，所以外层页头直接用它即可，不依赖页面状态。
class CopyLogsButton extends ConsumerWidget {
  const CopyLogsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PressScale(
      child: Material(
        color: AppDesignTokens.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => unawaited(_copyAll(context)),
          child: Padding(
            // 设计稿的页头按钮是纯粉底、无图标的紧凑胶囊；之前带一个分享
            // 图标、内边距偏大，和标题行比起来显得笨重。
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            child: Text(
              l10n.copyAllLogs,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _copyAll(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final buffer = StringBuffer();
    for (final file in await AppLogger.instance.files()) {
      try {
        buffer.writeln('=== ${file.uri.pathSegments.last} ===');
        buffer.writeln(await file.readAsString());
      } catch (_) {
        // 单个文件读失败不影响其它文件，跳过即可。
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      if (context.mounted) showAppToast(context, l10n.noLogsToExport);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showAppToast(context, l10n.copiedAllLogs);
  }
}

/// 页头：19-20 Bold 标题 + 说明灰 + 右侧「复制全部日志」主按钮。
///
/// 只在独立路由（窄窗 / 深链）里用。
/// 分栏模式下标题行由 `_SettingsPanes` 画。
/// `CopyLogsButton` 也在那一行，本页不再画页头。
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.inkMuted,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        const CopyLogsButton(),
      ],
    );
  }
}

/// 白底圆角 16 卡片外壳。
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppDesignTokens.stroke),
      ),
      child: child,
    );
  }
}

/// 运行环境：版本 / 系统 / 引擎 / 网络，纯静态信息展示。
class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.files,
    required this.size,
    required this.networkLabel,
  });

  final List<File> files;
  final int? size;
  final String networkLabel;

  @override
  Widget build(BuildContext context) {
    final engine = 'Flutter ${_flutterMajorMinor()}';
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('运行环境'),
          const SizedBox(height: 18),
          // 设计稿（`7468_v6_log.png`）是 **2×2 表格**：版本 / 系统 /
          // 引擎 / 网络，两列等宽、两行。原来用 `Wrap` 让四项随宽度乱排，
          // 第四项还写成「日志 1.38 MB · 1 个文件」—— 那是文件信息，
          // 不是运行环境，混在这张卡里层级不对。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _EnvField(label: '版本', value: appLoggerVersionLabel),
              ),
              Expanded(
                child: _EnvField(label: '系统', value: _platformLabel()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _EnvField(label: '引擎', value: engine),
              ),
              Expanded(
                child: _EnvField(label: '网络', value: networkLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _flutterMajorMinor() {
    // Flutter 版本号不在不额外引入依赖的范围内，这里给出稳定可读的占位写法。
    return '3.x · Dart 3.x';
  }

  static String _platformLabel() =>
      windowsVersionLabel(Platform.operatingSystemVersion, Platform.isWindows);
}

/// 把 Dart 给的系统版本串修正成正确的 Windows 版本名。
///
/// Win11 的 NT 内核版本仍是 10.0。
/// 英文 locale 下 ProductName 常写 "Windows 10 Pro"。
/// 只看字符串会把 Win11 认成 Win10。
/// 可靠的判据是 Build 号。
/// Build 大于等于 22000 即 Windows 11。
/// 22000 是 Win11 首个正式版。
/// 非 Windows 平台原样返回。
/// 抽成顶层函数是为了能被测试直接覆盖。
@visibleForTesting
String windowsVersionLabel(String raw, bool isWindows) {
  final cleaned = raw.trim().replaceAll('"', '');
  if (!isWindows) return cleaned;
  final match = RegExp(r'Build (\d+)').firstMatch(cleaned);
  final build = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  if (build < 22000) return cleaned;
  return cleaned.replaceFirst(RegExp(r'Windows 10'), 'Windows 11');
}

class _EnvField extends StatelessWidget {
  const _EnvField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppDesignTokens.inkMuted,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppDesignTokens.ink,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppDesignTokens.ink,
        height: 1.3,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppDesignTokens.fieldFill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppDesignTokens.inkMuted,
          height: 1.2,
        ),
      ),
    );
  }
}
