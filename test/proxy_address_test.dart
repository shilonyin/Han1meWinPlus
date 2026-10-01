// 回归测试：自定义代理地址的解析与校验。
//
// 背景（实测结论，非推断）：
// 1. Dart 的 HttpClient.findProxy 只认 `PROXY host:port` 与 `DIRECT` 两种写法
//    （见 Dart SDK `_ProxyConfiguration`：其余一律 throw
//    `HttpException: Invalid proxy configuration`）。
// 2. mpv 的 `http-proxy` 是 HTTP CONNECT 隧道：起假 SOCKS5 端口 + 假 HTTP 端口实测，
//    传 `socks5://...` 时两个端口都不会被连上（静默按直连处理）；传 `http://...`
//    时 HTTP 端口收到 `GET http://...`。
// 3. mpv 原样接受并保留 `http://user:pass@host:port`。
//
// 由此定下两条不变量，本文件就是守着它们：
// - socks 类 scheme 必须被**明确拒绝**，绝不能转成 `PROXY host:port` 去把
//   SOCKS 端口当 HTTP 代理端口说话（那必然失败，且用户看不出原因）。
// - 非法/不支持的地址解析结果必须是 null（= 直连），而不是崩掉或误用。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/windows_proxy.dart';

void main() {
  group('validate 区分「没填」与「填错了」', () {
    test('空值与纯空白算 empty', () {
      expect(WindowsProxy.validate(null), ProxyAddressStatus.empty);
      expect(WindowsProxy.validate(''), ProxyAddressStatus.empty);
      expect(WindowsProxy.validate('   '), ProxyAddressStatus.empty);
    });

    test('合法的 http/https 地址算 valid', () {
      expect(WindowsProxy.validate('http://127.0.0.1:7890'), ProxyAddressStatus.valid);
      expect(WindowsProxy.validate('https://127.0.0.1:7890'), ProxyAddressStatus.valid);
    });

    test('省略 scheme 时按 http 处理（沿用现有习惯）', () {
      expect(WindowsProxy.validate('127.0.0.1:7897'), ProxyAddressStatus.valid);
    });

    test('带凭据仍算 valid', () {
      expect(WindowsProxy.validate('http://user:pass@127.0.0.1:7890'), ProxyAddressStatus.valid);
    });

    test('缺端口算 missingHostOrPort', () {
      expect(WindowsProxy.validate('127.0.0.1'), ProxyAddressStatus.missingHostOrPort);
      expect(WindowsProxy.validate('http://127.0.0.1'), ProxyAddressStatus.missingHostOrPort);
    });

    test('缺主机名算 missingHostOrPort', () {
      expect(WindowsProxy.validate('http://:7890'), ProxyAddressStatus.missingHostOrPort);
    });

    test('socks 类 scheme 一律算 socksUnsupported', () {
      for (final scheme in ['socks', 'socks4', 'socks4a', 'socks5', 'socks5h']) {
        expect(
          WindowsProxy.validate('$scheme://127.0.0.1:1080'),
          ProxyAddressStatus.socksUnsupported,
          reason: '$scheme 两套网络栈都不支持，不能放行（实测）',
        );
      }
    });

    test('其它 scheme 算 unsupportedScheme', () {
      for (final scheme in ['ftp', 'quic', 'file']) {
        expect(WindowsProxy.validate('$scheme://127.0.0.1:1080'), ProxyAddressStatus.unsupportedScheme);
      }
    });
  });

  group('rule 产出 Dart findProxy 认得的规则串', () {
    test('http 地址产出 PROXY host:port; DIRECT', () {
      expect(WindowsProxy.rule('http://127.0.0.1:7890'), 'PROXY 127.0.0.1:7890; DIRECT');
    });

    test('省略 scheme 时补 http', () {
      expect(WindowsProxy.rule('127.0.0.1:7897'), 'PROXY 127.0.0.1:7897; DIRECT');
    });

    test('带凭据时保留凭据（Dart 的 _ProxyConfiguration 支持 user:pass@）', () {
      expect(WindowsProxy.rule('http://user:pass@127.0.0.1:7890'), 'PROXY user:pass@127.0.0.1:7890; DIRECT');
    });

    test('系统代理的多协议写法优先取 https 那一项', () {
      expect(WindowsProxy.rule('http=127.0.0.1:8080;https=127.0.0.1:8443'), 'PROXY 127.0.0.1:8443; DIRECT');
    });

    test('socks 地址返回 null，绝不转成 PROXY 串', () {
      // 这是本文件最重要的一条：把 SOCKS 端口当 HTTP 代理端口说话必然失败，
      // 而失败现场是一堆「连不上」，用户根本查不到是代理类型不对。
      expect(WindowsProxy.rule('socks5://127.0.0.1:1080'), isNull);
      expect(WindowsProxy.rule('socks5://user:pass@127.0.0.1:1080'), isNull);
    });

    test('非法输入返回 null 而不是抛异常', () {
      expect(WindowsProxy.rule(null), isNull);
      expect(WindowsProxy.rule(''), isNull);
      expect(WindowsProxy.rule('   '), isNull);
      expect(WindowsProxy.rule('127.0.0.1'), isNull);
    });
  });

  group('mpvUrl 产出 mpv 的 http-proxy 取值', () {
    test('恒定输出 http:// 形式（mpv 只支持 HTTP 代理）', () {
      expect(WindowsProxy.mpvUrl('PROXY 127.0.0.1:7890; DIRECT'), 'http://127.0.0.1:7890');
    });

    test('带凭据时保留（mpv 实测原样接受并保留该取值）', () {
      expect(WindowsProxy.mpvUrl('PROXY user:pass@127.0.0.1:7890; DIRECT'), 'http://user:pass@127.0.0.1:7890');
    });

    test('DIRECT 与空值返回 null', () {
      expect(WindowsProxy.mpvUrl('DIRECT'), isNull);
      expect(WindowsProxy.mpvUrl(null), isNull);
      expect(WindowsProxy.mpvUrl(''), isNull);
    });

    test('解析不出端口时返回 null', () {
      expect(WindowsProxy.mpvUrl('PROXY 127.0.0.1; DIRECT'), isNull);
    });

    test('rule 与 mpvUrl 串起来：http 地址两侧都拿得到值', () {
      final rule = WindowsProxy.rule('http://127.0.0.1:7890');
      expect(rule, isNotNull);
      expect(WindowsProxy.mpvUrl(rule), 'http://127.0.0.1:7890');
    });

    test('rule 与 mpvUrl 串起来：socks 地址两侧都是 null（一致地不走代理）', () {
      final rule = WindowsProxy.rule('socks5://127.0.0.1:1080');
      expect(rule, isNull);
      expect(WindowsProxy.mpvUrl(rule), isNull);
    });
  });
}
