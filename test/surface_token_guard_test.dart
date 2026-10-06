import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：禁止 feature 层**自己发明** surface 底色。
///
/// ## 拦什么、不拦什么
///
/// 拦的是 `scheme.surface.withValues(alpha: ...)` 这类「在调用点当场决定
/// 该多不透明」的写法。这种值有规则（要按明暗、档位推导），散落各处就会彼此漂移 ——
/// `GlassPanel` 里那个 62%/72% 就曾经在判定与绘制两处各写了一遍。
/// 规则该收在 `AppSurfaceTokens`（`lib/src/core/app_surface_tokens.dart`）。
///
/// **不拦**「取某一档 surface」的普通读取（`scheme.surfaceContainerLow` 之类）：
/// 取哪一档就是哪一档，直读已经足够清楚，包一层同名访问器不产生信息。
/// 本仓库只有一套 Material 3 主题，没有第二套风格需要桥接。
///
/// 与 `player_controls_alignment_test.dart` 同一路数：直接读源码做静态检查。
void main() {
  /// 规则收敛点 —— 这里本来就该写这些值。
  const allowed = <String>{
    'lib/src/core/app_surface_tokens.dart',
  };

  /// 匹配「对 surface 施加 withValues」，也就是在调用点自创不透明度。
  ///
  /// 两种写法都要拦：
  /// 1. 就地加工 —— `scheme.surface.withValues(alpha: ...)`；
  /// 2. 先取出来再加工 —— `final s = scheme.surface;` 之后 `s.withValues(...)`。
  ///    第 2 种看着绕，但同样是在调用点当场决定不透明度，且更容易躲过肉眼检查。
  ///    当前仓库还没有这种写法，拦它是为了以后不会被这么绕过去。
  final inventedSurfaceAlpha = RegExp(
    r'(?:scheme|colorScheme|theme|(?:Theme\s*\.\s*of\s*\([^)]*\)\s*\.\s*colorScheme))'
    r'\s*\.\s*surface\s*\.\s*withValues'
    r'|\.\s*surface\s*\.\s*withValues',
  );

  /// 把「先取出 surface 赋给变量」的那些变量名也纳入检查。
  ///
  /// 只认得字面量赋值的简单情形（`final x = scheme.surface;`），
  /// 不做数据流分析 —— 这层守卫要的是"便宜且挡得住常见回归"，不是完备性。
  final surfaceAlias = RegExp(
    r'\b(?:final|var|const)\s+(\w+)\s*=\s*'
    r'(?:scheme|colorScheme|theme|(?:Theme\s*\.\s*of\s*\([^)]*\)\s*\.\s*colorScheme))'
    r'\s*\.\s*surface\s*;',
  );

  List<String> offendersIn(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) return const [];
    final lines = file.readAsLinesSync();
    // 先收集「surface 被赋给哪个变量」，再逐行看有没有人对它 withValues。
    final aliases = <String>{
      for (final line in lines)
        if (surfaceAlias.firstMatch(line) case final match?) match.group(1)!,
    };
    final aliasWithValues = RegExp(
      '(?:${aliases.isEmpty ? r'(?!)' : aliases.map(RegExp.escape).join('|')})'
      r'\s*\.\s*withValues',
    );
    return [
      for (final (index, line) in lines.indexed)
        if (inventedSurfaceAlpha.hasMatch(line) ||
            (aliases.isNotEmpty && aliasWithValues.hasMatch(line)))
          '$relativePath:${index + 1}: ${line.trim()}',
    ];
  }

  List<String> featureFiles() => Directory('lib/src/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList();

  test('feature 层不再自创 surface 不透明度', () {
    final offenders = [
      for (final path in featureFiles())
        if (!allowed.contains(path)) ...offendersIn(path),
    ];
    expect(
      offenders,
      isEmpty,
      reason: '这些值有规则（按明暗/档位推导），应收到 AppSurfaceTokens 里，'
          '而不是在调用点各写一遍：\n${offenders.join('\n')}',
    );
  });

  test('规则收敛点本身确实用到了该访问器（守卫没有指向空气）', () {
    // 若 AppSurfaceTokens 被清空或改名，上面的守卫会"全绿但毫无意义"。
    // 这条确保收敛点真的承担了职责。
    expect(
      offendersIn('lib/src/core/app_surface_tokens.dart'),
      isNotEmpty,
      reason: 'AppSurfaceTokens 里应保有 surface 的导数逻辑，否则守卫形同虚设',
    );
  });

  test('守卫能真实拦住违规写法（故意构造一次）', () {
    // 验收标准要求：用一次故意的违规验证守卫会失败。
    // 这里直接对正则喂一段违规代码，确认它命中 —— 而不是断守卫永远为真。
    const violation = '    color: scheme.surface.withValues(alpha: .42),';
    expect(
      inventedSurfaceAlpha.hasMatch(violation),
      isTrue,
      reason: '守卫正则必须能识别违规写法，否则它拦不住任何回归',
    );
    // 反向确认：合法的「取某一档」不该被拦。
    const legitimate = '    color: scheme.surfaceContainerLow,';
    expect(inventedSurfaceAlpha.hasMatch(legitimate), isFalse);
  });

  test('守卫覆盖"先取出 surface 再加工"的绕法', () {
    // 这类写法肉眼与简单正则都容易漏：它把 surface 存进变量，隔几行再加工。
    // 当前仓库没有这种写法，但守卫必须能挡住它，否则以后会从这儿绕过去。
    const source = '''
      final base = scheme.surface;
      // 中间隔几行，干扰简单的行内匹配
      return Container(color: base.withValues(alpha: .4));
    ''';
    final aliases = <String>{
      for (final line in source.split('\n'))
        if (surfaceAlias.firstMatch(line) case final match?) match.group(1)!,
    };
    expect(aliases, contains('base'), reason: '应识别出 surface 被赋给了 base');
    final aliasWithValues = RegExp(
      '(${aliases.map(RegExp.escape).join('|')})\\s*\\.\\s*withValues',
    );
    expect(
      aliasWithValues.hasMatch(source),
      isTrue,
      reason: '对别名的 withValues 也要被拦住',
    );
  });
}
