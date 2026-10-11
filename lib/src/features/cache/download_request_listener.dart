import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/local/download_requests.dart';
import '../video/download_queue.dart';

/// 主窗口侧的信箱监听：把独立播放窗口投进来的意图真正执行掉。
///
/// 为什么需要它：播放窗口是**另一个进程**（见 `play_window.dart` 的 `--play-window`），
/// 而下载调度器（`DownloadController`）持有内存状态、会写回 `download_store.json`，
/// 只有主窗口能持有这一份。所以播放窗口里的「下载」与「我的下载」都只写一封意图信
/// （见 `download_requests.dart`），由这里取走执行 —— 用户看到的结果是：下载内容出现在
/// **软件本体**的缓存页里，而不是只在点它的那个播放窗口里。
///
/// 用轮询而不是文件系统监听：Win32 侧的文件通知在「另一个进程新建文件」时行为
/// 不一致（不同文件系统 / 杀软 / OneDrive 重定向目录下都会漏），而这里只是每两秒
/// 看一眼一个通常为空的目录，代价可以忽略。
class DownloadRequestListener extends ConsumerStatefulWidget {
  const DownloadRequestListener({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  /// 主路由的 navigatorKey：拿到它就能 push 主窗口自己的路由。
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  ConsumerState<DownloadRequestListener> createState() =>
      _DownloadRequestListenerState();
}

class _DownloadRequestListenerState
    extends ConsumerState<DownloadRequestListener> {
  static const _interval = Duration(seconds: 2);

  Timer? _timer;
  var _draining = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) => unawaited(_drain()));
    // 启动时先看一眼：主窗口可能是在播放窗口之后才起来的（上一轮退出时刚好有一封
    // 信没来得及处理），晚了会让用户以为下载没生效。
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_drain()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 处理一批意图。用 [_draining] 串行化，避免上一批还没建完任务时下一轮又读一遍。
  Future<void> _drain() async {
    if (_draining || !mounted) return;
    _draining = true;
    try {
      for (final request in await takeDownloadRequests()) {
        if (!mounted) return;
        switch (request.kind) {
          case DownloadRequestKind.download:
            await _enqueue(request);
          case DownloadRequestKind.openDownloads:
            await _openDownloads();
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _enqueue(DownloadRequest request) async {
    if (request.episodes.isEmpty) return;
    await enqueueDownloads(
      ref,
      episodes: request.episodes,
      quality: request.quality,
      groupName: request.groupName,
      // 同系列的旧任务要一并归组：播放窗口给的是整个 playlist 的 id，这里再并上
      // 本次勾选的集，免得某集的 id 不在 playlist 里时漏掉。
      seriesIds: {
        ...request.seriesIds,
        ...request.episodes.map((episode) => episode.id),
      },
    );
    if (!mounted) return;
    // 主窗口多半没在前台（用户正在播放窗口里操作），把它唤出来并落在「正在缓存」
    // 页签上：用户点完下载，总得能看见它确实开始了。
    await _reveal();
    _goToDownloads();
  }

  /// 「我的下载」：不建任务，只把主窗口唤到前台并切到缓存页。
  Future<void> _openDownloads() async {
    await _reveal();
    _goToDownloads();
  }

  Future<void> _reveal() async {
    try {
      await windowManager.ensureInitialized();
      if (!await windowManager.isVisible()) await windowManager.show();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.focus();
    } catch (_) {
      // 唤不起来（非桌面端 / 插件异常）不该影响下载本身：任务已经建好了。
    }
  }

  /// 走挂在根导航器上的 `/downloads?tab=active`（不是 shell 分支里的 `/cache`）。
  ///
  /// 两条理由与 `video_actions.dart` 的「我的下载」一致：
  /// 1. `/cache` 是 `StatefulShellBranch` 下的分支路由，`push` 进去返回语义不清
  ///    （实测 pop 回不到用户原本待着的分栏）；`/downloads` 与当前栈无关，push 进来、
  ///    返回就能回到原处。
  /// 2. `?tab=active` 直接落在「正在缓存」页签 —— 用户点完下载，要看到的是刚加进
  ///    队列的那条，而不是「已缓存视频」那份列表。
  void _goToDownloads() {
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    // 已经在缓存页就不要再往栈上叠一层（`/cache` 分支与 `/downloads` 都算）。
    final path = GoRouter.of(context).state.uri.path;
    if (path == '/cache' || path == '/downloads') return;
    context.push('/downloads?tab=active');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
