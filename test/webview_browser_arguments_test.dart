import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/data/remote/webview_environment.dart';

/// 回归「登录页白屏 / 网页打不开 / ERR_CONNECTION_TIMED OUT」。
///
/// 根因是 WebView 通路只靠系统 DNS，而本机对 hanime 站群的解析是被污染的
/// （实测 `hanime1.me` 解到 `65.49.26.99`，直连 `HTTP 000` 完全不可达），
/// 于是同一个网络里**主界面能浏览、登录页却白屏/超时**。
///
/// 修法是给 WebView2 下 `--host-resolver-rules`，把它也指到内置的 Cloudflare 边缘 IP。
/// 但这条 flag 特别容易静默失效：`MAP host ip` 语法自带空格，而 Chromium 用
/// `CommandLineToArgvW` 解析命令行 —— 值不加引号就会在第一个空格被截断。
void main() {
  group('hostResolverRules：域名解析覆盖', () {
    test('只对字面量 IP 生成 MAP，主机名不能当 MAP 目标（会解析回环）', () {
      final rules = hostResolverRules(
        hosts: {'hanime1.me': ['104.19.0.1', 'hanime1.me']},
        addressesFor: (_, addresses) => addresses,
      );
      expect(rules, contains('MAP hanime1.me 104.19.0.1'));
      expect(rules, isNot(contains('MAP hanime1.me hanime1.me')));
    });

    test('裸域与 www 变体都要映射（站点会话在两处各留一份）', () {
      final rules = hostResolverRules(
        hosts: {'hanime1.com': ['104.18.0.1']},
        addressesFor: (_, addresses) => addresses,
      );
      expect(rules, 'MAP hanime1.com 104.18.0.1,MAP www.hanime1.com 104.18.0.1');
    });

    test('规则串里不能出现逗号+空格', () {
      final rules = hostResolverRules();
      expect(rules, isNotEmpty);
      expect(rules.contains(', '), isFalse);
      for (final rule in rules.split(',')) {
        expect(rule.split(' '), hasLength(3), reason: '规则被切坏了：$rule');
      }
    });

    test('已经是 www 开头的 host 不再叠加前缀', () {
      final rules = hostResolverRules(
        hosts: {'www.getchu.com': ['210.155.150.145']},
        addressesFor: (_, addresses) => addresses,
      );
      expect(rules, 'MAP www.getchu.com 210.155.150.145');
      expect(rules, isNot(contains('www.www.')));
    });

    test('IPv6 字面量也算字面量，不能被当成主机名丢掉', () {
      final rules = hostResolverRules(
        hosts: {'hanime1.me': ['2606:4700:3035::ac43:bb8d']},
        addressesFor: (_, addresses) => addresses,
      );
      expect(rules, contains('2606:4700:3035::ac43:bb8d'));
    });

    test('该 host 一个字面量地址都没有时整体跳过，不产出半截规则', () {
      final rules = hostResolverRules(
        hosts: {'hanime1.me': ['hanime1.me']},
        addressesFor: (_, addresses) => addresses,
      );
      expect(rules, isEmpty);
    });

    test('取排序后的第一个地址：整表都映射等于用最慢的覆盖最快的', () {
      final rules = hostResolverRules(
        hosts: {'hanime1.me': ['9.9.9.9', '1.1.1.1', '5.5.5.5']},
        addressesFor: (_, __) => ['1.1.1.1', '9.9.9.9', '5.5.5.5'],
      );
      expect(rules, 'MAP hanime1.me 1.1.1.1,MAP www.hanime1.me 1.1.1.1');
      expect(rules, isNot(contains('9.9.9.9')));
    });

    test('真实内置表能产出规则（防止表被改坏后静默不生效）', () {
      final rules = hostResolverRules();
      expect(rules, isNotEmpty);
      expect(rules, contains('MAP hanime1.me'));
      for (final rule in rules.split(',')) {
        final parts = rule.split(' ');
        expect(parts, hasLength(3), reason: '格式不对的规则整条会被 Chromium 忽略：$rule');
        expect(parts[0], 'MAP');
        expect(RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(parts[2]), isTrue, reason: '目标必须是 IP：$rule');
      }
    });
  });

  group('webViewBrowserArguments：浏览器参数整体拼装', () {
    test('直连 + 开内置 Hosts：显式直连与解析覆盖都要有', () {
      final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: true));
      expect(arguments, contains('--no-proxy-server'));
      expect(arguments, contains('--host-resolver-rules="MAP '));
    });

    test('走代理时不再注入解析覆盖（会绕开代理自己的分流规则）', () {
      final arguments = webViewBrowserArguments('PROXY 127.0.0.1:7897', settings: const AppSettings(useBuiltInHosts: true));
      expect(arguments, contains('--proxy-server=http://127.0.0.1:7897'));
      expect(arguments, isNot(contains('--host-resolver-rules')));
    });

    test('关掉内置 Hosts 就不注入（尊重用户开关）', () {
      final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: false));
      expect(arguments, contains('--no-proxy-server'));
      expect(arguments, isNot(contains('--host-resolver-rules')));
    });

    test('代理地址非法而回退成直连时，仍然注入解析覆盖', () {
      const settings = AppSettings(useBuiltInHosts: true);
      expect(webViewBrowserArguments('DIRECT', settings: settings), contains('--host-resolver-rules="MAP '));
      expect(webViewBrowserArguments('', settings: settings), contains('--host-resolver-rules="MAP '));
    });
  });

  group('解析覆盖必须整体加引号（ERR_CONNECTION_TIMED OUT 的直接原因）', () {
    // 现场证据：运行中实例的 WebView2 命令行里，这条 flag 的实际值只有 `MAP` 三个字符。
    // 用 CommandLineToArgvW（Chromium 同一套解析）实测：
    //   不加引号 → 7 段，`--host-resolver-rules=MAP` 之后全被拆成独立参数
    //   加引号   → 1 段，值与预期完全一致
    const flag = '--host-resolver-rules=';

    test('值必须以双引号开头和结尾', () {
      final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: true));
      final start = arguments.indexOf(flag);
      expect(start, isNonNegative);
      final value = arguments.substring(start + flag.length);
      expect(value, startsWith('"'), reason: '没有起始引号 → 会被 CommandLineToArgvW 按空格切碎');
      expect(value, endsWith('"'), reason: '没有结束引号 → 会被 CommandLineToArgvW 按空格切碎');
    });

    test('引号内部就是完整规则，且含 MAP host ip 的空格语法', () {
      final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: true));
      final value = arguments.substring(arguments.indexOf(flag) + flag.length);
      final inner = value.substring(1, value.length - 1);
      expect(inner, startsWith('MAP '));
      expect(inner, contains(',MAP '));
      expect(inner, isNot(contains('"')));
    });

    test('整个参数串里只有一对双引号（多出来的会让后续参数被吞进同一个值）', () {
      final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: true));
      expect('"'.allMatches(arguments).length, 2);
    });

    test('引号不是用来掩盖一个本身写坏的规则串', () {
      expect(hostResolverRules().contains(', '), isFalse);
    });
  });

  group('进程级兜底（环境创建失败时的降级路径）', () {
    test('环境变量名必须是 WebView2 认的那个', () {
      // 改错名字等于兜底失效（WebView2 读不到就静默用默认值），而自定义环境实测创建失败。
      expect(webViewArgsEnvironmentVariable, 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS');
    });

    test('设置环境变量的调用不能抛异常', () {
      expect(() => applyWebViewArgumentsToProcess('--no-proxy-server'), returnsNormally);
    });
  });
}
