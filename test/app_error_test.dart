// 回归测试：统一的错误态（AppErrorView / showAppErrorBar）。
//
// 背景（用户要求）：出错时要给一条看得见、能重来的提示。改之前首页/搜索/漫画三处
// 各写一份几乎一样的错误视图，其中两份靠 `'$error'.contains('Cloudflare')` 判断要不要
// 给「完成验证」的入口 —— 文案一改就静默失效。这里同时守住三件事：
//  A. 分类函数按**类型**给出建议与图标；
//  B. 「完成验证」只在真的是 [CloudflareChallengeException] 时出现；
//  C. 顶部提示条能装进 root overlay、能点重试、能关掉。
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_api.dart' show CloudflareChallengeException;
import 'package:han1me_win_plus/src/features/shared/app_error.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 造一个 DioException：只关心 statusCode / type，其余字段给最小可用值。
DioException _dio({int? statusCode, DioExceptionType type = DioExceptionType.badResponse}) =>
    DioException(
      requestOptions: RequestOptions(path: '/'),
      type: type,
      response: statusCode == null ? null : Response<void>(requestOptions: RequestOptions(path: '/'), statusCode: statusCode),
    );

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('错误分类', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    });

    test('Cloudflare 挑战给换网络/镜像的建议', () {
      expect(appErrorSuggestion(l10n, CloudflareChallengeException('https://a/b')), l10n.suggestionCloudflare);
      expect(appErrorSuggestion(l10n, _dio(statusCode: 403)), l10n.suggestionCloudflare);
    });

    test('5xx 判站点异常，超时/连接类判网络', () {
      expect(appErrorSuggestion(l10n, _dio(statusCode: 503)), l10n.suggestionSite);
      expect(appErrorSuggestion(l10n, _dio(type: DioExceptionType.connectionTimeout)), l10n.suggestionTimeout);
      expect(appErrorSuggestion(l10n, _dio(type: DioExceptionType.connectionError)), l10n.suggestionTimeout);
    });

    test('认不出的错误不给建议，而不是猜一个', () {
      expect(appErrorSuggestion(l10n, StateError('boom')), isNull);
      expect(appErrorSuggestion(l10n, _dio(statusCode: 404)), isNull);
    });

    test('图标按种类分档', () {
      expect(appErrorIcon(CloudflareChallengeException('u')), Symbols.gpp_maybe_rounded);
      expect(appErrorIcon(_dio(type: DioExceptionType.receiveTimeout)), Symbols.wifi_off_rounded);
      expect(appErrorIcon(StateError('x')), Symbols.error_outline_rounded);
    });
  });

  group('AppErrorView', () {
    testWidgets('整页错误态给出原因、建议与重试', (tester) async {
      await tester.pumpWidget(_host(AppErrorView(error: _dio(statusCode: 503), onRetry: () {})));
      await tester.pumpAndSettle();

      // 错误原文来自 `'$error'`，DioException 会把状态码拼进去；这里只断言
      // 「有原因、有建议、有重试」三件事都在，不锁死 Dio 的文案格式。
      expect(find.textContaining('DioException'), findsOneWidget);
      expect(find.textContaining('站点返回异常'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 不是 Cloudflare，就不该出现那条恢复入口。
      expect(find.text('完成 Cloudflare 验证'), findsNothing);
    });

    testWidgets('Cloudflare 挑战才出现「完成验证」，且不靠文案判断', (tester) async {
      var verified = 0;
      await tester.pumpWidget(_host(AppErrorView(
        error: CloudflareChallengeException('https://hanime1.me/'),
        onRetry: () {},
        onCloudflareVerified: () async => verified++,
      )));
      await tester.pumpAndSettle();

      expect(find.text('完成 Cloudflare 验证'), findsOneWidget);
      await tester.tap(find.text('完成 Cloudflare 验证'));
      await tester.pumpAndSettle();
      expect(verified, 1);

      // 反过来：错误文案里带 Cloudflare 字样、但类型不对 —— 旧实现会误判成挑战，
      // 现在必须不给入口。
      await tester.pumpWidget(_host(AppErrorView(error: StateError('Cloudflare said no'), onRetry: () {}, onCloudflareVerified: () async {})));
      await tester.pumpAndSettle();
      expect(find.text('完成 Cloudflare 验证'), findsNothing);
    });

    testWidgets('没有 onRetry 时不画重试按钮', (tester) async {
      await tester.pumpWidget(_host(const AppErrorView(error: 'plain')));
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsNothing);
      expect(find.text('plain'), findsOneWidget);
    });
  });

  group('showAppErrorBar', () {
    testWidgets('挂到 root overlay，重试按钮回调并收起提示', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(Builder(builder: (context) => TextButton(
        onPressed: () => showAppErrorBar(context, StateError('拉取失败'), onRetry: () => retried++),
        child: const Text('触发'),
      ))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();
      expect(find.textContaining('拉取失败'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(retried, 1);
      // 点过重试就该让位，免得盖着新内容。
      expect(find.textContaining('拉取失败'), findsNothing);
    });

    testWidgets('关闭按钮收起提示，且不留悬挂的定时器', (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) => TextButton(
        onPressed: () => showAppErrorBar(context, StateError('又失败了')),
        child: const Text('触发'),
      ))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();
      expect(find.textContaining('又失败了'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.textContaining('又失败了'), findsNothing);
    });

    testWidgets('返回的句柄能提前撤掉提示', (tester) async {
      late VoidCallback dismiss;
      await tester.pumpWidget(_host(Builder(builder: (context) => TextButton(
        onPressed: () => dismiss = showAppErrorBar(context, StateError('临时')),
        child: const Text('触发'),
      ))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();
      expect(find.textContaining('临时'), findsOneWidget);

      dismiss();
      await tester.pumpAndSettle();
      expect(find.textContaining('临时'), findsNothing);
    });
  });
}
