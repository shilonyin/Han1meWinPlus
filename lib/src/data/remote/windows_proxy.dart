/// 代理地址的校验结果。
///
/// 「没填」与「填错了」必须分开：两者最终都不走代理，但前者是用户的正常选择，
/// 后者要说出来，否则用户看着自己填的地址百思不得其解（见 [WindowsProxy.validate]）。
enum ProxyAddressStatus {
  /// 空值：未指定代理。
  empty,

  /// 地址合法可用。
  valid,

  /// 缺少主机名或端口。
  missingHostOrPort,

  /// scheme 不在支持范围内。
  unsupportedScheme,

  /// socks 类 scheme：Dart 与 mpv 两套网络栈都不支持（实测），需明确告知。
  socksUnsupported,
}

class WindowsProxy {
  const WindowsProxy._();

  /// 本应用支持显式指定的代理 scheme。
  ///
  /// 只有 `http` / `https`：Dart 的 `HttpClient.findProxy` 只认 `PROXY host:port`
  /// 与 `DIRECT` 两种写法（见 Dart SDK `_ProxyConfiguration`，其余一律抛
  /// `HttpException: Invalid proxy configuration`），而 mpv 的 `http-proxy`
  /// 是 HTTP CONNECT 隧道，实测传 `socks5://` 时**两条路都不连**、静默按直连处理。
  /// 所以 socks 类 scheme 只能明确拒绝，不能放行后静默降级。
  static const supportedSchemes = {'http', 'https'};

  /// socks 类 scheme：解析得出，但两套网络栈都不支持。
  static const _socksSchemes = {'socks', 'socks4', 'socks4a', 'socks5', 'socks5h'};

  /// 校验用户填的代理地址，供设置页与解析层共用。
  static ProxyAddressStatus validate(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return ProxyAddressStatus.empty;
    final uri = _parse(raw);
    if (uri == null || uri.host.isEmpty || !uri.hasPort) {
      return ProxyAddressStatus.missingHostOrPort;
    }
    final scheme = uri.scheme.toLowerCase();
    if (_socksSchemes.contains(scheme)) return ProxyAddressStatus.socksUnsupported;
    if (!supportedSchemes.contains(scheme)) {
      return ProxyAddressStatus.unsupportedScheme;
    }
    return ProxyAddressStatus.valid;
  }

  /// 解析成 `http://host:port` 形式；scheme 不支持或地址不完整时返回 null。
  static Uri? _parse(String raw) {
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
    return uri;
  }

  static String? rule(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    // 系统代理常见的 `http=host:port;https=host:port` 多协议写法：优先取 https 那一项。
    final proxy = raw.contains('=')
        ? raw
            .split(';')
            .map((entry) => entry.split('='))
            .where((entry) => entry.length == 2 && entry.first.toLowerCase() == 'https')
            .map((entry) => entry.last.trim())
            .firstOrNull ??
          raw.split(';').first.trim()
        : raw;
    final uri = _parse(proxy);
    if (uri == null) return null;
    // socks:// 之类不能当 HTTP 代理用：Dart 的 findProxy 只认 PROXY/DIRECT，
    // 硬转成 `PROXY host:port` 会把 SOCKS 端口当 HTTP 代理端口去说话（必然失败）。
    if (!supportedSchemes.contains(uri.scheme.toLowerCase())) return null;
    // Dart 的 `_ProxyConfiguration` 支持 `user:pass@host:port` 形式的代理认证，
    // 用户填了凭据就带上，否则需要认证的代理会一直 407。
    final credentials = uri.userInfo.isEmpty ? '' : '${uri.userInfo}@';
    return 'PROXY $credentials${uri.host}:${uri.port}; DIRECT';
  }

  /// 把 [rule]（如 `PROXY 127.0.0.1:7897; DIRECT`）转成 mpv 的 `http-proxy` 取值。
  ///
  /// mpv/libmpv **不会**读取系统代理，必须由调用方显式传入，否则在需要代理的
  /// 网络环境下视频会一直停留在缓冲状态（界面与评论走 Dart 的 HttpClient，
  /// 那里已经应用了 [rule]，所以看起来只有播放不正常）。
  ///
  /// 没有可用代理时（`DIRECT`、空值、解析不出端口）返回 null。
  ///
  /// 注意 mpv 只支持 HTTP 代理：`http-proxy` 是 HTTP CONNECT 隧道，实测传
  /// `socks5://` 时两套网络栈都不会去连代理端口（静默按直连处理），所以这里
  /// 恒定输出 `http://`。带凭据的取值（`http://user:pass@host:port`）mpv
  /// 原样接受并保留（实测），因此凭据在这里是要带上的。
  static String? mpvUrl(String? rule) {
    if (rule == null) return null;
    final match = RegExp(r'PROXY\s+([^;\s]+)', caseSensitive: false).firstMatch(rule);
    final authority = match?.group(1)?.trim();
    if (authority == null || authority.isEmpty) return null;
    final uri = _parse(authority);
    if (uri == null) return null;
    final credentials = uri.userInfo.isEmpty ? '' : '${uri.userInfo}@';
    return 'http://$credentials${uri.host}:${uri.port}';
  }
}

