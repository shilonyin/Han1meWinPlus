import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../settings/settings_controller.dart';

/// 独立播放窗口（多进程多窗口方案）的启动参数与进程启动器。
///
/// 客户端式的多窗口播放：点击封面不是在主窗口里 push 播放页，而是再拉起
/// 一个本程序自己的进程，只渲染播放页。之所以用**多进程**而不是
/// desktop_multi_window 的多引擎，是因为后者与手写 runner 不兼容——副窗口一
/// 创建，主窗口的引擎就不再处理输入 / 重绘（见 windows/runner/main.cpp 的
/// NOTE）；独立进程各有各的引擎与消息循环，互不影响，也天然支持同时开多个
/// 播放窗口。runner 侧对 `--play-window` 启动会跳过单实例互斥（见
/// IsPlayWindowLaunch），所以播放窗口与主窗口、以及播放窗口彼此之间都能并存。
const String kPlayWindowFlag = '--play-window';
const String _kVideoArgumentPrefix = '--video=';

/// 当前进程是不是独立播放窗口；由 `main()` 在解析启动参数后置位。
///
/// 界面层要据此避开「只有主窗口才能做的事」——典型的是下载：下载调度器
/// （[DownloadController]）持有内存状态并且会写回下载索引，两个进程各跑一份就会
/// 互相覆盖。播放窗口只投递意图，真正下载交给主窗口（见 download_requests.dart）。
bool isPlayWindowProcess = false;

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
  return launchExecutable([kPlayWindowFlag, '$_kVideoArgumentPrefix$videoId']);
}

/// 把主窗口唤到前台；没在运行就直接冷启动一个。
///
/// 播放窗口里「回到主界面」用：无参启动时 runner 的单实例逻辑会激活已运行的
/// 主窗口（ActivateExistingWindow）然后自己退出，主窗口没在跑则正常启动。
Future<void> revealMainWindow() async {
  await launchExecutable(const []);
}

/// 进程启动器的签名：接命令行参数，起得来返回 true。
typedef LaunchExecutable = Future<bool> Function(List<String> arguments);

/// 当前使用的进程启动器。生产环境就是 [_launchExecutable]。
///
/// 测试会把它换成不真正拉进程的实现，用来断言参数、并模拟「拉不起来」——
/// [openVideo] 里那条回退到窗口内播放的分支只能这样覆盖（真实的
/// `Process.start` 在测试进程里既不该被调用，也没法让它失败）。
@visibleForTesting
LaunchExecutable launchExecutable = _launchExecutable;

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
/// 只用于「从列表进播放页」的入口（首页 / 搜索 / 库 / 预告 / 缓存）。播放页内部的
/// 换集、相关推荐仍走窗口内导航——同类客户端也是这样：窗口内换内容，不开新窗口。
/// Getchu 预告片这种「合成 VideoDetail 只能靠 extra 传对象」的入口不要走这里，
/// 跨进程传不了对象，继续用 `context.push('/video/…', extra: video)`。
Future<void> openVideo(
  BuildContext context,
  WidgetRef ref,
  String videoId,
) async {
  if (await openVideoInPlayWindow(context, ref, videoId)) return;
  if (context.mounted) context.push('/video/$videoId');
}

/// 尝试把 [videoId] 放进独立播放窗口打开；返回 true 表示已经打开、调用方不要再导航。
///
/// 抽出来是为了让**缓存页**复用同一套判断：本地缓存以前是在主窗口内 push
/// `VideoPage`，于是「从缓存播」和「从列表播」行为不一致（前者不开独立窗口）。
/// 播放窗口那一侧会自己按 id 去读本地缓存（见 play_window_app.dart 的
/// `_PlayWindowVideo`），所以这里同样只需要传 id。
Future<bool> openVideoInPlayWindow(
  BuildContext context,
  WidgetRef ref,
  String videoId,
) async {
  final settings = ref.read(settingsProvider).valueOrNull;
  if (!Platform.isWindows || !(settings?.openVideoInWindow ?? true)) return false;
  // 拉起成功就直接返回；拉不起来（exe 被移动 / 删除等）回退窗口内播放，
  // 别让用户点不开视频。
  return launchPlayWindow(videoId);
}
