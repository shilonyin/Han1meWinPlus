import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/download.dart';
import '../../domain/models/video.dart';
import '../video/video_page.dart';

/// 分组名的展示文案：内置的默认分组用本地化文案，其余用用户存储的名字。
///
/// 文件夹卡片、分组详情页、分组设置弹窗都要这个判断，集中一份免得各写一遍漂移。
String localizedGroupName(DownloadGroup group, AppLocalizations l10n) =>
    group.id == 'default' && (group.name == 'Default' || group.name == 'Cached') ? l10n.cachedDownloads : group.name;

/// 一组任务占用的空间：优先用服务端给的总长，没拿到时退回已下载量。
int totalBytesOf(Iterable<DownloadTask> tasks) =>
    tasks.fold<int>(0, (sum, task) => sum + (task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes));

/// 把字节数写成「95.9 MB」这种紧凑形式。
///
/// 缓存管理里到处都是体积（分组卡、任务行、容量概览），统一一个口径；
/// 三位数以上不再保留小数，免得「406.3 MB」把行宽撑得比数字本身还宽。
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// 下载速度，缺省（0）时写「0 KB/s」而不是「0 B/s」——后者看起来像卡住了。
String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond <= 0 ? 0 : bytesPerSecond)}/s';

/// 把毫秒时间戳写成 `2026-09-18`；非法值返回空串（调用方据此决定要不要画）。
String formatDate(int milliseconds) {
  if (milliseconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// 已完成任务的副标题：「1080 · 310 MB · 2026-09-25」。
String taskDetailLine(DownloadTask task) {
  final bytes = task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes;
  final date = formatDate(task.updatedAt);
  return [
    if (task.quality.isNotEmpty) task.quality,
    if (bytes > 0) formatBytes(bytes),
    if (date.isNotEmpty) date,
  ].join(' · ');
}

/// 「N 个视频 · 共 X」，分组卡与容量概览共用。
String groupSummaryLine(AppLocalizations l10n, Iterable<DownloadTask> tasks) {
  final list = tasks.toList(growable: false);
  return l10n.cacheSummary(list.length, formatBytes(totalBytesOf(list)));
}

/// 任务是否算「进行中」（含暂停：暂停也是没下完、还占着这条缓存的状态）。
bool isActiveTask(DownloadTask task) =>
    task.status == DownloadStatus.queued ||
    task.status == DownloadStatus.downloading ||
    task.status == DownloadStatus.paused ||
    task.status == DownloadStatus.failed;

/// 任务状态对应的文案。
String taskStatusLabel(AppLocalizations l10n, DownloadStatus status) => switch (status) {
      DownloadStatus.queued => l10n.queued,
      DownloadStatus.downloading => l10n.downloading,
      DownloadStatus.completed => l10n.completed,
      DownloadStatus.failed => l10n.failed,
      DownloadStatus.paused => l10n.paused,
    };

/// 播放一条本地缓存。
///
/// 缓存页与文件夹页都要这个动作，放在这里共用：本地文件已被外部删掉时给一句
/// 提示，而不是让播放器去打开一个不存在的路径。
Future<void> openCachedVideo(BuildContext context, DownloadTask task) async {
  final path = task.localVideoPath;
  if (path == null || !File(path).existsSync()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.localVideoMissing)));
    }
    return;
  }
  final localVideo = VideoDetail(id: task.videoCode, title: task.title, coverUrl: task.coverUrl, sources: [VideoSource(quality: task.quality, url: path)], tags: const [], playlist: const [], related: const []);
  if (context.mounted) {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => VideoPage(id: task.videoCode, localVideo: localVideo)));
  }
}
