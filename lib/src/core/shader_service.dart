import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;

import 'platform_paths.dart';

class ShaderService {
  ShaderService._();

  static Directory? directory;

  static Future<void> copyToStorage() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest
          .listAssets()
          .where((asset) => asset.startsWith('assets/shaders/') && asset.endsWith('.glsl'));
      // 用 appStorageDirectory 而不是 getApplicationSupportDirectory：后者在
      // Windows 上按 exe 的版本资源拼路径，会落到 %APPDATA%\Han1meWinPlus\Han1meWinPlus\
      // 那个历史目录里，与应用真正在用的 %APPDATA%\han1me_win_plus\ 分家。
      // 详见 platform_paths.dart 的说明。
      final target = Directory(p.join((await appStorageDirectory()).path, 'shaders'));
      await target.create(recursive: true);
      for (final asset in assets) {
        final file = File(p.join(target.path, p.basename(asset)));
        if (await file.exists()) continue;
        final data = await rootBundle.load(asset);
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      directory = target;
    } catch (_) {}
  }
}
