import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../data/local/local_media_repository.dart';
import '../../core/local_media_scanner.dart';
import '../shared/glass/glass_scroll_edge_bar.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_sub_page.dart';
import '../shared/press_scale.dart';
import '../video/video_page.dart';

/// 本地媒体库：扫描用户指定的目录，把里面的视频列出来直接播放。
///
/// 与在线视频是两条独立的来源——本地文件没有封面 / 作者 / 标签，
/// 列表只显示文件名解析出的标题，点开后走同一个播放页（传 localVideo）。
///
/// 视觉按 `p_localmedia` 设计稿重做：页头 19 Bold + 副标题、目录信息卡白底圆角 16、
/// 全部视频区标题与计数、白底圆角列表行（深色封面块 + 标题 + 元数据 + 播放圆钮）。
/// 目录扫描 / 文件打开逻辑保持原样，只改颜色、间距与排版。
class LocalMediaPage extends ConsumerStatefulWidget {
  const LocalMediaPage({super.key});

  @override
  ConsumerState<LocalMediaPage> createState() => _LocalMediaPageState();
}

class _LocalMediaPageState extends ConsumerState<LocalMediaPage> {
  var _scanning = false;

  Future<void> _pickDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: l10n.localMediaDirectory);
    if (selected == null) return;
    await _rescan(selected);
  }

  Future<void> _rescan(String directory) async {
    final controller = ref.read(settingsProvider.notifier);
    setState(() => _scanning = true);
    try {
      if (directory.isNotEmpty) await controller.saveChanges((current) => current.copyWith(localMediaDirectory: directory));
      await ref.read(localMediaRepositoryProvider).rescan(directory);
      await ref.read(localMediaRepositoryProvider).watchDirectory(directory);
      ref.invalidate(localMediaProvider);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final directory = settings?.localMediaDirectory ?? '';
    final entries = ref.watch(localMediaProvider).valueOrNull ?? const [];
    final bar = AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      leading: settingsSubPageBack(context),
      title: Text(l10n.localMedia),
    );
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackgroundOf(context),
      // 顶栏挂 g1455 的 scroll edge：列表滚到它下面时被模糊淡出。
      extendBodyBehindAppBar: true,
      appBar: glassScrollEdgeAppBar(bar),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, barExtent(bar) + 16, 24, 24),
        children: [
          // ── 页头：标题 + 副标题 ─────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('本地媒体', style: TextStyle(fontSize: 19.5, fontWeight: FontWeight.w700, color: AppDesignTokens.inkOf(context))),
              const SizedBox(width: 10),
              Text('从本机添加的视频', style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMutedOf(context))),
              const Spacer(),
              _AccentButton(icon: Symbols.add_rounded, label: l10n.localMediaPickDirectory, onPressed: _scanning ? null : _pickDirectory),
            ],
          ),
          const SizedBox(height: 16),

          // ── 目录信息卡 ─────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(color: AppDesignTokens.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.lg)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppDesignTokens.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: const Icon(Symbols.folder_rounded, size: 20, color: AppDesignTokens.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(directory.isEmpty ? l10n.localMediaHint : directory, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppDesignTokens.inkOf(context))),
                      const SizedBox(height: 4),
                      Text(_metaLabel(l10n, entries), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMutedOf(context))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SoftButton(icon: Symbols.refresh_rounded, label: l10n.localMediaRescan, onPressed: _scanning || directory.isEmpty ? null : () => _rescan(directory)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── 全部视频：标题 + 计数 ──────────────────────────────────
          Row(
            children: [
              Text('全部视频', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppDesignTokens.inkOf(context))),
              const SizedBox(width: 8),
              Text('共 ${entries.length} 个', style: TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMutedOf(context))),
            ],
          ),
          const SizedBox(height: 12),
          if (_scanning)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: M3EContainedLoadingIndicator()))
          else if (entries.isEmpty)
            _EmptyState(onPick: _scanning ? null : _pickDirectory, l10n: l10n)
          else
            ...entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MediaRow(
                    entry: entry,
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoPage(id: entry.id, localVideo: entry.toVideoDetail()))),
                  ),
                )),
        ],
      ),
    );
  }

  /// 目录卡副行：`128 个视频 · 42.6 GB`；未选目录时退化为提示语。
  static String _metaLabel(AppLocalizations l10n, List<LocalMediaEntry> entries) {
    if (entries.isEmpty) return l10n.localMediaHint;
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.fileSize);
    return '${entries.length} 个视频 · ${_formatSize(total)}';
  }
}

/// 单个本地视频行：白底圆角 16，深色封面块 + 标题/元数据 + 右侧播放圆钮。
class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.entry, required this.onOpen});

  final LocalMediaEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final name = entry.path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    final ext = dot <= 0 ? '' : name.substring(dot + 1).toUpperCase();
    return Material(
      color: AppDesignTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: PressScale(child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 封面块：本地无缩略图，用深色块 + 播放三角作占位。
              Container(
                width: 88,
                height: 50,
                decoration: BoxDecoration(color: AppDesignTokens.inkOf(context), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: const Icon(Symbols.play_arrow_rounded, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.title.isNotEmpty ? entry.title : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppDesignTokens.inkOf(context))),
                    const SizedBox(height: 5),
                    Text('${_formatSize(entry.fileSize)} · ${_formatDate(entry.modifiedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMutedOf(context))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (ext.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppDesignTokens.fieldFillOf(context), borderRadius: BorderRadius.circular(AppRadius.xs)),
                  child: Text(ext, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppDesignTokens.inkMutedOf(context))),
                ),
              const SizedBox(width: 14),
              PressScale(
                child: Material(
                  color: AppDesignTokens.accent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onOpen,
                    child: const SizedBox(width: 32, height: 32, child: Icon(Symbols.play_arrow_rounded, size: 18, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
    )));
  }
}

/// 空状态：图标 + 说明 + 选目录按钮，居中且友好。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick, required this.l10n});

  final VoidCallback? onPick;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppDesignTokens.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.lg)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppDesignTokens.fieldFillOf(context), borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Icon(Symbols.video_library_rounded, size: 30, color: AppDesignTokens.inkMutedOf(context)),
          ),
          const SizedBox(height: 16),
          Text(l10n.localMediaEmpty, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppDesignTokens.inkSubtleOf(context))),
          const SizedBox(height: 18),
          _AccentButton(icon: Symbols.folder_open_rounded, label: l10n.localMediaPickDirectory, onPressed: onPick),
        ],
      ),
    );
  }
}

/// 主按钮：accent 实底、白字、圆角 10。
class _AccentButton extends StatelessWidget {
  const _AccentButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return PressScale(
      enabled: enabled,
      child: Material(
        color: enabled ? AppDesignTokens.accent : AppDesignTokens.fieldFillOf(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: enabled ? Colors.white : AppDesignTokens.inkMutedOf(context)),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: enabled ? Colors.white : AppDesignTokens.inkMutedOf(context))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 次按钮：fieldFill 底、inkSubtle 字、无描边，与设计稿「重新扫描」一致。
class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? AppDesignTokens.inkSubtleOf(context) : AppDesignTokens.inkMutedOf(context);
    return PressScale(
      enabled: enabled,
      child: Material(
        color: AppDesignTokens.fieldFillOf(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 文件大小：B / KB / MB / GB，保一位小数。
String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return unit == 0 ? '${size.round()} ${units[unit]}' : '${size.toStringAsFixed(1)} ${units[unit]}';
}

/// 修改时间：MM-DD。
String _formatDate(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$month-$day';
}
