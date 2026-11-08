import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：中文文档注释的句末标点。
///
/// ## 为什么只有一条规则
///
/// 注释规范（`docs/comment-style.md`）里大部分条款（"写 why 不写 what"、
/// "不写任务流水账"）机器判不了，硬上正则只会误伤。这里只挑**能机械判定、
/// 且判定无歧义**的那一条：完整的中文句子以句号收尾。
///
/// 判定条件三条同时满足才算一句完整的话：
///
/// 1. 行是 `///` 文档注释，且去掉前缀后非空；
/// 2. 正文里含中文，且**不以**中文标点结尾 —— 已带标点的句子不用再管；
/// 3. 正文**不是**结构片段：不以 `-`、`*`、`|`、`>`、`#`、数字序号开头，
///    不是纯代码/链接/引用（`[Foo]`、`foo()`、`{@macro}`）。
///
/// 第三条是防止把列表项、表格行、代码示例误判成"忘记句号的一句话"。
/// 这个守卫宁可漏（少报），也不要误伤 —— 误伤的守卫最后会被关掉。
void main() {
  /// 中文标点结尾。
  final endsWithCjkPunctuation = RegExp(r'[，。：；？！、]$');

  /// 含中文（CJK 统一表意文字）。
  final hasCjk = RegExp(r'[\u4e00-\u9fff]');

  /// 首字符是结构标记的，不当作「一句话」。
  final startsWithStructure = RegExp(r'^[-*|>#`\d]');

  /// 整行是纯引用/代码：`[Foo]`、`foo()`、`SomeClass`。
  final looksLikeCode = RegExp(r'^[\w\[\]<>.,()/]+$');

  bool endsWithLatinPeriod(String text) => text.endsWith('.');

  /// 一行文档注释是不是「忘了句号的完整句子」。
  ///
  /// 公开放到 `main` 外面抽成函数是为了让最后一条测试能直接用同一套判定，
  /// 而不是在测试里再抄一遍 —— 抄一遍的守卫测的是抄件，不是原件。
  bool isUnpunctuatedSentence(String body) =>
      hasCjk.hasMatch(body) &&
      !startsWithStructure.hasMatch(body) &&
      !looksLikeCode.hasMatch(body) &&
      !endsWithCjkPunctuation.hasMatch(body) &&
      !endsWithLatinPeriod(body);

  List<String> offendersIn(File file) {
    final relative = file.path.replaceAll(r'\', '/');
    final hits = <String>[];
    final lines = file.readAsLinesSync();
    for (final (index, line) in lines.indexed) {
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('///')) continue;
      final body = trimmed.substring(3).trim();
      if (body.isEmpty) continue;
      if (!isUnpunctuatedSentence(body)) continue;
      hits.add('$relative:${index + 1}: $body');
    }
    return hits;
  }

  List<File> sourceFiles() => Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('中文文档注释的完整句子以句号收尾', () {
    // 这里只打印数量与样例，不做硬断言 —— 存量注释里有大量未加句号的行，
    // 一次性全改会淹没真正的改动。守卫以「不增长」为目标（见下一个测试的 baseline），
    // 新写的代码里没收句的注释则顺手补掉。
    final offenders = [for (final file in sourceFiles()) ...offendersIn(file)];
    // ignore: avoid_print
    print('未以标点结尾的中文文档注释：${offenders.length} 条');
  });

  test('新增的中文文档注释以句号收尾（对照 baseline 只减不增）', () {
    // baseline 是建立守卫时的存量。守卫的意义在于**新写的**那条合格：
    // 后续改动的代码里若出现未收句的完整句子，数量就会超过 baseline。
    //
    // 降低 baseline 的方式是顺手补句号；不要为了让测试变绿而调大这个数。
    const baseline = 748;
    final offenders = [for (final file in sourceFiles()) ...offendersIn(file)];
    expect(
      offenders.length,
      lessThanOrEqualTo(baseline),
      reason:
          '新写的中文文档注释请以句号收尾（见 docs/comment-style.md）。'
          '当前 ${offenders.length} 条，上限 $baseline。\n'
          '${offenders.take(20).join('\n')}',
    );
  });

  test('守卫规则本身有效（正例与反例）', () {
    // 该报的。
    expect(isUnpunctuatedSentence('顶部背景图 + 渐变遮罩'), isTrue);
    expect(isUnpunctuatedSentence('按元素尺寸分档而不是按页面分'), isTrue);
    // 不该报的：已带标点。
    expect(isUnpunctuatedSentence('顶部背景图 + 渐变遮罩。'), isFalse);
    expect(isUnpunctuatedSentence('顶部背景图 + 渐变遮罩.'), isFalse);
    // 不该报的：结构片段。
    expect(isUnpunctuatedSentence('- 进度条、色块、角标'), isFalse);
    expect(isUnpunctuatedSentence('| 令牌 | 值 | 用于 |'), isFalse);
    expect(isUnpunctuatedSentence('```dart'), isFalse);
    expect(isUnpunctuatedSentence('1. 先找语义'), isFalse);
    // 不该报的：纯代码/引用。
    expect(isUnpunctuatedSentence('[AppMotion.page]'), isFalse);
    expect(isUnpunctuatedSentence('AppRadius.sm'), isFalse);
    // 不该报的：不含中文（英文句子由 lint 的其余规则管）。
    expect(isUnpunctuatedSentence('The quick brown fox'), isFalse);
  });
}
