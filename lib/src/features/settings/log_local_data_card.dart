import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/platform_paths.dart';

/// 日志页底部那排「本地数据」卡：人脸缓存 / 观看历史 / 图片缓存。
///
/// 三张卡各自显示「条数（大号强调色）+ 文件名（灰）」。
/// 这是设计稿 `日志页 · v6` 底部的形态。
/// 数值从实际落盘文件读，不做示例数据：文件不存在时显示 0。
/// 用户一眼能看出「这台机器上有没有这份数据」。
///
/// 放在日志页是因为它是「运行环境与调试信息」的延伸。
/// 缓存文件也是排障时要看的东西。
/// 例如「人脸缓存命中率低」就去看这个文件有多大。
class LogLocalDataSection extends StatelessWidget {
  const LogLocalDataSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '本地数据',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
            ),
          ),
        ),
        // 设计稿（`7468_v6_log.png`）底部是**三张各自带圆角的小白卡**，
        // 每张一个指标：标签 / 大号数值 / 文件名。原来把它们塞进同一张
        // 大白卡的三列里，卡片边界没了，看起来像一整块表格而不是三张数据卡。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(
              child: _LocalDataTile(
                label: '人脸缓存',
                // 与 `FaceFocusService` 的 `_storeFile` 同名（那里是私有的）。
                file: 'face_focus.json',
                unit: '条',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _LocalDataTile(
                label: '观看历史',
                // 观看记录落在 `watch_store.json`（见 `WatchController._save`），
                // 不是 `han1me_history.json` —— 之前写错文件名导致永远显示 0。
                // 而且这个文件是 `{continueItems, histories}` 两个键的 Map，
                // 真正的条数在 `histories` 数组里，得用 `countKey` 单独取。
                file: 'watch_store.json',
                countKey: 'histories',
                unit: '条',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _LocalDataTile(
                label: '图片缓存',
                // 图片缓存索引文件名见 `app_image_cache.dart`。
                file: 'han1me_images.json',
                unit: '个文件',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单张「本地数据」小卡：自带白底圆角，标签 / 大号数值 / 文件名三段。
///
/// 设计稿里这三张是**独立的白卡**（各自有圆角与边距），不是同一张卡的三列。
class _LocalDataTile extends StatelessWidget {
  const _LocalDataTile({
    required this.label,
    required this.file,
    required this.unit,
    this.countKey,
  });

  final String label;

  /// 应用数据目录下的文件名。
  final String file;

  /// 计量单位（「条」/「个文件」）。
  final String unit;

  /// 顶层 Map 里代表「条目列表」的那个键。
  ///
  /// 多数存储顶层就是条数本身（Map 的键数 / 数组长度）；但 `watch_store.json`
  /// 是 `{continueItems, histories}` 两个键的 Map，条数在 `histories` 里。
  /// 指定它才不会把「2 个键」误当成「2 条观看历史」。
  final String? countKey;

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _countEntries(file, countKey),
    builder: (context, snapshot) {
      final value = snapshot.data;
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.inkSubtle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value == null ? '—' : '$value $unit',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                // 数值用主题色（跟随用户选的配色，见 `AppDesignTokens.accentOf`）。
                color: AppDesignTokens.accentOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              file,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppDesignTokens.inkMuted,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 数一个 JSON 存储里的条目数。
///
/// 只做「读文件 → 数顶层键/数组元素」，不解析成强类型对象：这些文件结构各不相同，
/// 这里只想知道「有多少条」。文件不存在或坏了就返回 0，不抛 —— 这是信息展示，
/// 不该因为一个坏文件把整页打挂。
///
/// [countKey] 用于顶层是「包了一层」的 Map：取该键对应的数组长度。
/// 例如 `watch_store.json` 的 `histories`，而不是那两个顶层键的数量。
Future<int> _countEntries(String fileName, String? countKey) async {
  try {
    final base = await appStorageDirectory();
    final file = File(path.join(base.path, fileName));
    if (!await file.exists()) return 0;
    return countFromDecoded(jsonDecode(await file.readAsString()), countKey);
  } catch (_) {
    return 0;
  }
}

/// 从已解码的 JSON 里数条目（抽出来给测试直接验证结构与 `countKey`）。
///
/// 顶层是数组或 Map 时数其长度；指定 [countKey] 时只取该键的数组长度。
/// 任何形状不对的情况都返回 0，不抛。
@visibleForTesting
int countFromDecoded(Object? decoded, String? countKey) {
  if (countKey case final key?) {
    final nested = decoded is Map ? decoded[key] : null;
    return nested is List ? nested.length : 0;
  }
  return switch (decoded) {
    Map<dynamic, dynamic>() => decoded.length,
    List<dynamic>() => decoded.length,
    _ => 0,
  };
}
