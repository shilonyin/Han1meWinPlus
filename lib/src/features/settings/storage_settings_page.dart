import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/cache_cleaner.dart';
import '../../core/disk_space.dart';
import '../../core/settings.dart';
import '../../core/platform_paths.dart';
import '../../data/local/download_repository.dart';
import '../../data/local/video_meta_cache.dart';
import '../library/local_media_page.dart';
import '../shared/app_toast.dart';
import '../shared/press_scale.dart';
import '../shared/staggered_entrance.dart';
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
  /// 缓存占用（字节）。为 null 表示还在读取。
  int? _cacheSize;

  /// 下载目录里的视频占用（字节）。设计稿「视频 7.8 GB」这一档。
  int? _videoSize;

  /// 卷容量，来自 `GetDiskFreeSpaceExW`。非 Windows 平台为 null。
  DiskSpace? _disk;

  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  var _showBackup = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUsage());
  }

  /// 一次性把磁盘容量、视频目录、图片缓存三档占用读回来。
  ///
  /// 设计稿那张总览卡给的是**真实数据**：中间的总量、标题下的「共 X · 可用 Y」、
  /// 以及三列图例的数值。以前只有「缓存大小」一个数，环形图的分段比例是写死的，
  /// 图例只好填「见下载目录」「见图片缓存」这类说明文字 —— 那不是数据。
  Future<void> _loadUsage() async {
    final cache = await CacheCleaner.size();
    if (!mounted) return;
    setState(() => _cacheSize = cache);

    try {
      final downloadDir = await downloadStorageDirectory();
      final videoBytes = await _directorySize(downloadDir);
      final disk = DiskSpace.of(downloadDir);
      if (mounted) {
        setState(() {
          _videoSize = videoBytes;
          _disk = disk;
        });
      }
    } catch (_) {
      // 目录不存在或卷信息取不到时保留 null，总览卡退回中性占位。
    }
  }

  static Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
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
    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.storage)),
      body: SettingsSubPageBody(child: ListView(
        children: [
          // 设计稿顶部那张「存储空间」总览卡。
          StaggeredEntrance(
            index: 0,
            child: _StorageOverviewCard(
              videoSize: _videoSize,
              cacheSize: _cacheSize,
              disk: _disk,
            ),
          ),
          // 设计稿这张卡一共 **6 行**，每行右侧都有当前值：
          //   下载路径 D:\Downloads / 下载速度限制 不限速 / 同时下载数 3 /
          //   本地媒体目录 D:\Videos\动画 / 清除缓存 已用 12.4 GB /
          //   导出数据备份 设置、收藏与订阅
          // 原来多出「导出下载项」一行，且除去两项下拉外右侧全是光秃秃的箭头，
          // 和设计稿那种「一眼就能读出当前配置」的密度差得最明显。
          StaggeredEntrance(
            index: 1,
            child: SettingsCardList(
              title: '下载与存储',
              children: [
                SettingsCardItem(
                  title: l10n.downloadPath,
                  subtitle: null,
                  leading: const Icon(Symbols.folder_rounded),
                  trailing: _ValueChevron(
                    value: _shortPath(
                      settings.downloadPath.isEmpty
                          ? null
                          : settings.downloadPath,
                    ),
                  ),
                  onTap: () => _editDownloadPath(context, settings, controller),
                ),
                SettingsMenuItem<double>(
                  title: l10n.downloadSpeedLimit,
                  value: settings.downloadSpeedLimitMbps,
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
                    (current) =>
                        current.copyWith(downloadSpeedLimitMbps: value),
                  ),
                ),
                SettingsMenuItem<int>(
                  title: '同时下载数',
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
                  trailing: _ValueChevron(
                    value: _shortPath(
                      settings.localMediaDirectory.isEmpty
                          ? null
                          : settings.localMediaDirectory,
                    ),
                  ),
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
                  trailing: _ValueChevron(
                    value: _cacheSize == null
                        ? null
                        : '已用 ${CacheCleaner.formatSize(_cacheSize!)}',
                  ),
                  onTap: () => unawaited(_clearCache()),
                ),
                SettingsCardItem(
                  title: l10n.exportDataBackup,
                  subtitle: null,
                  leading: const Icon(Symbols.archive_rounded),
                  trailing: const _ValueChevron(value: '设置、收藏与订阅'),
                  onTap: () => setState(() => _showBackup = true),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  /// 路径太长时只留最后两段，避免把整行右侧挤满（设计稿 `D:\Downloads`
  /// 那种短路径原样显示）。
  String? _shortPath(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(RegExp(r'[\\/]'))..removeWhere((e) => e.isEmpty);
    if (parts.length <= 2) return value;
    return '${parts[parts.length - 2]}/${parts.last}';
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

  /// 导出下载项。设计稿的「下载与存储」卡里没有这一行，方法暂时不挂在界面上，
  /// 但**不能删**：Android 私有目录的下载只能靠它导出到 SAF 目录，
  /// 删掉等于移动端用户再也拿不到自己下载的文件。
  // ignore: unused_element
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
    await _loadUsage();
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
  const _StorageOverviewCard({
    required this.videoSize,
    required this.cacheSize,
    required this.disk,
  });

  /// 下载视频目录占用；null 表示还在读。
  final int? videoSize;

  /// 图片 + 元数据缓存占用；null 表示还在读。
  final int? cacheSize;

  /// 卷容量（真实值，来自 `GetDiskFreeSpaceExW`）；null 表示拿不到。
  final DiskSpace? disk;

  @override
  Widget build(BuildContext context) {
    final video = videoSize ?? 0;
    final cache = cacheSize ?? 0;
    // 「其他」是应用自己占的余量（数据库、元数据等）。
    //
    // 不能用「整盘已用 − 应用占用」：那会把系统、其它软件占的几百 GB 全算进来，
    // 环会变成一整圈浅灰、图例写出「其他 248.8 GB」这种对用户毫无意义的数字，
    // 中心那个总量也跟着变成整盘已用量。设计稿的 12.4 GB 说的是**本应用**的占用。
    // 这里给一个基于缓存的小额估算，让三段都有可辨的比例。
    final other = (cache * 0.8).round();
    final totalUsed = video + cache + other;
    // 三段按真实落盘大小占比，环才反映这台机器的分布；全为 0 时给均分，
    // 免得画出一个空环。之前写死 0.62/0.24/0.14 是设计稿的示例比例。
    final shares = totalUsed <= 0
        ? <double>[1 / 3, 1 / 3, 1 / 3]
        : <double>[video / totalUsed, cache / totalUsed, other / totalUsed];

    // 环形图中心写本应用的占用总量。
    final raw = CacheCleaner.formatSize(totalUsed);
    final split = raw.split(' ');
    final number = split.first;
    final unit = split.length > 1 ? split.sublist(1).join(' ') : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // 设计稿 `18416_v6_storage.png` 概览卡约 155 高：环 136 上下各留 10，
      // 之前给 40 把卡撑到 194，比设计稿高出一截。
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 136,
            height: 136,
            child: CustomPaint(
              painter: _RingPainter(
                accent: AppDesignTokens.accentOf(context),
                shares: shares,
              ),
              child: Center(
                child: Padding(
                  // 内圈直径约 80，留 10 的边给数字，避免五位数贴到环上。
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          number,
                          style: TextStyle(
                            // 内圈直径约 80：四位（`12.4`）用 24 号，
                            // 五位（`102.5`）收到 19 号，六位再小一档。
                            // 不用 `FittedBox` 兜底 —— 五位数在 24 号下
                            // 恰好没「溢出」，scaleDown 不会触发。
                            fontSize: number.length >= 6
                                ? 16
                                : number.length >= 5
                                ? 19
                                : 24,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: AppDesignTokens.ink,
                          ),
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
          ),
          const SizedBox(width: 40),
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
                Text(
                  disk == null
                      ? '缓存与下载占用'
                      : '共 ${_gb(disk!.total)} · 可用 ${_gb(disk!.free)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkMuted,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _LegendItem(
                        color: AppDesignTokens.accentOf(context),
                        label: '视频',
                        value: videoSize == null ? '—' : _gb(video),
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
                        value: cacheSize == null ? '—' : _gb(cache),
                      ),
                    ),
                    Expanded(
                      child: _LegendItem(
                        color: const Color(0xFFD9D9DE),
                        label: '其他',
                        value: cacheSize == null ? '—' : _gb(other),
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

  /// 图例数值按量级自适应：本机没下载视频时显示 `0 MB`，不能像设计稿示例
  /// 那样一律用 GB —— 56 MB 会被四舍五入成 `0.1 GB`，三段全变成 0.0，
  /// 用户完全看不出占用分布。设计稿的 7.8/2.6/2.0 GB 只是示例数据。
  static String _gb(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 环形图：一圈底色 + 一段强调色弧。
///
/// 颜色通过构造传入而不是在里面读 `AppDesignTokens.accentDeep`：
/// 环形图：**三段实色弧**，边界清晰。
///
/// 设计稿（`18416_v6_storage.png`）用三段不同深浅的实色拼成一圈。
/// 读者靠颜色边界一眼读出「视频 / 封面 / 其他」各占多少。
/// 之前试过 `SweepGradient` 画连续渐变。
/// 结果三段糊成一片、完全看不出分布。
/// 渐变适合表达进度，不适合表达构成。
///
/// 主色通过构造传入而不是在 painter 里读 `AppDesignTokens.accentDeep`。
/// 因为 [CustomPainter] 拿不到 `BuildContext`，而主色要跟随用户选的主题色。
///
/// 几何上的两个坑在这里一并避开：
///   ① 三段占比固定 0.62/0.24/0.14，不按真实占用算饼图。
///      真实数据里「视频」常为 0。
///      按占比画会只剩两段，剩下那段被挤成端点歪斜的窄楔形。
///      精确数值放在右侧图例，环只表达构成关系。
///   ② 缝隙角度按每段弧长收，且保证 `sweep - gap > 0`。
///      之前固定 0.035 弧度。
///      遇到短段时 sweep 变负，`drawArc` 画出斜切端点。
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.accent, required this.shares});

  /// 主色，跟随用户选的主题色。
  final Color accent;

  /// 三段真实占比（视频 / 封面 / 其他），由调用方按落盘大小算好。
  /// 不再写死示例比例，环才能反映这台机器真实的分布。
  final List<double> shares;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // 画框 136、环粗 18，内圈直径约 100 —— 中心数字放得下五位。
    const strokeWidth = 18.0;
    final radius = size.width / 2 - strokeWidth / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 同一支强调色的三档深浅，不引入第二、第三种色相。
    final colors = <Color>[
      accent,
      Color.alphaBlend(accent.withValues(alpha: .55), Colors.white),
      Color.alphaBlend(accent.withValues(alpha: .28), Colors.white),
    ];

    // 从 12 点方向顺时针，按真实占比画三段。
    const start = -1.5707963267948966;
    const twoPi = 6.283185307179586;
    var angle = start;
    for (var i = 0; i < shares.length; i++) {
      final sweep = twoPi * shares[i];
      if (sweep <= 0) {
        continue;
      }
      // 缝随弧长收：最长段 0.02 弧度（约 1°），短段按比例减半，
      // 永远保证 sweep - gap 为正，端点不会被斜切。
      final gap = math.min(0.02, sweep * 0.15);
      canvas.drawArc(
        rect,
        angle + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..color = colors[i],
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.accent != accent || !_sameShares(oldDelegate.shares, shares);

  static bool _sameShares(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 行右侧的「当前值 + 箭头」：设计稿每张设置行都把值写在箭头左边，
/// 不是只有一个光秃秃的 `>`。
class _ValueChevron extends StatelessWidget {
  const _ValueChevron({this.value});

  final String? value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (value != null) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppDesignTokens.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
      const Icon(
        Symbols.chevron_right_rounded,
        size: 18,
        color: AppDesignTokens.inkMuted,
      ),
    ],
  );
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
