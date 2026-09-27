// 回归测试：账号资料刷新（cookie 不变）不得让视频详情 provider 失效重建。
//
// 背景（用户报的现象）：点视频 → 正常播放几秒 → 画面自动重新加载一遍。
// 根因链路：
//   1. AccountController.build() 里有个 unawaited 的资料刷新
//      （Future.delayed(Duration.zero) -> _refresh），它发网络请求拉用户资料，
//      回来后执行 `state = AsyncData(next)`（account_controller.dart:151）。
//   2. videoDetailProvider 以前直接 `ref.watch(accountProvider)`，于是那次刷新
//      让详情 provider 失效重建、退回 loading 态。
//   3. video_page.dart 是 `ref.watch(videoDetailProvider).when(...)`，loading 分支
//      返回加载指示器 —— 整个播放器被从树上摘掉，数据回来后再重建。
//   其中「几秒」正是资料请求的往返时间。
//
// 修复：详情只 select 出 cookie（_refresh 前后 cookie 不变），资料刷新不再影响详情，
// 而登录 / 登出（cookie 变了）仍会正常触发重取。
//
// 本文件直接驱动**真实的 videoDetailProvider**（只把仓库与账号换成替身），
// 这样把依赖改回 `ref.watch(accountProvider)` 会让测试变红（已用变异验证）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/han1me_repository.dart';
import 'package:han1me_win_plus/src/domain/models/account.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/account/account_controller.dart';
import 'package:han1me_win_plus/src/features/video/video_controller.dart';

/// 记录 video() 被调用了几次 —— 这就是「详情是否被重建」的观察点。
var detailFetchCount = 0;

/// 只实现 video()，其余一律抛错（测试不该走到别的接口）。
class _FakeRepository implements Han1meRepository {
  @override
  Future<VideoDetail> video(String baseUrl, String id) async {
    detailFetchCount++;
    return VideoDetail(
      id: id,
      title: 't',
      sources: const [],
      tags: const [],
      playlist: const [],
      related: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被调用');
}

/// 可直接推入 AsyncValue 的账号状态替身（绕开真实的网络资料刷新）。
///
/// 继承 AccountController 才能用于 accountProvider.overrideWith：container 拿到的
/// notifier 仍是 AccountController 类型，调用方读到的却是我们推入的状态。
///
/// build 返回一个永不完成的 Future，好让初始状态停在 AsyncLoading
/// （首屏时序的用例需要它）。
class _AccountStub extends AccountController {
  final _never = Completer<Account?>();

  @override
  Future<Account?> build() => _never.future;

  void push(AsyncValue<Account?> next) => state = next;
}

Account _account({required String cookie, String? name}) =>
    Account(cookie: cookie, id: '1', name: name);

/// 建容器：仓库换假实现、账号换成可手动推入的替身。
///
/// 关键是 videoDetailProvider 对账号的**依赖方式**是否只取 cookie，
/// 这与替身本身是什么无关。
ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      han1meRepositoryProvider.overrideWithValue(_FakeRepository()),
      accountProvider.overrideWith(_AccountStub.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 取到那个替身 notifier（overrideWith 的静态类型是父类，这里转回来以便 push）。
_AccountStub _stub(ProviderContainer container) =>
    container.read(accountProvider.notifier) as _AccountStub;

void main() {
  setUp(() => detailFetchCount = 0);

  test('账号资料刷新（cookie 不变）→ 详情不被重取（修复的核心）', () async {
    final container = _container();
    // 先让账号就绪，避免首屏 loading→ready 那次正当重取混进计数。
    _stub(
      container,
    ).push(AsyncData(_account(cookie: 'c=1', name: '旧昵称')));
    container.listen(videoDetailProvider('v1'), (_, __) {});
    await container.read(videoDetailProvider('v1').future);
    final before = detailFetchCount;

    // 资料刷新：_refresh 的结果 —— 只改资料字段，cookie 原样不动。
    _stub(
      container,
    ).push(AsyncData(_account(cookie: 'c=1', name: '新昵称')));
    await Future<void>.delayed(Duration.zero);

    expect(
      detailFetchCount,
      before,
      reason: 'cookie 未变，资料刷新不该让详情重建（否则播放器会被摘掉）',
    );
  });

  test('登录（cookie 变化）→ 详情正常重取', () async {
    final container = _container();
    _stub(container).push(AsyncData(_account(cookie: 'c=1')));
    container.listen(videoDetailProvider('v1'), (_, __) {});
    await container.read(videoDetailProvider('v1').future);
    final before = detailFetchCount;

    _stub(container).push(AsyncData(_account(cookie: 'c=2')));
    await container.read(videoDetailProvider('v1').future);
    expect(detailFetchCount, greaterThan(before), reason: 'cookie 变了要重取');
  });

  test('登出（cookie 变空）→ 详情正常重取', () async {
    final container = _container();
    _stub(container).push(AsyncData(_account(cookie: 'c=1')));
    container.listen(videoDetailProvider('v1'), (_, __) {});
    await container.read(videoDetailProvider('v1').future);
    final before = detailFetchCount;

    _stub(container).push(const AsyncData(null));
    await container.read(videoDetailProvider('v1').future);
    expect(detailFetchCount, greaterThan(before));
  });

  test('同一 cookie 连续多次刷新 → 一次都不该重取（去抖）', () async {
    final container = _container();
    _stub(container).push(AsyncData(_account(cookie: 'c=1', name: 'a')));
    container.listen(videoDetailProvider('v1'), (_, __) {});
    await container.read(videoDetailProvider('v1').future);
    final before = detailFetchCount;

    for (var i = 0; i < 5; i++) {
      _stub(
        container,
      ).push(AsyncData(_account(cookie: 'c=1', name: 'name$i')));
      await Future<void>.delayed(Duration.zero);
    }
    expect(detailFetchCount, before, reason: 'cookie 一直是 c=1');
  });

  test('首屏：账号从 loading 到就绪 → 详情重取一次以带登录态', () async {
    final container = _container();
    container.listen(videoDetailProvider('v1'), (_, __) {});
    await Future<void>.delayed(Duration.zero);
    final duringLoading = detailFetchCount;

    _stub(container).push(AsyncData(_account(cookie: 'c=1')));
    await container.read(videoDetailProvider('v1').future);
    expect(
      detailFetchCount,
      greaterThan(duringLoading),
      reason: 'cookie 从空变为有值，应重取以带登录态',
    );
  });
}
