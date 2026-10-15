import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_logger.dart';
import '../../data/han1me_repository.dart';
import '../../domain/models/library.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import '../../data/local/library_repository.dart';

final remoteLibraryProvider = FutureProvider.autoDispose<RemoteLibrary>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);
  final account = await ref.watch(accountProvider.future);
  if (account?.id == null) throw StateError('Not logged in');
  final settings = await ref.watch(settingsProvider.future);
  // 失败时记一条带上下文的日志再抛。
  //
  // 这里**不吞掉异常**：界面靠 error 态决定显示什么，静默退回旧数据会让「我的」页
  // 看起来是最新的、实际是陈的。日志的价值在于把原因留档 —— 实测正是靠它才看清
  // 那次是 `HttpException: 信号灯超时时间已到`（站点把 .com 301 到 .me，每个请求
  // 多一跳，叠加代理后首字节在 500ms 量级，四个并发请求里偶发一个超时）。
  // 分区级的容错在 `Han1meApi.library` 里做：单个分区取不到就留空，不再整页失败。
  try {
    final library = await ref.watch(han1meRepositoryProvider).library(settings.resolvedBaseUrl, account!.id!);
    await ref.read(libraryProvider.notifier).cacheRemote(library);
    return library;
  } catch (error, stack) {
    AppLogger.instance.error('拉取「我的」失败', tag: 'library', error: error, stackTrace: stack);
    rethrow;
  }
});
