class WindowsProxy {
  const WindowsProxy._();

  static String? rule(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    final proxy = raw.contains('=')
        ? raw
            .split(';')
            .map((entry) => entry.split('='))
            .where((entry) => entry.length == 2 && entry.first.toLowerCase() == 'https')
            .map((entry) => entry.last.trim())
            .firstOrNull ??
          raw.split(';').first.trim()
        : raw;
    final uri = Uri.tryParse(proxy.contains('://') ? proxy : 'http://$proxy');
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
    return 'PROXY ${uri.host}:${uri.port}; DIRECT';
  }

  /// 把 [rule]（如 `PROXY 127.0.0.1:7897; DIRECT`）转成 mpv 的 `http-proxy` 取值。
  ///
  /// mpv/libmpv **不会**读取系统代理，必须由调用方显式传入，否则在需要代理的
  /// 网络环境下视频会一直停留在缓冲状态（界面与评论走 Dart 的 HttpClient，
  /// 那里已经应用了 [rule]，所以看起来只有播放不正常）。
  ///
  /// 没有可用代理时（`DIRECT`、空值、解析不出端口）返回 null。
  static String? mpvUrl(String? rule) {
    if (rule == null) return null;
    final match = RegExp(r'PROXY\s+([^;\s]+)', caseSensitive: false).firstMatch(rule);
    final authority = match?.group(1)?.trim();
    if (authority == null || authority.isEmpty) return null;
    final uri = Uri.tryParse(authority.contains('://') ? authority : 'http://$authority');
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
    return 'http://${uri.host}:${uri.port}';
  }
}

