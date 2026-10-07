import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

/// g1455 的独立验证页。
///
/// **为什么单独做一个入口而不是直接改主应用**：主应用的玻璃是我们自己那套
/// （每块面板各自一个 `BackdropFilter`），要换成 g1455 得重写 19 个调用点。
/// 而 g1455 的整个成本模型建立在「一个 `GlassHost` 捕获全屏一次」上 —— 在
/// 真实 GPU 上确认它**确实能出玻璃**之前，任何替换都是盲改。
///
/// 用 `--glass-demo` 启动，主应用一行代码都不会走到这里。
///
/// 这一页刻意照着它文档里"Glass goes over content, in a Stack"的范式搭：
/// 一张会滚动的彩色列表 + 浮在上面的玻璃 bar，用来观察
/// **折射、模糊、底色、亮边**四件事在真实窗口里是否都在。
class GlassDemoApp extends StatelessWidget {
  const GlassDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'g1455 验证',
      debugShowCheckedModeBanner: false,
      // 文档第 1 条：唯一的 host 放在 builder 里、navigator 之上，
      // 这样对话框与弹层也能找到它。
      builder: (context, child) => GlassHost(
        // 文档第 3 条：内容是可滚动彩色列表 → 声明为 richBackdrop，
        // 并把标签对比度压在 WCAG AA，标签色由它自己挑。
        richBackdrop: true,
        minLabelContrast: kTextContrastAA,
        backdrop: const Color(0xFF101014),
        child: child!,
      ),
      home: const GlassDemoPage(),
    );
  }
}

class GlassDemoPage extends StatelessWidget {
  const GlassDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: Stack(
        children: [
          // 内容层：玻璃要折的就是它。
          ListView.builder(
            padding: EdgeInsets.fromLTRB(16, safe.top + 96, 16, 32),
            itemCount: 24,
            itemBuilder: (context, i) => Container(
              height: 110,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    HSVColor.fromAHSV(1, (i * 37) % 360.0, .7, .9).toColor(),
                    HSVColor.fromAHSV(1, (i * 37 + 60) % 360.0, .8, .5).toColor(),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '内容 ${i + 1}',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          ),

          // 玻璃层 1：顶部 bar，贴顶浮着。
          Positioned(
            top: safe.top + 12,
            left: 16,
            right: 16,
            child: GlassBar(
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'g1455 折射验证',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GlassButton(
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    semanticLabel: '搜索',
                    child: const Icon(Icons.search),
                  ),
                ],
              ),
            ),
          ),

          // 玻璃层 2：一块 GlassCard，用来看"面板式"玻璃与 bar 的差异。
          Positioned(
            left: 16,
            right: 16,
            bottom: safe.bottom + 24,
            child: GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GlassCard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('同形状的浮层面板', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    GlassButton(
                      onPressed: () {},
                      child: const Text('按钮'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 玻璃层 3：一个圆形 clear 镜片，用来看折射在曲面上的样子。
          Positioned(
            right: 24,
            top: safe.top + 120,
            child: const SizedBox.square(
              dimension: 88,
              child: GlassSurface(
                borderRadius: kGlassCapsule,
                finish: GlassFinish.clear,
                labelled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
