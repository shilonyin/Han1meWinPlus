// 回归测试：UA 必须跟随本机 WebView2 内核版本，不能写死。
//
// 背景（实测确认的故障）：AV 源里 missav / jable / supjav 都要过 Cloudflare。
// 代码原先把 UA 写死成 `Chrome/140.0.0.0`，而本机 WebView2 内核已升到 154，
// 于是请求头声称 140、页面内 `navigator.userAgent` 自报 154 —— Cloudflare
// 交叉核对这一对值，判定为伪造浏览器，验证永远过不去。
// 现场表现：这几个站点一直转圈、`webview2` 数据目录从未生成（cf_clearance 拿不到）。
//
// 所以不变量是：拼出来的 UA 版本号**必须等于本机真实内核主版本**。
// 谁把动态取值改回写死，本文件就应该变红。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/browser_user_agent.dart';

void main() {
  group('从 reg query 输出里取版本号', () {
    test('典型输出能取出 pv', () {
      const output = '''
HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
    pv    REG_SZ    154.0.4258.48
''';
      expect(BrowserUserAgent.parseRegistryVersion(output, 'pv'), '154.0.4258.48');
    });

    test('大小写与空白差异不影响解析', () {
      const output = '    PV    REG_SZ    120.0.1.2';
      expect(BrowserUserAgent.parseRegistryVersion(output, 'pv'), '120.0.1.2');
      expect(BrowserUserAgent.parseRegistryVersion(output, 'PV'), '120.0.1.2');
    });

    test('找不到该值时返回 null', () {
      expect(BrowserUserAgent.parseRegistryVersion('ERROR: 找不到', 'pv'), isNull);
      expect(BrowserUserAgent.parseRegistryVersion('', 'pv'), isNull);
    });
  });

  group('主版本号解析', () {
    test('正常四段版本取第一段', () {
      expect(BrowserUserAgent.majorFromVersion('154.0.4258.48'), 154);
      expect(BrowserUserAgent.majorFromVersion('140.0.7339.207'), 140);
    });

    test('小于 50 的主版本当作读失败（避免拼出畸形 UA）', () {
      expect(BrowserUserAgent.majorFromVersion('1.2.3'), isNull);
      expect(BrowserUserAgent.majorFromVersion('0.0.0.0'), isNull);
    });

    test('超过三位数当作读失败', () {
      expect(BrowserUserAgent.majorFromVersion('1234.0.0.0'), isNull);
    });

    test('空值与非数字返回 null', () {
      expect(BrowserUserAgent.majorFromVersion(null), isNull);
      expect(BrowserUserAgent.majorFromVersion(''), isNull);
      expect(BrowserUserAgent.majorFromVersion('abc'), isNull);
    });
  });

  group('UA 与内核版本一致（核心不变量）', () {
    tearDown(() => BrowserUserAgent.overrideForTesting = null);

    test('本机 UA 的版本号等于真实 WebView2 主版本', () {
      final major = BrowserUserAgent.webView2MajorVersion();
      final ua = BrowserUserAgent.value;
      if (major == null) {
        // 读不到内核（例如 CI 上没有 WebView2）时应当回退，而不是拼出空版本号。
        expect(ua, BrowserUserAgent.fallback, reason: '读不到内核版本时必须回退到 fallback');
        return;
      }
      expect(
        ua,
        contains('Chrome/$major.0.0.0'),
        reason: 'UA 版本必须与真实内核主版本一致，否则 Cloudflare 会判定为伪造浏览器',
      );
    });

    test('UA 不是写死的 140（本机内核为 154，回归防护）', () {
      final major = BrowserUserAgent.webView2MajorVersion();
      if (major == null) return; // 无 WebView2 环境跳过
      if (major == 140) return; // 恰好在 140 的机器上无从判断
      expect(
        BrowserUserAgent.value,
        isNot(contains('Chrome/140.0.0.0')),
        reason: '内核已是 $major，UA 却还写着 140 —— 这正是导致 AV 站点验证失败的 bug',
      );
    });

    test('UA 保持桌面 Chrome 形态（站点对移动 UA 会返回精简页）', () {
      final ua = BrowserUserAgent.value;
      expect(ua, contains('Mozilla/5.0'));
      expect(ua, contains('Windows NT 10.0; Win64; x64'));
      expect(ua, contains('AppleWebKit/537.36'));
      expect(ua, contains('Safari/537.36'));
      expect(ua, isNot(contains('Mobile')));
    });

    test('同一进程内多次取值稳定（请求头与 WebView 设置必须同一串）', () {
      expect(BrowserUserAgent.value, BrowserUserAgent.value);
    });
  });
}
