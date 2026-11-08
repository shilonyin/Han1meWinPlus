import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：动效的字面量不许再散落回 feature 层。
///
/// ## 为什么要有这条
///
/// `AppMotion` 已经存在，但「知道有令牌」和「真的用令牌」是两件事：
/// 2026-10 之后仍然新冒出 `170ms`、`180ms`、`160ms` 这类偏差值 ——
/// 它们不只是「散成字面量」，还**绕过了 `motionDuration()`**：
/// 系统的「减少动画」打开时，`AppMotion.*` 经过 `motionDuration` 会归零，
/// 而裸写的 `Duration(milliseconds: 200)` 照样播。
///
/// 所以这里拦的不只是数字，而是「不受无障碍开关约束的动画」。
///
/// ## 怎么放行一个合理的字面量
///
/// 不是所有 `Duration(milliseconds: …)` 都是界面动效，下面三类例外：
///
/// 1. **节流 / 防抖 / 轮询间隔**：`Future.delayed`、`Timer`、`timeout`，
///    它们不是视觉过渡，换令牌没有意义。
/// 2. **单点语义时长**：只有一个调用点、且值是刻意量出来的（悬停延迟、
///    封面放大时长）。这类放在一个命名常量里，值本身携带上下文。
/// 3. **高频阈值**：点击判定用的 250ms 之类，属于交互判定不是动效。
///
/// 放行方式是**加额度**（下面的 `knownOffenders`），只减不增。
/// 加额度时必须写清为什么它不该用 AppMotion —— 额度表就是这份理由的存档。
void main() {
  /// 裸字面量（不在命名常量里）的配额键。
  const bareKey = '*';

  /// 允许保留的字面量：`路径` → `{命名常量: 允许出现次数}`。
  ///
  /// 只减不增。新增一条之前先问：这个时长真的不属于界面过渡吗？
  /// 键写 `*` 表示「这个文件里**非命名常量**的裸字面量」配额，同样只减不增。
  const knownOffenders = <String, Map<String, int>>{
    // 轮询 / 防抖：不是视觉过渡。
    'lib/src/features/account/login_page.dart': {'_pollInterval': 1},
    'lib/src/features/cache/download_request_listener.dart': {'_interval': 1},
    'lib/src/features/shared/hover_preview.dart': {'hoverPreviewDelay': 1},
    // 单点语义时长：值本身说明它是什么，改令牌反而看不出原意。
    'lib/src/features/shared/hover_zoom.dart': {'hoverCoverDuration': 1},
    // 交互判定阈值 / 搜索防抖 / 进度条等待，都不是动效。
    'lib/src/features/comics/comic_pages.dart': {bareKey: 1},
    'lib/src/features/search/search_page.dart': {bareKey: 1},
    'lib/src/features/settings/color_compass_dialog.dart': {bareKey: 1},
    'lib/src/features/stats/stats_page.dart': {bareKey: 1},
  };

  /// 只扫 feature 层。core 层的播放器心跳、网络超时不在这个守卫的范围内，
  /// 它们和界面动效无关。app 层（`app_theme.dart` 的页面过渡）扫，因为它就是动效。
  List<File> featureFiles() => [
    ...Directory('lib/src/features').listSync(recursive: true),
    ...Directory('lib/src/app').listSync(recursive: true),
  ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  /// 匹配 `Duration(milliseconds: 123)`，抓出中间的毫秒数。
  ///
  /// 只认毫秒：仓库里唯一的 `Duration(seconds:)` 级别的值是轮询间隔，
  /// 这类本来就在放行清单里，没有动画用秒级时长。
  final literal = RegExp(r'Duration\(\s*milliseconds:\s*(\d+)\s*\)');

  /// 判断这一行是不是「非视觉」用法（节流、超时、等待）。
  ///
  /// 只看同一行：`Future.delayed(...)`、`Timer(...)`、`.timeout(...)`。
  /// 跨行写法这里故意不管 —— 守卫要的是便宜且挡得住常见回归，
  /// 严格跨行解析的成本远大于它多挡住的少数情况。
  /// 上一行以 `delayed(` / `Timer(` / `timeout(` 结尾 → 本行是它的参数。
  ///
  /// 用一个小状态类而不是把整个文件拼成一行，是为了让报错仍能指到具体行号。
  /// 守卫只需要「够挡住常见回归」，不做完整解析。
  final delayContext = _DelayContext();

  bool isNonVisual(String line) =>
      line.contains('Future<void>.delayed') ||
      line.contains('Future.delayed') ||
      RegExp(r'\bTimer\(').hasMatch(line) ||
      line.contains('.timeout(') ||
      // 跨行调用：`Future<void>.delayed(` 换行后参数落在下一行。
      // 只看单行会把它误判成动画时长 —— 这类"延迟"就算换令牌也不会被
      // motionDuration 归零，硬报违规只会逼人给它加假额度。
      delayContext.isOpen;

  List<String> offendersIn(File file) {
    final relative = file.path.replaceAll(r'\', '/');
    final allowed = knownOffenders[relative] ?? const <String, int>{};
    final used = <String, int>{};
    final hits = <String>[];
    final lines = file.readAsLinesSync();
    delayContext.reset();
    for (final (index, line) in lines.indexed) {
      // 注释里写的示例不算违规。
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) continue;
      final isDelayArgument = delayContext.isOpen;
      delayContext.observe(line);
      if (!literal.hasMatch(line)) continue;
      if (isNonVisual(line) || isDelayArgument) continue;
      // 出现在命名常量声明里：按常量名记账。额度表里没有这个名字就报违规
      // （不是「静默当裸字面量」—— 那样错误信息会指向错误的行）。
      final named = RegExp(
        r'const\s+(?:Duration\s+)?(\w+)\s*=\s*Duration\(\s*milliseconds:',
      ).firstMatch(line);
      if (named != null && allowed.containsKey(named.group(1)!)) {
        final key = named.group(1)!;
        used[key] = (used[key] ?? 0) + 1;
        continue;
      }
      // 裸字面量：只吃 `*` 配额。
      used[bareKey] = (used[bareKey] ?? 0) + 1;
      if (used[bareKey]! <= (allowed[bareKey] ?? 0)) continue;
      hits.add('$relative:${index + 1}: ${line.trim()}');
    }
    // 同一命名常量在同一文件出现更多次也要报 —— 否则把它抄到别处就能绕过守卫。
    for (final entry in used.entries) {
      if (entry.key == bareKey) continue;
      final budget = allowed[entry.key] ?? 0;
      if (entry.value > budget) {
        hits.add(
          '$relative: 常量 ${entry.key} 出现 ${entry.value} 次，'
          '额度只有 $budget 次',
        );
      }
    }
    return hits;
  }

  test('feature 层不再新写不受 motionDuration 约束的动画时长', () {
    final offenders = [for (final file in featureFiles()) ...offendersIn(file)];
    expect(
      offenders,
      isEmpty,
      reason:
          '这些时长应改用 AppMotion.*，并经过 motionDuration(context, ...) —— '
          '否则系统的「减少动画」打开时它们照样播：\n${offenders.join('\n')}',
    );
  });

  test('额度表里的文件确实存在（防止改名后额度失效成摆设）', () {
    for (final path in knownOffenders.keys) {
      expect(File(path).existsSync(), isTrue, reason: '额度表指向了不存在的文件：$path');
    }
  });

  test('守卫能真实拦住违规写法（故意构造一次）', () {
    // 守住「守卫永远绿」这件事本身：不喂真实文件，直接对匹配逻辑验一次。
    const violation = '          duration: const Duration(milliseconds: 170),';
    expect(literal.hasMatch(violation), isTrue);
    // 反向确认：轮询、超时这类非视觉用法不该被拦。
    const polling =
        '    await Future<void>.delayed(const Duration(milliseconds: 500));';
    expect(isNonVisual(polling), isTrue);
    const timeout = '    await controller.pause().timeout(';
    expect(isNonVisual(timeout), isTrue);
    // 合法写法不该被拦。
    const legitimate = '          duration: AppMotion.brief,';
    expect(literal.hasMatch(legitimate), isFalse);
  });

  test('曲线字面量里，非豁免的曲线也要收进 AppMotion', () {
    // `Curves.easeOutCubic` 有 11 处同类用途，已经收成 `AppMotion.settle`。
    // 之后同类过渡再冒出一个新曲线，这里就会红。
    //
    // 豁免两条：
    // - `linear` / `easeOut` 本来就是"没有曲线的曲线"，收成令牌不产生语义；
    // - `explore_page.dart` 的 `fastOutSlowIn` 是从 AniBaka 抄来的翻页曲线，
    //   刻意保留原手感（见该文件里 `_slideCurve` 的注释）。
    const allowedCurves = <String>{'linear', 'easeOut'};
    const curveFileExemptions = <String, Set<String>>{
      'lib/src/features/explore/explore_page.dart': {
        'fastOutSlowIn',
        'easeOutQuart',
      },
      // 主题切换的圆形揭示要「两端都缓」，现有令牌都是单端缓动。
      'lib/src/app/theme_transition.dart': {'easeInOutCubic'},
    };
    final curveUse = RegExp(r'Curves\.(\w+)');
    final offenders = <String>[];
    for (final file in featureFiles()) {
      final relative = file.path.replaceAll(r'\', '/');
      final exempt = curveFileExemptions[relative] ?? const <String>{};
      final lines = file.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        for (final match in curveUse.allMatches(line)) {
          final name = match.group(1)!;
          if (allowedCurves.contains(name) || exempt.contains(name)) continue;
          // 变量名里带 Curve 的那一行是往 AppMotion 抄的，不在这里拦。
          offenders.add('$relative:${index + 1}: Curves.$name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '过渡曲线也应走 AppMotion（settle / enter / exit / standardCurve）。'
          '确实需要别的曲线时，加进 AppMotion 并在注释里说明它和现有曲线的分工：\n'
          '${offenders.join('\n')}',
    );
  });
}

/// 追踪「上一行以 `delayed(` / `Timer(` / `timeout(` 结尾」：下一行是它的参数，
/// 不是动画时长。
///
/// 只认一种形态 —— 调用括号挂在行尾、参数在下一行。这是仓库里实际出现的写法；
/// 更复杂的跨行形态不做解析，守卫的取舍在 `isNonVisual` 的注释里写了。
class _DelayContext {
  var _open = false;

  bool get isOpen => _open;

  void reset() => _open = false;

  void observe(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    _open = RegExp(r'(delayed|Timer|timeout)\(\s*$').hasMatch(trimmed);
  }
}
