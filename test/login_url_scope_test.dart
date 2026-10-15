import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/account/login_url_scope.dart';

/// 回归「密码输错时看不到站点的错误提示」。
///
/// 站点已把 `hanime1.com` 301 到 `hanime1.me`，而用户设置里存的仍是 `.com`。
/// 登录页原来用 `url.host != login.host` 判断「是否已离开登录页」，两边域名不同时
/// 这个条件**恒为真** —— 轮询每 2 秒就认为登录完成、强制采集一次 cookie，拿不到
/// 账号资料就抛 `Account profile is unavailable`。
///
/// 用户看到的是：密码输错了，站点正要显示「账号或密码错误」，却被应用自己那条
/// 内部错误盖住；而且每隔两秒重复一次。这个测试钉住的就是那个判断。
void main() {
  group('登录页判定：是否还停在登录页上', () {
    test('同一个域名、同一个路径 → 还在登录页', () {
      expect(
        isStillOnLoginPage(current: Uri.parse('https://hanime1.com/login'), base: 'https://hanime1.com'),
        isTrue,
      );
    });

    test('站点重定向到镜像域名时，仍算还在登录页（核心回归）', () {
      // 设置里是 .com，页面实际在 .me —— 这正是用户遇到的情形。
      expect(
        isStillOnLoginPage(current: Uri.parse('https://hanime1.me/login'), base: 'https://hanime1.com'),
        isTrue,
      );
      expect(
        isStillOnLoginPage(current: Uri.parse('https://hanimeone.me/login'), base: 'https://hanime1.com'),
        isTrue,
      );
    });

    test('www 前缀不影响判断', () {
      expect(
        isStillOnLoginPage(current: Uri.parse('https://www.hanime1.me/login'), base: 'https://hanime1.com'),
        isTrue,
      );
    });

    test('同站群但路径不同 → 已离开登录页', () {
      expect(
        isStillOnLoginPage(current: Uri.parse('https://hanime1.me/'), base: 'https://hanime1.com'),
        isFalse,
      );
      expect(
        isStillOnLoginPage(current: Uri.parse('https://hanime1.me/user/123/edit'), base: 'https://hanime1.com'),
        isFalse,
      );
    });

    test('完全不同的站点 → 已离开登录页', () {
      expect(
        isStillOnLoginPage(current: Uri.parse('https://example.com/login'), base: 'https://hanime1.com'),
        isFalse,
      );
    });

    test('host 为空（页面还没加载出来）→ 当作还没离开，别急着采集', () {
      expect(
        isStillOnLoginPage(current: Uri.parse('about:blank'), base: 'https://hanime1.com'),
        isFalse,
      );
    });
  });
}
