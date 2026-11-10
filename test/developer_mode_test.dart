// 回归测试：开发者模式（纯色封面 + 不播放）。
//
// 开发者模式是全局标志驱动：底层封面组件读不到 settingsProvider，由启动流程
// 单向同步到 developerMode.value。这里验证三件事：设置能正确存取、封面层在
// 开启时不发图片请求、provider 入口返回纯色图而不是网络图。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/developer_mode.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/app_image_cache.dart';

void main() {
  setUp(() => developerMode.value = false);
  tearDown(() => developerMode.value = false);

  group('AppSettings.developerMode', () {
    test('默认关闭', () {
      expect(const AppSettings().developerMode, isFalse);
    });

    test('toJson / fromJson 往返保留', () {
      final json = const AppSettings(developerMode: true).toJson();
      expect(json['developerMode'], isTrue);
      expect(AppSettings.fromJson(json).developerMode, isTrue);
    });

    test('老配置缺字段时回落为 false', () {
      expect(AppSettings.fromJson(<String, dynamic>{}).developerMode, isFalse);
    });

    test('copyWith 能开能关', () {
      final on = const AppSettings().copyWith(developerMode: true);
      expect(on.developerMode, isTrue);
      expect(on.copyWith(developerMode: false).developerMode, isFalse);
    });
  });

  group('封面拦截', () {
    testWidgets('开启开发者模式时 AppCachedNetworkImage 只画纯色块', (tester) async {
      developerMode.value = true;
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 120,
            height: 80,
            child: AppCachedNetworkImage(imageUrl: 'https://example.com/a.jpg'),
          ),
        ),
      );
      // MaterialApp 自己也铺一层 ColoredBox，这里只认占位色那一块。
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == developerCoverColor,
        ),
        findsOneWidget,
      );
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('关闭时照常走 CachedNetworkImage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 120,
            height: 80,
            child: AppCachedNetworkImage(imageUrl: 'https://example.com/a.jpg'),
          ),
        ),
      );
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    test('provider 入口在开发者模式下返回纯色图', () {
      developerMode.value = true;
      expect(
        appNetworkImage('https://example.com/a.jpg'),
        same(developerSolidImage),
      );
      expect(
        appCachedImage('https://example.com/a.jpg'),
        same(developerSolidImage),
      );
    });

    test('provider 入口在正常模式下返回网络图', () {
      expect(
        appNetworkImage('https://example.com/a.jpg'),
        isA<CachedNetworkImageProvider>(),
      );
    });
  });
}
