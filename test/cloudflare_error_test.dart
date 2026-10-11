// 回归测试：Cloudflare 的两种 403 必须分得开。
//
// 背景：站点回 403 时有两种完全不同的情况 ——
//   1. `Just a moment...`：可解的 JS 挑战，走应用内 WebView 过一次就能拿到
//      `cf_clearance`，界面该给「完成 Cloudflare 验证」入口；
//   2. `Attention Required!`：WAF 硬封锁，直接拒绝，**根本不返回挑战页**。
//      让用户点「完成验证」只会看到一个没有可点内容的页面。
//
// 此前两种都被当成同一种异常抛出，硬封锁时界面照样引导用户去点校验，白试一场。
// 现在由 `Han1meApi.cloudflareError` 统一判定并带上 `blocked` 标志，这里守住它。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_api.dart' show Han1meApi;

/// 挑战页的最小特征（真实响应约 5.3KB，这里只取判定用到的部分）。
const _challengeBody = '<!DOCTYPE html><html><head><title>Just a moment...</title></head>'
    '<body><div id="cf-chl-widget"></div><form id="challenge-form"></form></body></html>';

/// 硬封锁页的最小特征（真实响应约 5.5KB）。
const _blockedBody = '<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title></head>'
    '<body><h1>Sorry, you have been blocked</h1></body></html>';

void main() {
  group('cloudflareError 判定', () {
    test('非 403 一律返回 null', () {
      expect(Han1meApi.cloudflareError(200, const {}, _challengeBody, 'u'), isNull);
      expect(Han1meApi.cloudflareError(404, const {}, _challengeBody, 'u'), isNull);
      expect(Han1meApi.cloudflareError(500, const {}, _challengeBody, 'u'), isNull);
      expect(Han1meApi.cloudflareError(null, const {}, _challengeBody, 'u'), isNull);
    });

    test('403 但不是 Cloudflare 页面（没有特征）返回 null', () {
      expect(Han1meApi.cloudflareError(403, const {}, '<html>nope</html>', 'u'), isNull);
    });

    test('可解挑战：blocked 为 false，带原 url', () {
      final error = Han1meApi.cloudflareError(403, const {}, _challengeBody, 'https://hanime1.me/watch?v=1');
      expect(error, isNotNull);
      expect(error!.blocked, isFalse);
      expect(error.url, 'https://hanime1.me/watch?v=1');
    });

    test('硬封锁：blocked 为 true', () {
      final error = Han1meApi.cloudflareError(403, const {}, _blockedBody, 'https://hanime1.me/');
      expect(error, isNotNull);
      expect(error!.blocked, isTrue);
    });

    // `cf-mitigated: challenge` 是 Cloudflare 明示「这是挑战」的头，
    // 有它但正文里没有特征串时，也该判成可解挑战而不是硬封锁。
    test('cf-mitigated: challenge 头算可解挑战', () {
      final error = Han1meApi.cloudflareError(403, const {'cf-mitigated': ['challenge']}, '', 'u');
      expect(error, isNotNull);
      expect(error!.blocked, isFalse);
    });

    test('大写 CF-Mitigated 也能认出来', () {
      final error = Han1meApi.cloudflareError(403, const {'CF-Mitigated': ['Challenge']}, '', 'u');
      expect(error, isNotNull);
      expect(error!.blocked, isFalse);
    });
  });

  group('isCloudflareBlock', () {
    test('只认 Attention Required，不把可解挑战算进去', () {
      expect(Han1meApi.isCloudflareBlock(403, _blockedBody), isTrue);
      expect(Han1meApi.isCloudflareBlock(403, _challengeBody), isFalse);
    });

    // 真实响应里两个串同时出现的情况不该出现；真出现时按「可解」处理更安全 ——
    // 宁可多给一个入口，也不要因为误判成硬封锁而把用户挡在恢复路径之外。
    test('两个特征同时出现时，按可解挑战处理', () {
      const both = '$_blockedBody$_challengeBody';
      expect(Han1meApi.isCloudflareBlock(403, both), isFalse);
    });

    test('非 403 一律 false', () {
      expect(Han1meApi.isCloudflareBlock(200, _blockedBody), isFalse);
      expect(Han1meApi.isCloudflareBlock(null, _blockedBody), isFalse);
    });
  });
}
