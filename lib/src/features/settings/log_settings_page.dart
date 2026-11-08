import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_dialog.dart';
import '../../core/app_logger.dart';
import '../../core/app_radius.dart';
import '../shared/app_toast.dart';
import '../shared/press_scale.dart';
import 'log_local_data_card.dart';
import 'settings_pane_scope.dart';

/// 「日志」：查看、导出、清空应用日志。
///
/// 存在的理由很直接：这个应用是 GUI 子系统程序，从终端启动读不到 `debugPrint`，
/// 于是每次排查问题都要临时改代码埋诊断、重新编译、请用户复现。有了常驻日志之后，
/// 出问题时用户在这里点一下导出、把 zip 发过来就行。
///
/// 视觉按设计稿 `p_log.png`（1280×800）重做：白底卡片 + 圆角 16 + 三档文字灰，
/// 页头标题 19-20 Bold，日志正文用等宽字体。日志的读取/导出/清理逻辑原样保留。
class LogSettingsPage extends StatefulWidget {
  const LogSettingsPage({super.key});

  @override
  State<LogSettingsPage> createState() => _LogSettingsPageState();
}

class _LogSettingsPageState extends State<LogSettingsPage> {
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
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackground,
      appBar: embedded ? null : AppBar(title: Text(l10n.logs)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          _PageHeader(
            title: l10n.logs,
            subtitle: l10n.logsDescription,
            exportLabel: l10n.exportLogs,
            onExport: () => unawaited(_export()),
            // 分栏模式下标题与副标题由 `_SettingsPanes` 统一画，这里只留右侧的
            // 「导出」按钮 —— 否则会重复成两行同样的标题。
            showTitle: !embedded,
          ),
          const SizedBox(height: 20),
          _EnvironmentCard(files: _files, size: _size),
          const SizedBox(height: 20),
          // 设计稿在「运行环境」下面紧跟一块**最近日志**（时间 / 级别 / 正文的
          // 实时列表）。原来这一页只有「日志文件」列表 —— 用户想看刚刚发生了什么，
          // 还得先打开文件、再从头翻到尾，而且新日志不会自己出现。
          const _RecentLogsCard(),
          const SizedBox(height: 20),
          if (_files.isNotEmpty) ...[
            _LogFilesCard(
              files: _files,
              onPreview: (file) => unawaited(_preview(file)),
            ),
            const SizedBox(height: 20),
          ],
          _LogActionsCard(
            exportLabel: l10n.exportLogs,
            folderLabel: l10n.openLogsFolder,
            folderPath: _folderPath(),
            clearLabel: l10n.clearLogs,
            clearHint: l10n.clearLogsDescription,
            onExport: () => unawaited(_export()),
            onOpenFolder: () => unawaited(_openFolder()),
            onClear: () => unawaited(_clear()),
          ),
          const SizedBox(height: 20),
          // 设计稿底部那排「本地数据」卡（人脸缓存 / 观看历史 / 图片缓存）。
          // 数值来自实际落盘文件，没有的显示 0 —— 不写死示例数字。
          const LogLocalDataSection(),
        ],
      ),
    );
  }

  String _folderPath() => AppLogger.instance.directory?.path ?? '—';

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

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

  Future<void> _preview(File file) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      if (mounted) showAppToast(context, _l10n.logsFolderUnavailable);
      return;
    }
    if (!mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.uri.pathSegments.last),
        content: SizedBox(
          width: 720,
          height: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.6,
                color: AppDesignTokens.inkSubtle,
              ),
            ),
          ),
        ),
        actions: [
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l10n.close),
            ),
          ),
        ],
      ),
    );
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
  const _RecentLogsCard();

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

/// 页头：19-20 Bold 标题 + 说明灰 + 右侧「导出」主按钮。
class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.exportLabel,
    required this.onExport,
    this.showTitle = true,
  });

  final String title;
  final String subtitle;
  final String exportLabel;
  final VoidCallback onExport;

  /// 是否画左侧的标题 + 说明。嵌在设置分栏里时为 false（页头已由外层画过），
  /// 这时这一行只剩右边的「导出」按钮，右对齐。
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: showTitle
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        if (showTitle)
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
        if (showTitle) const SizedBox(width: 16),
        PressScale(
          child: Material(
            color: AppDesignTokens.accent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: onExport,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Symbols.ios_share_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      exportLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 白底圆角 16 卡片外壳。
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
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
  const _EnvironmentCard({required this.files, required this.size});

  final List<File> files;
  final int? size;

  @override
  Widget build(BuildContext context) {
    final engine = 'Flutter ${_flutterMajorMinor()}';
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('运行环境'),
          const SizedBox(height: 18),
          Wrap(
            spacing: 40,
            runSpacing: 18,
            children: [
              _EnvField(label: '版本', value: appLoggerVersionLabel),
              _EnvField(label: '系统', value: _platformLabel()),
              _EnvField(label: '引擎', value: engine),
              _EnvField(
                label: '日志',
                value: size == null
                    ? '—'
                    : '${_bytesLabel(size!)} · ${files.length} 个文件',
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

  static String _platformLabel() {
    final name = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    final pretty = switch (name) {
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => name,
    };
    return version.isEmpty ? pretty : '$pretty $version';
  }

  static String _bytesLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
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

/// 日志文件列表：白卡，等宽字体展示文件名与大小。
class _LogFilesCard extends StatelessWidget {
  const _LogFilesCard({required this.files, required this.onPreview});

  final List<File> files;
  final ValueChanged<File> onPreview;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardTitle('日志文件'),
              const Spacer(),
              _Pill(label: '全部'),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < files.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppDesignTokens.divider,
              ),
            _LogFileRow(file: files[i], onTap: () => onPreview(files[i])),
          ],
        ],
      ),
    );
  }
}

class _LogFileRow extends StatelessWidget {
  const _LogFileRow({required this.file, required this.onTap});

  final File file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = file.uri.pathSegments.last;
    String size = '';
    try {
      size = _formatSize(file.lengthSync());
    } catch (_) {
      size = '—';
    }
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              // 设计稿的日志文件行没有左侧图标：一行就是「文件名 … 大小 ›」。
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: AppDesignTokens.ink,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                size,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppDesignTokens.inkMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Symbols.chevron_right_rounded,
                size: 16,
                color: AppDesignTokens.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// 日志操作：导出 / 打开文件夹 / 清空，保持原有功能入口。
class _LogActionsCard extends StatelessWidget {
  const _LogActionsCard({
    required this.exportLabel,
    required this.folderLabel,
    required this.folderPath,
    required this.clearLabel,
    required this.clearHint,
    required this.onExport,
    required this.onOpenFolder,
    required this.onClear,
  });

  final String exportLabel;
  final String folderLabel;
  final String folderPath;
  final String clearLabel;
  final String clearHint;
  final VoidCallback onExport;
  final VoidCallback onOpenFolder;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('日志管理'),
          const SizedBox(height: 8),
          _ActionRow(
            icon: Symbols.ios_share_rounded,
            title: exportLabel,
            subtitle: null,
            onTap: onExport,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppDesignTokens.divider,
          ),
          _ActionRow(
            icon: Symbols.folder_open_rounded,
            title: folderLabel,
            subtitle: folderPath,
            onTap: onOpenFolder,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppDesignTokens.divider,
          ),
          _ActionRow(
            icon: Symbols.delete_sweep_rounded,
            title: clearLabel,
            subtitle: clearHint,
            onTap: onClear,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive
        ? AppDesignTokens.accentOf(context)
        : AppDesignTokens.ink;
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              // 设计稿的设置行没有左侧图标（见 `settings_card_list.dart` 的说明），
              // 这一卡是手写的 Row，所以单独去掉；文字与右侧箭头保持不变。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: accent,
                        height: 1.3,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.inkMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Symbols.chevron_right_rounded,
                size: 16,
                color: AppDesignTokens.inkMuted,
              ),
            ],
          ),
        ),
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
