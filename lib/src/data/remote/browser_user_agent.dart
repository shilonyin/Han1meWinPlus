import 'dart:io';

/// 应用内 WebView（登录页、Cloudflare 人机验证页）与无头代取共用的浏览器 UA。
///
/// 为什么必须**动态**取内核版本，而不是写死一串：
/// `cf_clearance` 与 UA 绑定，而且 Cloudflare 会交叉核对 `User-Agent` 请求头与
/// 页面内 `navigator.userAgent`。写死的版本号一旦与机器上真实的 WebView2 内核
/// 不一致，两边就自相矛盾（请求头声称 Chrome/140、页面自报 Chrome/154），
/// 被判定成伪造浏览器，验证**永远过不去**——表现就是这几个 AV 站点一直转圈。
/// 本项目踩过这个坑：内核升到 154 之后，写死的 140 让所有需要验证的源全挂。
///
/// 所以这里读注册表拿真实内核版本再拼 UA。读不到时回退到 [fallback]，
/// 至少保持「同一串 UA」这个不变量（请求头与 WebView 设置用的是同一个值）。
class BrowserUserAgent {
  const BrowserUserAgent._();

  /// 读不到内核版本时的兜底 UA。
  ///
  /// 取一个足够新的版本号：站点对「太旧的浏览器」另有限制，宁可新不可旧。
  static const fallback = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// WebView2 Evergreen 运行时在注册表里的产品 ID（x64 与 x86 各一份）。
  static const _runtimeKeys = [
    r'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    r'HKEY_CURRENT_USER\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
  ];

  static String? _cached;

  /// 当前应使用的 UA（首次调用时解析并缓存）。
  static String get value => _cached ??= _build();

  /// 仅测试用：覆盖缓存值。
  static set overrideForTesting(String? ua) => _cached = ua;

  /// 从 WebView2 运行时版本拼出 UA；读不到就用 [fallback]。
  static String _build() {
    final major = webView2MajorVersion();
    if (major == null) return fallback;
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36';
  }

  /// WebView2 内核主版本号（如 154）；读不到返回 null。
  ///
  /// 非 Windows（或没有 WebView2）时返回 null，由调用方回退。
  static int? webView2MajorVersion() {
    if (!Platform.isWindows) return null;
    for (final key in _runtimeKeys) {
      final version = _queryRegistry(key, 'pv');
      final major = majorFromVersion(version);
      if (major != null) return major;
    }
    return null;
  }

  static String? _queryRegistry(String key, String valueName) {
    try {
      final result = Process.runSync('reg', ['query', key, '/v', valueName]);
      if (result.exitCode != 0) return null;
      return parseRegistryVersion(result.stdout.toString(), valueName);
    } catch (_) {
      return null;
    }
  }

  /// 从 `reg query` 的输出里取出 `pv` 的值，抽成纯函数便于单测。
  ///
  /// 输出形如：`    pv    REG_SZ    154.0.4258.48`
  static String? parseRegistryVersion(String output, String valueName) {
    final match = RegExp('$valueName\\s+REG_SZ\\s+(\\S+)', caseSensitive: false).firstMatch(output);
    return match?.group(1)?.trim();
  }

  /// 从 `154.0.4258.48` 取出主版本 154；解析不出返回 null。
  static int? majorFromVersion(String? version) {
    if (version == null) return null;
    final match = RegExp(r'^(\d+)\.').firstMatch(version.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    // 明显不合理的主版本号（0、或超过三位数）当作读失败，避免拼出畸形 UA。
    if (major == null || major < 50 || major > 999) return null;
    return major;
  }
}
