import 'package:flutter/widgets.dart';

/// 一块玻璃面板向登记册暴露的几何与采样属性。
@immutable
class GlassSurfaceRecord {
  const GlassSurfaceRecord({
    required this.bounds,
    required this.sharedSampling,
  });

  /// 这块玻璃在**全局坐标**里占的矩形。
  final Rect bounds;

  /// 它的滤镜是否与同类面板**完全相同**（纯模糊档），因而可以和它们共用一次
  /// 背景采样。
  ///
  /// 走折射的档位为 `false`：着色器 uniform 里带着这一块自己的光照与按压值，
  /// 各块滤镜不同，共享背景输入没有意义。
  final bool sharedSampling;

  @override
  bool operator ==(Object other) =>
      other is GlassSurfaceRecord &&
      other.bounds == bounds &&
      other.sharedSampling == sharedSampling;

  @override
  int get hashCode => Object.hash(bounds, sharedSampling);
}

/// 一次读数：当前屏幕上的玻璃有多少、占多大。
///
/// 照 g1455 的 `GlassLoad` 思路做，但**只保留我们能诚实地算出来的字段** ——
/// 它那套 `verdict` 依赖实测的硬件成本表，本仓库没有那个数据，编一个出来
/// 只会误导。
@immutable
class GlassLoad {
  const GlassLoad({
    required this.surfaceCount,
    required this.sharedSamplingCount,
    required this.rectAreaLogical,
    required this.screensOfGlass,
    required this.overlappingPairs,
  });

  const GlassLoad.empty()
      : surfaceCount = 0,
        sharedSamplingCount = 0,
        rectAreaLogical = 0,
        screensOfGlass = 0,
        overlappingPairs = 0;

  /// 屏上的玻璃面板数。
  final int surfaceCount;

  /// 其中多少块的滤镜与同类一致、**可以**共用一次背景采样。
  final int sharedSamplingCount;

  /// 全部玻璃的矩形面积和（逻辑像素²）。
  ///
  /// **不扣重叠** —— 相互重叠的部分会被重复计入。重叠多少见 [overlappingPairs]。
  final double rectAreaLogical;

  /// 玻璃面积和相对屏幕面积的比例。可以超过 1（一屏玻璃叠了好几层）。
  final double screensOfGlass;

  /// 相互重叠的玻璃**对数**。
  ///
  /// 这个数字不参与观感评判，它是 [GlassLedger] 存在的另一半理由：共享背景
  /// 采样（`BackdropFilter.grouped`）的前提是**互不重叠**，引擎文档明确警告
  /// 重叠的滤镜共用 key 会「看起来只有一个滤镜生效」。这个计数让那个前提从
  /// 「我以为」变成「量出来的」。
  final int overlappingPairs;

  /// 走折射、因而**不能**共享采样的面板数。
  int get refractingCount => surfaceCount - sharedSamplingCount;

  @override
  String toString() =>
      'GlassLoad(面板 $surfaceCount 块，其中可共享采样 $sharedSamplingCount 块，'
      '面积 ${rectAreaLogical.toStringAsFixed(0)} px²，'
      '${screensOfGlass.toStringAsFixed(2)} 屏，重叠 $overlappingPairs 对)';
}

/// 从几何记录算出读数 —— **纯函数**，不碰任何全局状态。
///
/// - [surfaces] 每块的全局矩形与"滤镜是否同类一致"；
/// - [viewSize] 屏幕（视图）尺寸，用来折算 [GlassLoad.screensOfGlass]。
///
/// [viewSize] 退化为零或负数时，占比按 0 处理而不是除出 `Infinity` ——
/// 首帧拿到空尺寸是常事，那不该变成一个 NaN 传遍调用方。
GlassLoad resolveGlassLoad({
  required List<GlassSurfaceRecord> surfaces,
  required Size viewSize,
}) {
  if (surfaces.isEmpty) return const GlassLoad.empty();

  var shared = 0;
  var area = 0.0;
  for (final surface in surfaces) {
    if (surface.sharedSampling) shared++;
    area += surface.bounds.width * surface.bounds.height;
  }

  var overlapping = 0;
  for (var i = 0; i < surfaces.length; i++) {
    for (var j = i + 1; j < surfaces.length; j++) {
      if (surfaces[i].bounds.overlaps(surfaces[j].bounds)) overlapping++;
    }
  }

  final viewArea = viewSize.width * viewSize.height;
  return GlassLoad(
    surfaceCount: surfaces.length,
    sharedSamplingCount: shared,
    rectAreaLogical: area,
    screensOfGlass: viewArea > 0 ? area / viewArea : 0,
    overlappingPairs: overlapping,
  );
}

/// 玻璃面板向 [GlassLedger] 暴露自己的方式。
///
/// 几何**按需现取**而不是登记时快照：玻璃移动（滚动、拖拽）不该让登记册
/// 频繁通知，而读数本来就是要读"此刻"的位置。
abstract interface class GlassSurfaceProbe {
  /// 此刻在全局坐标里的矩形；还没布局或已卸载时返回 `null`。
  Rect? probeGlassBounds();

  /// 见 [GlassSurfaceRecord.sharedSampling]。
  bool get probeSharesSampling;
}

/// 屏上玻璃的登记册。
///
/// ## 它为什么存在
///
/// 玻璃的开销是**面板数量与面积**的函数，而这两样都没法靠读代码估准 ——
/// 一屏同时挂几块、占多少、有没有叠在一起，只有量出来才知道。先有数字再决定
/// 优化哪，是这个类唯一的目的。
///
/// ## 它不做什么
///
/// **不参与任何渲染决策。** 没有阈值、没有自动降级、没有"太多了就关掉"。
/// 那些属于策略层（`GlassQuality` 与将来的 tier），混进来会让"读数"和
/// "行为"互相纠缠，两样都难改。
class GlassLedger extends ChangeNotifier {
  /// 全局登记册。玻璃分散在几十个页面、还可能在 Overlay 里，逐层传一个
  /// InheritedWidget 不现实。
  static final GlassLedger instance = GlassLedger();

  final Set<GlassSurfaceProbe> _probes = <GlassSurfaceProbe>{};

  /// 已登记的面板数（不问几何，因此不会触发布局）。
  int get registeredCount => _probes.length;

  /// 登记一块玻璃。重复登记同一个对象无副作用。
  void register(GlassSurfaceProbe probe) {
    if (_probes.add(probe)) notifyListeners();
  }

  /// 注销。没登记过时无副作用。
  void unregister(GlassSurfaceProbe probe) {
    if (_probes.remove(probe)) notifyListeners();
  }

  /// 读一次此刻的屏上玻璃。取不到几何的面板（未布局/已卸载）**不计入** ——
  /// 把一个尺寸为零的矩形算进去会拉低平均、也污染重叠判定。
  GlassLoad read({required Size viewSize}) => resolveGlassLoad(
        surfaces: <GlassSurfaceRecord>[
          for (final probe in _probes)
            if (probe.probeGlassBounds() case final bounds?)
              if (!bounds.isEmpty)
                GlassSurfaceRecord(
                  bounds: bounds,
                  sharedSampling: probe.probeSharesSampling,
                ),
        ],
        viewSize: viewSize,
      );

  /// 仅供测试：清空登记。
  @visibleForTesting
  void resetForTest() {
    _probes.clear();
    notifyListeners();
  }
}
