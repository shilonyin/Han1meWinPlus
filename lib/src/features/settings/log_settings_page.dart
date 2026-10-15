import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_dialog.dart';
import '../../core/app_logger.dart';
import '../shared/app_toast.dart';
import '../shared/press_scale.dart';
import 'settings_card_list.dart';
import 'settings_pane_scope.dart';

/// 「日志」：查看、导出、清空应用日志。
///
/// 存在的理由很直接：这个应用是 GUI 子系统程序，从终端启动读不到 `debugPrint`，
/// 于是每次排查问题都要临时改代码埋诊断、重新编译、请用户复现。有了常驻日志之后，
/// 出问题时用户在这里点一下导出、把 zip 发过来就行。
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
    final size = _size;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context) ? null : AppBar(title: Text(l10n.logs)),
      body: ListView(children: [
        SettingsCardList(title: l10n.logs, children: [
          SettingsCardItem(
            title: l10n.exportLogs,
            subtitle: size == null ? l10n.logsDescription : l10n.logsUsage(_formatSize(size), _files.length),
            leading: const Icon(Symbols.ios_share_rounded),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () => unawaited(_export()),
          ),
          SettingsCardItem(
            title: l10n.openLogsFolder,
            subtitle: _folderPath(),
            leading: const Icon(Symbols.folder_open_rounded),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () => unawaited(_openFolder()),
          ),
          SettingsCardItem(
            title: l10n.clearLogs,
            subtitle: l10n.clearLogsDescription,
            leading: const Icon(Symbols.delete_sweep_rounded),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () => unawaited(_clear()),
          ),
        ]),
        if (_files.isNotEmpty)
          SettingsCardList(title: l10n.logFiles, children: [
            for (final file in _files)
              SettingsCardItem(
                title: file.uri.pathSegments.last,
                leading: const Icon(Symbols.description_rounded),
                trailing: Text(_formatSize(file.lengthSync()), style: Theme.of(context).textTheme.bodySmall),
                onTap: () => unawaited(_preview(file)),
              ),
          ]),
      ]),
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
    final name = 'han1me-logs-${DateTime.now().toIso8601String().substring(0, 19).replaceAll(RegExp(r'[:\-T]'), '')}.zip';
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
            child: SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          PressScale(child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(_l10n.close))),
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
          PressScale(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_l10n.cancel))),
          PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_l10n.clear))),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.instance.clear();
    await _reload();
    if (mounted) showAppToast(context, _l10n.logsCleared);
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
