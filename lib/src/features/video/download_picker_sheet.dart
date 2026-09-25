import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/video.dart';
import '../../domain/series_name.dart';

/// 用户在下载弹窗里确认后的选择。
class DownloadPickerResult {
  const DownloadPickerResult({
    required this.source,
    required this.episodeIds,
    required this.groupName,
    this.openDownloads = false,
  });

  /// 「我的下载」按钮的返回值：不带片源/勾选，只表达"去缓存页"这个意图。
  const DownloadPickerResult.openDownloads()
      : source = const VideoSource(quality: '', url: ''),
        episodeIds = const {},
        groupName = '',
        openDownloads = true;

  /// 选中的画质（下载时按同名清晰度取源，取不到再退回第一个可下载源）。
  final VideoSource source;

  /// 选中的剧集 id。
  final Set<String> episodeIds;

  /// 目标分组名；为空表示不分组。
  final String groupName;

  /// 用户点的是「我的下载」而不是「下载(N)」：调用方据此跳去缓存页。
  final bool openDownloads;
}

/// 打开下载弹窗，返回用户的选择（`null` = 关掉了弹窗）。
///
/// 必须是 `showDialog` + **透明遮罩**（不是 `showModalBottomSheet`）：
/// 用 bottom sheet 承载时，路由会额外铺两层东西 —— 半透明遮罩（`Colors.black54`）
/// 和一层 640 宽、整屏高的 sheet 底板（`surfaceContainerLow`），
/// 用户看到的就是「弹窗后面有一大块黑底铺满画面中间」。
/// 这里遮罩透明（仍可点外部关闭，只是不可见），屏幕上只剩中间那张卡片。
Future<DownloadPickerResult?> showDownloadPickerSheet(
  BuildContext context, {
  required List<VideoSource> sources,
  required List<VideoCard> episodes,
  required String currentId,
  required String suggestedGroupName,
  required bool initialAutoGroup,
  required bool initialNameFromSeries,
  required bool initialTraditional,
  required Set<String> groupNames,
}) =>
    showDialog<DownloadPickerResult>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => DownloadPickerSheet(
        sources: sources,
        episodes: episodes,
        currentId: currentId,
        suggestedGroupName: suggestedGroupName,
        initialAutoGroup: initialAutoGroup,
        initialNameFromSeries: initialNameFromSeries,
        initialTraditional: initialTraditional,
        groupNames: groupNames,
      ),
    );

/// 下载弹窗（参考 b 站「离线缓存」）。
///
/// 与 b 站一致的几处形态，都是刻意为之：
/// - **悬浮居中卡片**：四周留白 + 圆角，不是贴着屏幕底边的 bottom sheet；
/// - **紧凑画质下拉**：宽度贴合文字，不撑满整行；
/// - **「正片」分段小标题**：把集数列表和顶部设置区分开；
/// - **分组配置在「正片」标题上方**：默认收起、只占一行，集数再多也不会被滚出视野；
/// - **圆角卡片式分集行**：选中项用主题色描边，而不是加一个复选框
///   （复选框会把标题挤短，b 站这里就是整行可点）。
///
/// 拆成独立 widget 是因为它有一整套本地状态（画质、勾选集、自动分组、组名编辑），
/// 塞在 `video_actions.dart` 里既长又没法单独测试。
class DownloadPickerSheet extends StatefulWidget {
  const DownloadPickerSheet({
    super.key,
    required this.sources,
    required this.episodes,
    required this.currentId,
    required this.suggestedGroupName,
    required this.initialAutoGroup,
    required this.initialNameFromSeries,
    required this.initialTraditional,
    required this.groupNames,
  });

  /// 可下载的片源（已剔除 HLS 清单）。
  final List<VideoSource> sources;

  /// 剧集列表（当前集在第一位）。
  final List<VideoCard> episodes;

  /// 当前播放集的 id（保证任何时候都至少勾着它）。
  final String currentId;

  /// 自动分组时的预填组名（已按设置里的来源 / 繁简规则算好）。
  final String suggestedGroupName;

  final bool initialAutoGroup;
  final bool initialNameFromSeries;
  final bool initialTraditional;

  /// 已存在的分组名，用来提示「会复用已有分组」还是「会新建」。
  final Set<String> groupNames;

  @override
  State<DownloadPickerSheet> createState() => _DownloadPickerSheetState();
}

class _DownloadPickerSheetState extends State<DownloadPickerSheet> {
  late VideoSource _source;
  late bool _autoGroup;
  late bool _nameFromSeries;
  late bool _traditional;
  late final TextEditingController _nameController;
  late Set<String> _selected;
  var _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _source = widget.sources.first;
    _autoGroup = widget.initialAutoGroup;
    _nameFromSeries = widget.initialNameFromSeries;
    _traditional = widget.initialTraditional;
    // 默认只勾当前集：多数时候用户只要这一集，想批量再自己全选。
    _selected = {widget.currentId};
    _nameController = TextEditingController(text: _renderName(widget.suggestedGroupName));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _renderName(String raw) => _traditional ? toTraditionalForGroupName(raw) : raw;

  /// 当前生效的组名：输入框为空时退回建议名。
  String get _currentName {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) return _renderName(widget.suggestedGroupName);
    return _traditional ? toTraditionalForGroupName(raw) : raw;
  }

  bool get _allSelected => widget.episodes.every((episode) => _selected.contains(episode.id));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = _currentName;
    final existing = widget.groupNames.contains(name);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.sizeOf(context);
    // 卡片尺寸**全部用视口比例**（不写固定逻辑值）。
    //
    // 之前写的是 `(media.width * .42).clamp(460, 560)`：那个下界 460 在 200% 缩放下
    // 等于 920 物理像素，于是卡片占了半个屏幕宽 —— 用户看到的"整个画面中间都是它"。
    // 固定逻辑值在不同 DPI 下差别巨大，比例才与 DPI 无关。
    //
    // 数值照抄 b 站「离线缓存」弹窗的实测：占高 63.8%（1090x695 于 1734x1089 窗口）。
    // 这里 maxHeight 只作**兜底上限**；内容少时卡片更矮（真正的高度由内容决定），
    // 所以正常情况下占高会小于 64%。
    final available = media.height * .64;
    return Dialog(
      // 悬浮卡片：圆角 + 四周留白，不贴屏幕边缘（b 站的「离线缓存」就是这种小卡片）。
      backgroundColor: scheme.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: media.width * .44, maxHeight: available),
        child: SizedBox(
          // 测试与调试都靠这个 key 定位卡片本体（它有确定的宽高）。
          key: const ValueKey('download-picker-card'),
          width: media.width * .42,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            // 中间区**按内容**取高，超出上限才滚动。
            //
            // 踩过的坑：只要把滚动区挂在 `Flexible` 下，父级就会把"剩余可用高度"
            // 全分给它，内容多寡都一样高（占满卡片）。所以这里用**非 Flexible** 的
            // ConstrainedBox 夹住上限，高度由内容决定、超限才滚。
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(title: l10n.download),
                ConstrainedBox(
                  // 中间区的上限 = 卡片高度上限 - 头部 - 底栏（约 140）。
                  // 要扣掉这两个固定区，否则内容多时中间区把 Column 顶破。
                  constraints: BoxConstraints(maxHeight: available - 140),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                // 画质与全选同一行：画质是紧凑下拉（宽度贴合文字），
                // 不再用撑满整行的描边输入框。
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Row(
                    children: [
                      // 窄卡片时下拉要能收缩，否则「下拉 + 全选」会把这一行挤破
                      // （实测卡片收到 460 宽时溢出 11px）。
                      Flexible(child: _QualityDropdown(sources: widget.sources, value: _source, onChanged: (value) => setState(() => _source = value))),
                      const SizedBox(width: 12),
                      // 「全选」：视觉三态，动作按意图判断（详见 onChanged 注释）。
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              tristate: true,
                              value: _allSelected ? true : _selected.isEmpty ? false : null,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (_) => setState(() {
                                if (_allSelected) {
                                  // 至少留下当前集，避免出现「一集都没选」的空状态。
                                  _selected = {widget.currentId};
                                } else {
                                  _selected.addAll(widget.episodes.map((episode) => episode.id));
                                }
                              }),
                            ),
                            Flexible(child: Text(l10n.downloadSelectAllEpisodes, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 分组配置：默认收起、只占一行，放在「正片」标题**上面**。
                //
                // 它原来在集数列表**下面** —— 集数一多，中间区就是一个滚动列表，
                // 「新建分组」会被滚到看不见的地方，用户根本找不到这个功能。
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 24),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: Text(l10n.downloadGroupSection),
                    subtitle: Text(
                      _autoGroup ? (existing ? l10n.willUseExistingGroup(name) : l10n.willCreateNewGroup(name)) : l10n.noGrouping,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: [
                      SwitchListTile(
                        value: _autoGroup,
                        dense: true,
                        onChanged: (value) => setState(() => _autoGroup = value),
                        title: Text(l10n.autoGroupDownloads),
                        subtitle: Text(l10n.autoGroupDownloadsDescription),
                      ),
                      if (_autoGroup) ...[
                        SwitchListTile(
                          value: _nameFromSeries,
                          dense: true,
                          onChanged: (value) => setState(() {
                            _nameFromSeries = value;
                            if (!_nameEdited) _nameController.text = _renderName(suggestGroupName(title: widget.episodes.first.title, seriesName: inferSeriesName(widget.episodes.first.title), useSeriesName: value));
                          }),
                          title: Text(l10n.groupNameFromSeries),
                        ),
                        SwitchListTile(
                          value: _traditional,
                          dense: true,
                          onChanged: (value) => setState(() {
                            _traditional = value;
                            if (!_nameEdited) _nameController.text = _renderName(suggestGroupName(title: widget.episodes.first.title, seriesName: inferSeriesName(widget.episodes.first.title), useSeriesName: _nameFromSeries));
                          }),
                          title: Text(l10n.groupNameTraditional),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                          child: TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: l10n.groupName,
                              border: const OutlineInputBorder(),
                              helperText: existing ? l10n.willUseExistingGroup(name) : l10n.willCreateNewGroup(name),
                            ),
                            onChanged: (value) => setState(() => _nameEdited = true),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 「正片」分段小标题（b 站这个位置就是它）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.mainEpisodes, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
                // 集数列表：外层已经是可滚动容器，这里直接用 Column 铺开
                // （不要再套一层 ListView，嵌套滚动视图会在小窗口下报约束错误）。
                for (var index = 0; index < widget.episodes.length; index++)
                  Padding(
                    padding: EdgeInsets.only(left: 24, right: 24, bottom: index == widget.episodes.length - 1 ? 8 : 6),
                    child: _EpisodeRow(
                      title: widget.episodes[index].title,
                      // 当前正在播的那一集标出来，避免"这集到底勾没勾"的疑惑。
                      current: widget.episodes[index].id == widget.currentId,
                      selected: _selected.contains(widget.episodes[index].id),
                      onTap: () => setState(() {
                        final id = widget.episodes[index].id;
                        if (_selected.contains(id)) {
                          // 至少保留一集，不允许清空。
                          if (_selected.length > 1) _selected.remove(id);
                        } else {
                          _selected.add(id);
                        }
                      }),
                    ),
                  ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                // 底栏两个按钮（b 站同款）：左边去看已下好的，右边才是开始下载。
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          // 「我的下载」不改动选择，只告诉调用方"把用户带到缓存页"。
                          onPressed: () => Navigator.pop(context, const DownloadPickerResult.openDownloads()),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                          child: Text(l10n.myDownloads, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _selected.isEmpty ? null : _submit,
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                          child: Text(l10n.downloadCountButton(_selected.length), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() => Navigator.pop(
        context,
        DownloadPickerResult(
          source: _source,
          episodeIds: {..._selected},
          groupName: _autoGroup ? _currentName : '',
        ),
      );
}

/// 紧凑画质下拉：宽度贴合当前选项文字（加一点内边距），不撑满整行。
///
/// 用自绘而不是 `DropdownButtonFormField` —— 后者的 `isExpanded` 一开就吃掉整行宽，
/// 关掉又会在长画质名（「4K · HDR 10」「1080P 高码率」）时溢出。
/// 这里用 [IntrinsicWidth] 让宽度跟着最长选项走，再夹一个上限。
class _QualityDropdown extends StatelessWidget {
  const _QualityDropdown({required this.sources, required this.value, required this.onChanged});

  final List<VideoSource> sources;
  final VideoSource value;
  final ValueChanged<VideoSource> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      // 给下拉一个浅色圆角底：只留文字 + 箭头会看不出"这里能点"，
      // 参考里也是一个淡淡的圆角容器（不是描边输入框）。
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // 用 isExpanded 让下拉在窄卡片里收缩（配 Flexible 使用），
          // 否则长画质名（「4K · HDR 10」）会把这一行顶破。
          child: DropdownButtonHideUnderline(
            child: DropdownButton<VideoSource>(
              value: value,
              isDense: true,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 10),
              icon: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.arrow_drop_down, size: 22)),
              dropdownColor: theme.colorScheme.surfaceContainerHigh,
              style: theme.textTheme.bodyMedium,
              items: [
                for (final item in sources)
                  DropdownMenuItem(value: item, child: Text(item.quality, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (next) => next == null ? null : onChanged(next),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗标题条：居中标题 + 右上角关闭（b 站同款）。
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Stack(
          children: [
            Center(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(tooltip: AppLocalizations.of(context)!.cancel, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ),
            ),
          ],
        ),
      );
}

/// 分集行：整行可点的圆角卡片，选中时描主题色边（b 站不给复选框）。
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.title, required this.selected, required this.current, required this.onTap});

  final String title;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: .10) : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
              if (current) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                  child: Text(l10n.downloadCurrentOnly, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
