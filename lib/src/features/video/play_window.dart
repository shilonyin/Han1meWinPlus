import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../settings/settings_controller.dart';

/// 独立播放窗口（多进程多窗口方案）的启动参数与进程启动器。
///
/// b 站客户端式的多窗口播放：点击封面不是在主窗口里 push 播放页，而是再拉起
/// 一个本程序自己的进程，只渲染播放页。之所以用**多进程**而不是
/// desktop_multi_window 的多引擎，是因为后者与手写 runner 不兼容——副窗口一
/// 创建，主窗口的引擎就不再处理输入 / 重绘（见 windows/runner/main.cpp 的
/// NOTE）；独立进程各有各的引擎与消息循环，互不影响，也天然支持同时开多个
/// 播放窗口。runner 侧对 `--play-window` 启动会跳过单实例互斥（见
/// IsPlayWindowLaunch），所以播放窗口与主窗口、以及播放窗口彼此之间都能并存。
const String kPlayWindowFlag = '--play-window';
const String _kVideoArgumentPrefix = '--video=';

/// 播放窗口进程的启动参数（`han1me.exe --play-window --video=<id>`）。
class PlayWindowArgs {
  const PlayWindowArgs({required this.videoId});

  final String videoId;

  /// 从命令行参数里解析播放窗口请求；不是播放窗口启动（缺 flag 或缺视频 id）
  /// 就返回 null，走主应用流程。
  static PlayWindowArgs? fromArguments(List<String> arguments) {
    var isPlayWindow = false;
    String? videoId;
    for (final argument in arguments) {
      if (argument == kPlayWindowFlag) {
        isPlayWindow = true;
      } else if (argument.startsWith(_kVideoArgumentPrefix)) {
        videoId = argument.substring(_kVideoArgumentPrefix.length);
      }
    }
    if (!isPlayWindow || videoId == null || videoId.isEmpty) return null;
    return PlayWindowArgs(videoId: videoId);
  }
}

/// 拉起一个独立播放窗口进程；成功返回 true。
///
/// [workingDirectory] 必须指向 exe 所在目录：runner 用相对路径 `data` 加载
/// Flutter 资源，跟随主进程的 cwd（比如从 IDE 里跑）就会找不到。
Future<bool> launchPlayWindow(String videoId) async {
  return _launchExecutable([kPlayWindowFlag, '$_kVideoArgumentPrefix$videoId']);
}

/// 把主窗口唤到前台；没在运行就直接冷启动一个。
///
/// 播放窗口里「回到主界面」用：无参启动时 runner 的单实例逻辑会激活已运行的
/// 主窗口（ActivateExistingWindow）然后自己退出，主窗口没在跑则正常启动。
Future<void> revealMainWindow() async {
  await _launchExecutable(const []);
}

Future<bool> _launchExecutable(List<String> arguments) async {
  final executable = Platform.resolvedExecutable;
  try {
    await Process.start(
      executable,
      arguments,
      workingDirectory: File(executable).parent.path,
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (error) {
    debugPrint(
      '[play-window] failed to launch "$executable" $arguments: $error',
    );
    return false;
  }
}

/// 点击视频封面的统一入口：桌面 Windows 且设置开启时弹出独立播放窗口，
/// 其余情况照旧在当前窗口内 push 播放页。
///
/// 只用于「从列表进播放页」的入口（首页 / 搜索 / 库 / 预告）。播放页内部的
/// 换集、相关推荐仍走窗口内导航——b 站也是这样：窗口内换内容，不开新窗口。
/// Getchu 预告片这种「合成 VideoDetail 只能靠 extra 传对象」的入口不要走这里，
/// 跨进程传不了对象，继续用 `context.push('/video/…', extra: video)`。
Future<void> openVideo(
  BuildContext context,
  WidgetRef ref,
  String videoId,
) async {
  final settings = ref.read(settingsProvider).valueOrNull;
  if (Platform.isWindows && (settings?.openVideoInWindow ?? true)) {
    if (await launchPlayWindow(videoId)) return;
    // 进程拉不起来（exe 被移动 / 删除等）时回退到窗口内播放，别让用户点不开视频。
    if (context.mounted) context.push('/video/$videoId');
    return;
  }
  context.push('/video/$videoId');
}
