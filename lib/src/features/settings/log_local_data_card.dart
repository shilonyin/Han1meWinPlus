import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../core/platform_paths.dart';

/// 日志页底部那排「本地数据」卡：人脸缓存 / 观看历史 / 图片缓存。
///
/// 三张卡各自显示「条数（大号强调色）+ 文件名（灰）」——设计稿 `日志页 · v6`
/// 底部就是这个形态。数值**从实际落盘文件读**，不做示例数据：
/// 文件不存在时显示 0，用户一眼能看出「这台机器上有没有这份数据」。
///
/// 放在日志页是因为它是「运行环境与调试信息」的延伸：缓存文件也是排障时要看的东西
/// （例如「人脸缓存命中率低」就去看这个文件有多大）。
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
        // 三格放**同一张白卡**里（设计稿是这么画的）：每格单独一张卡会显得碎，
        // 也不符合「一个区块放一组相关数字」的做法。
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: _LocalDataCell(
                  label: '人脸缓存',
                  // 与 `FaceFocusService` 的 `_storeFile` 同名（那里是私有的）。
                  file: 'face_focus.json',
                  unit: '条',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _LocalDataCell(
                  label: '观看历史',
                  file: 'han1me_history.json',
                  unit: '条',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _LocalDataCell(
                  label: '图片缓存',
                  // 图片缓存索引文件名见 `app_image_cache.dart`。
                  file: 'han1me_images.json',
                  unit: '个文件',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单格「本地数据」：标签在上、大号数值在下、文件名最底。
///
/// 设计稿里这三格是**同一张白卡里的三列**（没有各自的边框与圆角）：
/// 每格单独一张卡会显得碎，也不符合设计稿「一个区块放一组相关数字」的做法。
/// 白卡本身由外层 [LogLocalDataSection] 提供，这里只画内容。
class _LocalDataCell extends StatelessWidget {
  const _LocalDataCell({
    required this.label,
    required this.file,
    required this.unit,
  });

  final String label;

  /// 应用数据目录下的文件名。
  final String file;

  /// 计量单位（「条」/「个文件」）。
  final String unit;

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _countEntries(file),
    builder: (context, snapshot) {
      final value = snapshot.data;
      return Column(
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
      );
    },
  );
}

/// 数一个 JSON 存储里的条目数。
///
/// 只做「读文件 → 数顶层键/数组元素」，不解析成强类型对象：这些文件结构各不相同，
/// 这里只想知道「有多少条」。文件不存在或坏了就返回 0，不抛 —— 这是信息展示，
/// 不该因为一个坏文件把整页打挂。
Future<int> _countEntries(String fileName) async {
  try {
    final base = await appStorageDirectory();
    final file = File(path.join(base.path, fileName));
    if (!await file.exists()) return 0;
    final decoded = jsonDecode(await file.readAsString());
    return switch (decoded) {
      Map<dynamic, dynamic>() => decoded.length,
      List<dynamic>() => decoded.length,
      _ => 0,
    };
  } catch (_) {
    return 0;
  }
}
