import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

/// g1455 的独立验证页。
///
/// **为什么单独做一个入口而不是直接改主应用**：主应用的玻璃是我们自己那套
/// （每块面板各自一个 `BackdropFilter`）。而 g1455 的整个成本模型建立在
/// 「一个 `GlassHost` 捕获全屏一次」上 —— 在真实 GPU 上确认它**确实能出玻璃**
/// 之前，任何替换都是盲改。
///
/// 用 `--glass-demo` 启动，主应用一行代码都不会走到这里。
///
/// 这一页是**动效试验台**：三块不同粘度的 ripple 玻璃 + 四个带 drop motion 的
/// 控件，用来一次看全它那套"液体"动效与我们原来 Material 动效的差别。
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
        // drop motion 由 host 统一下发；单个控件仍可自己覆盖。
        dropMotion: const GlassDropMotion(),
        child: child!,
      ),
      home: const GlassDemoPage(),
    );
  }
}

class GlassDemoPage extends StatefulWidget {
  const GlassDemoPage({super.key});

  @override
  State<GlassDemoPage> createState() => _GlassDemoPageState();
}

class _GlassDemoPageState extends State<GlassDemoPage> {
  int _segment = 0;
  int _tab = 0;
  double _slider = .45;
  bool _switch = true;

  /// 自动演示用的锚点：要拿到控件在屏幕上的确切位置，才能把合成的指针事件
  /// 按在它身上（而不是靠手算坐标）。
  final GlobalKey _sliderKey = GlobalKey();
  final GlobalKey _tabKey = GlobalKey();
  bool _autoRunning = false;

  /// 用**合成指针事件**驱动拖动。
  ///
  /// **为什么不是靠外部模拟鼠标**：Windows 上往窗口 PostMessage 拖动类手势不响应，
  /// 真鼠标又会和别的程序抢光标；而在 Dart 层直接喂 `PointerDownEvent/MoveEvent`，
  /// 走的是 Flutter 自己的命中测试与手势识别，与真手指完全同一条路径，
  /// 也不影响用户的鼠标。
  Future<void> _runAutoDemo() async {
    if (_autoRunning) return;
    setState(() => _autoRunning = true);
    try {
      // 滑块：从中间快速拉到右端，再拉回来 —— 加速度越大水珠拉得越长。
      await _dragAcross(_sliderKey, from: const Offset(-160, 0), to: const Offset(240, 0), steps: 30);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _dragAcross(_sliderKey, from: const Offset(240, 0), to: const Offset(-200, 0), steps: 26);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // 标签栏：跨三个标签横拖，形变幅度最大（文档里量到的 11%–12%）。
      await _dragAcross(_tabKey, from: const Offset(-150, 0), to: const Offset(320, 0), steps: 34);
    } finally {
      if (mounted) setState(() => _autoRunning = false);
    }
  }

  /// 在 [key] 控件上按下、变速移到目标、抬起。
  ///
  /// 三个坑，都是踩过才写在这里的：
  /// 1. **不能用 `endOfFrame` 驱动循环**：窗口被别的窗口挡住时引擎是按需出帧的，
  ///    没有新帧要调度，`endOfFrame` 的 future 就永远不完成，整段演示会卡死，
  ///    按钮也跟着永久禁用。所以按**真实时间**推进。
  /// 2. **必须给每个事件真实的 `timeStamp`**：drop motion 是加速度驱动的形变，
  ///    时间戳全为 0 时速度估计拿不到有效 dt，水珠根本不会变形。
  /// 3. **起点要先跨过 touch slop**：曲线从 0 起步的话，前十几步位移不到 1 像素，
  ///    拖动识别器一直赢不了手势竞技场，只有按下那一帧生效。
  Future<void> _dragAcross(GlobalKey key, {required Offset from, required Offset to, int steps = 30, Curve curve = Curves.easeInQuad}) async {
    final RenderBox? box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset center = box.localToGlobal(box.size.center(Offset.zero));
    final Offset start = center + from;
    final Offset end = center + to;
    final Offset travel = end - start;
    const int pointer = 7; // 一个不会被真实鼠标占用的 pointer id
    const double lead = .08; // 起步就跨过 kTouchSlop 的那一段
    final GestureBinding binding = GestureBinding.instance;
    final Stopwatch clock = Stopwatch()..start();

    binding.handlePointerEvent(PointerDownEvent(pointer: pointer, position: start, timeStamp: clock.elapsed));
    await Future<void>.delayed(const Duration(milliseconds: 16));
    Offset previous = start;
    for (var i = 1; i <= steps; i++) {
      final double t = i / steps;
      final Offset position = start + travel * (lead + (1 - lead) * curve.transform(t));
      binding.handlePointerEvent(PointerMoveEvent(pointer: pointer, position: position, delta: position - previous, timeStamp: clock.elapsed));
      previous = position;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: end, timeStamp: clock.elapsed));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      body: Stack(
        children: [
          // 内容层：玻璃要折的就是它。彩色渐变块 —— 没这层，玻璃只是灰块。
          ListView.builder(
            padding: EdgeInsets.fromLTRB(16, safe.top + 96, 16, 220),
            itemCount: 18,
            itemBuilder: (context, i) => Container(
              height: 100,
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

          // ── 顶部 bar ────────────────────────────────────────────────
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
                      'g1455 动效试验台',
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

          // ── 三块不同粘度的 ripple 玻璃 ──────────────────────────────
          // 文档：ripple 只该用在**无文字**的大块玻璃上，且不要压在别的可点元素上。
          // 这三块都 `labelled: false`，各自命名粘度，好横向比。
          Positioned(
            top: safe.top + 96,
            right: 16,
            child: Column(
              children: [
                _RippleSwatch(label: '水 0.15', viscosity: .15),
                const SizedBox(height: 10),
                _RippleSwatch(label: '默认 0.6', viscosity: .6),
                const SizedBox(height: 10),
                _RippleSwatch(label: '蜂蜜 0.95', viscosity: .95),
              ],
            ),
          ),

          // ── 四个带 drop motion 的控件 ───────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: safe.bottom + 16,
            child: GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 分段控件：选中项按住时变成"玻璃水珠"，移动时按加速度拉长/压扁。
                    GlassSegmentedControl(
                      segments: const [
                        Text('日'),
                        Text('周'),
                        Text('月'),
                        Text('年'),
                      ],
                      selectedIndex: _segment,
                      onSelected: (i) => setState(() => _segment = i),
                    ),
                    const SizedBox(height: 16),
                    // 滑块：拖动时滑块变成水珠，停下时弹簧回圆。
                    GlassSlider(
                      key: _sliderKey,
                      value: _slider,
                      onChanged: (v) => setState(() => _slider = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Text('开关的水珠')),
                        GlassSwitch(
                          value: _switch,
                          onChanged: (v) => setState(() => _switch = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 标签栏：跨多个标签拖动最能看出形变（3 个标签约 11%/12%）。
                    GlassTabBar(
                      key: _tabKey,
                      items: const [
                        GlassTabItem(icon: Icons.home, label: '主页'),
                        GlassTabItem(icon: Icons.explore, label: '发现'),
                        GlassTabItem(icon: Icons.person, label: '我的'),
                        GlassTabItem(icon: Icons.settings, label: '设置'),
                      ],
                      selectedIndex: _tab,
                      onSelected: (i) => setState(() => _tab = i),
                    ),
                    const SizedBox(height: 12),
                    // 「自动演示」：合成指针事件跑一遍拖动，用来在没有人工操作时
                    // 也能抓取 drop motion 的中间帧（见 _runAutoDemo 的说明）。
                    FilledButton(
                      onPressed: _autoRunning ? null : _runAutoDemo,
                      child: Text(_autoRunning ? '演示中…' : '自动演示拖动'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一块无文字的 ripple 玻璃，按粘度命名。按住它看液体波。
class _RippleSwatch extends StatelessWidget {
  const _RippleSwatch({required this.label, required this.viscosity});

  final String label;
  final double viscosity;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    height: 76,
    child: Stack(
      children: [
        Positioned.fill(
          child: GlassSurface(
            borderRadius: BorderRadius.circular(20),
            finish: GlassFinish.clear,
            // 无文字 → 保持 clear 不被压暗，波纹才看得清（它的文档明确建议）。
            labelled: false,
            ripple: GlassRipple(viscosity: viscosity, amplitude: 8, light: .06),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 8,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
