import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_identity.dart';

class UpdateInstaller {
  UpdateInstaller(this._dio);
  final Dio _dio;

  /// 单个源的下载超时。接收超时不能设太短：大文件在慢链路上只要还在稳定
  /// 收到数据就不该被判失败，它衡量的是「两次数据之间」的间隔，不是总时长。
  static const _connectTimeout = Duration(seconds: 10);
  static const _receiveTimeout = Duration(seconds: 30);

  Future<void> removeStaleUpdate() async {
    if (!Platform.isAndroid && !Platform.isWindows) return;
    try {
      final file = await _updateFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> downloadAndInstall(String url, ValueChanged<double?> onProgress, {bool useMirror = true}) async {
    final uri = Uri.tryParse(url.trim());
    final supportedAsset = Platform.isAndroid && path.extension(uri?.path ?? '').toLowerCase() == '.apk' ||
        Platform.isWindows && path.extension(uri?.path ?? '').toLowerCase() == '.exe';
    if (!supportedAsset) {
      final target = Uri.parse(url.trim().isEmpty ? '$repoUrl/releases/latest' : url);
      if (!await launchUrl(target, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open update URL');
      }
      return;
    }
    final update = await _updateFile();
    await update.parent.create(recursive: true);
    // 顺序按实测速度从快到慢排：直连 GitHub 在部分网络下只有 0.12 MB/s
    // （39.6MB 的包要 5.5 分钟），而镜像有 2.6~4.1 MB/s（10~15 秒）。
    // 原来把直连排在第一位，它并不失败、只是慢，于是永远轮不到镜像。
    final sources = [
      if (useMirror) ..._updateMirrors.map((mirror) => '$mirror$url'),
      url,
    ];
    Object? lastError;
    for (final source in sources) {
      try {
        await _dio.download(
          source,
          update.path,
          deleteOnError: true,
          options: Options(
            validateStatus: (status) => status != null && status >= 200 && status < 300,
            // 没有超时的话，一个卡住的慢连接会一直挂着，不会失败、也就不会
            // 切到下一个源；这里让它在 10s 内连上、30s 内没有新数据就放弃。
            connectTimeout: _connectTimeout,
            receiveTimeout: _receiveTimeout,
          ),
          onReceiveProgress: (received, total) => onProgress(total <= 0 ? null : received / total),
        );
        lastError = null;
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    if (Platform.isWindows) {
      await Process.start(update.path, const ['/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
      exit(0);
    }
    final result = await OpenFilex.open(update.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) throw StateError(result.message);
  }

  /// 更新镜像，**按实测速度与稳定性排序**（越快越靠前）。
  ///
  /// 实测（下载 GitHub release 的前 2~3MB，多轮取平均）：
  ///   v4  : 3.27 / 3.09 MB/s   最稳，两轮都接近 3 MB/s
  ///   cdn : 2.97 / 0.03 MB/s   快时很快，但会掉到几乎为 0
  ///   v6  : 0.52 / 0.11 MB/s   稳定地慢
  ///   主域: 0.27 / 0.26 MB/s   稳定地慢
  ///   直连: 0.06 / 3.05 MB/s   波动极大，作为最后的兜底
  /// 这些数字会随网络环境变化，改动前最好重新测一轮。
  static const _updateMirrors = [
    'https://v4.gh-proxy.org/',
    'https://cdn.gh-proxy.org/',
    'https://gh-proxy.org/',
    'https://v6.gh-proxy.org/',
  ];

  Future<File> _updateFile() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw StateError('Update directory is unavailable');
      return File(path.join(directory.path, 'updates', 'han1me-plus-update.apk'));
    }
    final directory = await getTemporaryDirectory();
    return File(path.join(directory.path, appName, 'updates', '$installerBaseName.exe'));
  }
}
