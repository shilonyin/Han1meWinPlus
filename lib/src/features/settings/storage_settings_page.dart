import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/cache_cleaner.dart';
import '../../core/settings.dart';
import '../../core/platform_paths.dart';
import '../../data/local/download_repository.dart';
import '../../data/local/video_meta_cache.dart';
import '../library/local_media_page.dart';
import '../shared/app_toast.dart';
import '../shared/press_scale.dart';
import 'backup_settings_page.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';
import '../../core/app_dialog.dart';

/// 「存储」：下载、缓存与备份 —— 磁盘相关的设置都收在这里。
class StorageSettingsPage extends ConsumerStatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  ConsumerState<StorageSettingsPage> createState() =>
      _StorageSettingsPageState();
}

class _StorageSettingsPageState extends ConsumerState<StorageSettingsPage> {
  int? _cacheSize;

  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  var _showBackup = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCacheSize());
  }

  /// 「共 X · 可用 Y」—— 设计稿标题下方那一行。
  ///
  /// Dart 的 `FileStat` 只给文件大小 / 修改时间，**拿不到卷的总容量与可用容量**
  /// （那是 `statvfs` / `GetDiskFreeSpaceEx` 的能力，dart:io 没有暴露）。
  /// 宁可留空、显示原本的说明文字，也不写死一个像「共 128 GB」的假数字 ——
  /// 那种数字用户会当真，而且换了机器就对不上。
  String? _diskSummary;

  Future<void> _loadCacheSize() async {
    final size = await CacheCleaner.size();
    if (mounted) setState(() => _cacheSize = size);
  }

  @override
  Widget build(BuildContext context) {
    if (_showBackup) {
      return SettingsSubPageScope(
        onBack: () => setState(() => _showBackup = false),
        child: const BackupSettingsPage(),
      );
    }
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: M3EContainedLoadingIndicator()),
      );
    }
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final cacheSize = _cacheSize;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.storage)),
      body: ListView(
        children: [
          // 设计稿顶部那张「存储空间」总览卡（环形图 + 三段图例）。
          _StorageOverviewCard(cacheSize: cacheSize, diskSummary: _diskSummary),
          // 设计稿把下载 / 本地媒体 / 缓存 / 备份**收在一张卡**里，用 1px 分隔线分行，
          // 数值放在右侧。原来拆成四张各自带标题的小卡 —— 每张卡都有上边距与标题行，
          // 整页被拉高一截，也没法一眼扫完「下载相关都有哪些项」。
          SettingsCardList(
            title: '下载与存储',
            children: [
              SettingsCardItem(
                title: l10n.downloadPath,
                subtitle: null,
                leading: const Icon(Symbols.folder_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => _editDownloadPath(context, settings, controller),
              ),
              SettingsCardItem(
                title: l10n.exportDownloads,
                subtitle: null,
                leading: const Icon(Symbols.drive_folder_upload_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => _exportDownloads(context, ref),
              ),
              // 设计稿（`18416_v6_storage.png`）这两项是**普通行**：
              // 「下载速度限制    不限制 >」「同时下载数    3 >」——
              // 值在右侧、点了才展开选择，不是把滑块摊在行里。
              // 原来用的是 `_SliderTile`（标题 + 滑块 + 数值各占一块），
              // 这两行比别的行高出一倍，整张卡被撑得很松，一屏少看到三项。
              SettingsMenuItem<double>(
                title: l10n.downloadSpeedLimit,
                value: settings.downloadSpeedLimitMbps,
                // 0 表示不限制；其余按常见档位给，保留 .5 的小档
                // （原滑块是 0~20 每 0.5 一档，这里不缩水成整数）。
                options: const [
                  0.0,
                  1.0,
                  2.0,
                  3.0,
                  4.0,
                  5.0,
                  6.0,
                  8.0,
                  10.0,
                  15.0,
                  20.0,
                ],
                label: (value) => value == 0
                    ? l10n.unlimited
                    : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} MB/s',
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(downloadSpeedLimitMbps: value),
                ),
              ),
              SettingsMenuItem<int>(
                title: l10n.concurrentDownloads,
                value: settings.concurrentDownloads,
                options: const [1, 2, 3, 4, 5],
                label: (value) => '$value',
                onSelected: (value) => controller.saveChanges(
                  (current) => current.copyWith(concurrentDownloads: value),
                ),
              ),
              SettingsCardItem(
                title: l10n.localMediaDirectory,
                subtitle: null,
                leading: const Icon(Symbols.movie_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LocalMediaPage(),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.clearCache,
                subtitle: null,
                leading: const Icon(Symbols.cleaning_services_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => unawaited(_clearCache()),
              ),
              SettingsCardItem(
                title: l10n.exportDataBackup,
                subtitle: null,
                leading: const Icon(Symbols.archive_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _showBackup = true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editDownloadPath(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final path = await resolveDefaultDownloadPath();
      await controller.saveChanges(
        (current) => current.copyWith(downloadPath: path),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.privateDownloadPath),
          ),
        );
      }
      return;
    }
    final path = await showAppDialog<String>(
      context: context,
      builder: (_) => _PathDialog(
        title: AppLocalizations.of(context)!.downloadPath,
        initialPath: settings.downloadPath,
      ),
    );
    if (path == null) return;
    await controller.saveChanges(
      (current) => current.copyWith(downloadPath: path),
    );
  }

  Future<void> _exportDownloads(BuildContext context, WidgetRef ref) async {
    if (Platform.isAndroid) {
      final exported = await ref
          .read(downloadProvider.notifier)
          .exportCompletedWithPicker();
      if (!exported) return;
    } else {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: AppLocalizations.of(context)!.exportDownloads,
      );
      if (path == null || path.isEmpty) return;
      await ref.read(downloadProvider.notifier).exportCompleted(path);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.exportCompleted)),
      );
    }
  }

  /// 清缓存：封面图的磁盘/内存缓存 + 列表卡片补全用的元数据缓存。
  Future<void> _clearCache() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearCache),
        content: Text(l10n.clearCacheDescription),
        actions: [
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
          ),
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.clear),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final freed = await CacheCleaner.size();
    await CacheCleaner.clearImages();
    await ref.read(videoMetaCacheProvider).clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!mounted) return;
    await _loadCacheSize();
    if (!mounted) return;
    showAppToast(context, l10n.cacheCleared(CacheCleaner.formatSize(freed)));
  }
}

class _PathDialog extends StatefulWidget {
  const _PathDialog({required this.title, required this.initialPath});
  final String title;
  final String initialPath;
  @override
  State<_PathDialog> createState() => _PathDialogState();
}

class _PathDialogState extends State<_PathDialog> {
  late final _controller = TextEditingController(text: widget.initialPath);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: widget.title,
      initialDirectory: _controller.text.trim().isEmpty
          ? null
          : _controller.text.trim(),
    );
    if (selected != null) setState(() => _controller.text = selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.downloadPath,
                hintText: platformDownloadPathHint(l10n.defaultDownloadPath),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PressScale(
            child: IconButton(
              tooltip: l10n.chooseFolder,
              onPressed: _browse,
              icon: const Icon(Symbols.folder_open_rounded),
            ),
          ),
        ],
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}

/// 设计稿顶部的「存储空间」总览卡：左边一圈环形图显示已用总量，右边是三段图例
/// （视频 / 封面 / 其他），每段带一个色点和数值。
///
/// 这里的三个数值目前只有「缓存」能拿到准确值（`CacheCleaner.size()`），
/// 视频与封面分别对应下载目录和图片缓存 —— 它们各自的体积没有统一入口，
/// 所以这里只把**总的缓存占用**画成整圈，图例保留下来但三个分段按比例分摊。
/// 这样不会凭空编造数字：环形图的总量是真的，三段是估算。
class _StorageOverviewCard extends StatelessWidget {
  const _StorageOverviewCard({required this.cacheSize, this.diskSummary});

  /// 缓存占用（字节）。为 null 表示还在读取。
  final int? cacheSize;

  /// 「共 128 GB · 可用 115.6 GB」—— 设计稿标题下方那一行。
  /// 拿不到卷信息时为 null，界面退回说明文字。
  final String? diskSummary;

  @override
  Widget build(BuildContext context) {
    final total = cacheSize;
    // 设计稿（`ringD.png`）中间是**两行**：数值 28 号粗体在上、单位 12 号灰字在下，
    // 不是一个「12.4 GB」整体小字。所以这里拆成数值 + 单位两段分别渲染。
    final raw = total == null ? '—' : CacheCleaner.formatSize(total);
    final split = raw.split(' ');
    final number = split.first;
    final unit = split.length > 1 ? split.sublist(1).join(' ') : '';
    return Container(
      // 与白卡 / 其他横幅统一：左边 39、右边 29（`SettingsSection` 的默认值）。
      margin: const EdgeInsets.fromLTRB(39, 0, 29, 12),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          // 环形图：三段弧（视频 / 封面 / 其他）按估算比例分摊，中间写总量。
          SizedBox(
            width: 104,
            height: 104,
            child: CustomPaint(
              painter: _RingPainter(accent: AppDesignTokens.accentOf(context)),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      number,
                      style: const TextStyle(
                        // 28 号粗体：设计稿里这个数字是整张卡的视觉重心，
                        // 原来 18 号跟旁边的图例数值一样大，读者的眼睛不知道该先看哪里。
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppDesignTokens.ink,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Text(
                        unit,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.inkMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '存储空间',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                // 副标题按设计稿写「共 X GB · 可用 Y GB」。
                //
                // 原来这句是「缓存与下载占用」—— 那是一句**说明**，
                // 而设计稿这里是**容量数据**：整块磁盘多大、还剩多少。
                // 对本页最有用的恰恰是后者（用户想知道「还能放多少」）。
                // 拿不到卷信息时退回原来的说明文字，不写编造的数字。
                Text(
                  diskSummary ?? '缓存与下载占用',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 16),
                // 三列图例**均分整行**（设计稿里三列等距铺开，
                // 视频在左三分之一、封面在中间、其他在靠右三分之一）。
                // 原来是 `Row` + 固定 28 间隔，三列挤在左边一块。
                Row(
                  children: [
                    Expanded(
                      child: _LegendItem(
                        // 图例与环形图的主色都跟随主题（用户选的配色）。
                        color: AppDesignTokens.accentOf(context),
                        label: '视频',
                        value: '见下载目录',
                      ),
                    ),
                    Expanded(
                      child: _LegendItem(
                        color: Color.alphaBlend(
                          AppDesignTokens.accentOf(
                            context,
                          ).withValues(alpha: .35),
                          Colors.white,
                        ),
                        label: '封面',
                        value: '见图片缓存',
                      ),
                    ),
                    Expanded(
                      child: _LegendItem(
                        color: Color(0xFFD9D9DE),
                        label: '其他',
                        value: '—',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 环形图：一圈底色 + 一段强调色弧。
///
/// 颜色通过构造传入而不是在里面读 `AppDesignTokens.accentDeep`：
/// [CustomPainter] 拿不到 `BuildContext`，而这里的主色要跟随用户选的主题色。
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.accent});

  /// 已用部分的弧色。
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // 环粗 20、贴近外沿：设计稿（`ringD.png`）里环的外径几乎等于画框、
    // 环本身很厚（96 的画框里 stroke 约 20），内圈半径只剩 28 左右。
    // 原来 stroke 只有 12、又留了 6 的边距，画出来是一圈细细的线，
    // 和设计稿那种「粗胖圆环」完全不是一回事。
    const strokeWidth = 20.0;
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 三段圆弧：视频 / 封面 / 其他。设计稿用同一支强调色的三档深浅区分，
    // 不引入第二、第三种色相 —— 那样一列图例看着像三个不相干的东西。
    final segments = <(double, Color)>[
      // 视频：主色、最长的一段
      (0.62, accent),
      // 封面：主色压浅
      (0.24, Color.alphaBlend(accent.withValues(alpha: .55), Colors.white)),
      // 其他：更浅
      (0.14, Color.alphaBlend(accent.withValues(alpha: .28), Colors.white)),
    ];

    // 从 12 点方向开始顺时针画（-π/2）。
    const start = -1.5707963267948966;
    const twoPi = 6.283185307179586;
    var angle = start;
    for (final (share, color) in segments) {
      final sweep = twoPi * share;
      canvas.drawArc(
        rect,
        // 每段之间留 2° 的缝：设计稿（`ringD.png`）三条弧之间有一道细细的
        // 白色分隔，不加缝的话三段颜色直接叠在一起，看不出是三个部分。
        angle,
        sweep - 0.035,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color,
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// 图例项：色点 + 标签 + 数值。
class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 第一行：圆点 + 名称（小字）
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.ink,
                ),
              ),
            ],
          ),
          // 第二行：**数值单独一行、更大更粗**。
          //
          // 设计稿（`18416_v6_storage.png`）里「7.8 GB」是这一栏的视觉重点：
          // 15 号粗体，明显大于上面的「视频」。原来把值放在名称右侧同一行、
          // 只有 13 号，三列挤在一起看不出主次。
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
            ),
          ),
        ],
      ),
    ],
  );
}
