import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/playback_speed_policy.dart';
import '../../core/settings.dart';
import '../../core/video_decoders.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';

class PlayerSettingsPage extends ConsumerWidget {
  const PlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(settingsProvider.notifier);
    final libmpv = settings.playerEngine == PlayerEngine.libMpv;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.playerSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SettingsCardList(children: [
            SettingsCardItem(title: l10n.hardwareDecode, subtitle: l10n.hardwareDecodeDescription, leading: const Icon(Icons.settings_input_hdmi_outlined), trailing: Switch(value: settings.hardwareAcceleration, onChanged: libmpv ? (value) => controller.saveChanges((current) => current.copyWith(hardwareAcceleration: value)) : null)),
            _OptionTile(icon: Icons.memory_outlined, title: l10n.hardwareDecoder, description: l10n.hardwareDecoderDescription, value: settings.hardwareDecoder, enabled: libmpv && settings.hardwareAcceleration, onTap: libmpv && settings.hardwareAcceleration ? () => _pickHardwareDecoder(context, ref, settings) : null),
            _OptionTile(icon: Icons.developer_board_outlined, title: l10n.decoder, value: _engineLabel(l10n, settings.playerEngine), enabled: true, onTap: () => _pickEngine(context, ref, settings)),
            _OptionTile(icon: Icons.video_settings_outlined, title: l10n.videoRenderer, value: _rendererLabel(l10n, settings.videoRenderer), enabled: libmpv, onTap: libmpv ? () => _pickRenderer(context, ref, settings) : null),
            _ViewMenuTile(icon: Icons.layers_outlined, title: l10n.viewSettings, value: settings.videoView, enabled: libmpv, label: (value) => _viewLabel(l10n, value), onSelected: (value) => controller.saveChanges((current) => current.copyWith(videoView: value))),
            _OptionTile(icon: Icons.tune_outlined, title: l10n.customParameters, value: settings.customParameters.isEmpty ? l10n.none : '${settings.customParameters.length}', enabled: libmpv, onTap: libmpv ? () => _editCustomParameters(context, ref, settings) : null),
            _OptionTile(icon: Icons.auto_awesome_outlined, title: l10n.superResolution, value: _superResolutionLabel(l10n, settings.superResolutionMode), enabled: libmpv, onTap: libmpv ? () => _pickSuperResolution(context, ref, settings) : null),
          ]),
        ],
      ),
    );
  }

  String _engineLabel(AppLocalizations l10n, PlayerEngine engine) => switch (engine) {
        PlayerEngine.exoPlayer => l10n.exoPlayer,
        PlayerEngine.avPlayer => l10n.avPlayer,
        PlayerEngine.libMpv => l10n.libMpv,
      };

  String _rendererLabel(AppLocalizations l10n, VideoRenderer renderer) => switch (renderer) {
        VideoRenderer.auto => l10n.rendererAuto,
        VideoRenderer.gpu => l10n.rendererGpu,
        VideoRenderer.gpuNext => l10n.rendererGpuNext,
        VideoRenderer.mediacodecEmbed => l10n.rendererMediacodecEmbed,
      };

  String _viewLabel(AppLocalizations l10n, VideoView view) => switch (view) {
        VideoView.platformView => l10n.viewPlatformView,
        VideoView.surfaceView => l10n.viewSurfaceView,
      };

  String _superResolutionLabel(AppLocalizations l10n, SuperResolutionMode mode) => switch (mode) {
        SuperResolutionMode.off => l10n.superResolutionOff,
        SuperResolutionMode.efficiency => l10n.superResolutionEfficiency,
        SuperResolutionMode.quality => l10n.superResolutionQuality,
        SuperResolutionMode.natural => l10n.superResolutionNatural,
      };

  String _superResolutionDescription(AppLocalizations l10n, SuperResolutionMode mode) => switch (mode) {
        SuperResolutionMode.off => l10n.superResolutionOffDescription,
        SuperResolutionMode.efficiency => l10n.superResolutionEfficiencyDescription,
        SuperResolutionMode.quality => l10n.superResolutionQualityDescription,
        SuperResolutionMode.natural => l10n.superResolutionNaturalDescription,
      };

  // 下面四个都是「内容少」的单选项：原先各自是一个独立页面，进一次、选一下、再退回来，
  // 代价比设置本身还大。现在统一弹层。只有改动了才写盘，取消或选了原值都不动配置。
  Future<void> _pickEngine(BuildContext context, WidgetRef ref, AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showOptionSettingsDialog<PlayerEngine>(
      context: context,
      title: l10n.decoder,
      current: settings.playerEngine,
      options: PlaybackSpeedPolicy.isHarmonyOs ? const [PlayerEngine.libMpv] : PlayerEngineX.available,
      label: (value) => _engineLabel(l10n, value),
    );
    if (selected == null || selected == settings.playerEngine) return;
    await ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(playerEngine: selected));
  }

  Future<void> _pickRenderer(BuildContext context, WidgetRef ref, AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showOptionSettingsDialog<VideoRenderer>(
      context: context,
      title: l10n.videoRenderer,
      current: settings.videoRenderer,
      options: VideoRenderer.values,
      label: (value) => _rendererLabel(l10n, value),
    );
    if (selected == null || selected == settings.videoRenderer) return;
    await ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(videoRenderer: selected));
  }

  Future<void> _pickHardwareDecoder(BuildContext context, WidgetRef ref, AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final decoders = hardwareDecodersFor(Localizations.localeOf(context));
    final selected = await showOptionSettingsDialog<String>(
      context: context,
      title: l10n.hardwareDecoder,
      description: l10n.hardwareDecoderHint,
      current: knownHardwareDecoder(settings.hardwareDecoder),
      options: decoders.keys.toList(growable: false),
      label: (value) => value,
      optionDescription: (value) => decoders[value] ?? '',
    );
    if (selected == null || selected == settings.hardwareDecoder) return;
    await ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(hardwareDecoder: selected));
  }

  Future<void> _pickSuperResolution(BuildContext context, WidgetRef ref, AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showOptionSettingsDialog<SuperResolutionMode>(
      context: context,
      title: l10n.superResolution,
      current: settings.superResolutionMode,
      options: SuperResolutionMode.values,
      label: (value) => _superResolutionLabel(l10n, value),
      optionDescription: (value) => _superResolutionDescription(l10n, value),
    );
    if (selected == null || selected == settings.superResolutionMode) return;
    await ref.read(settingsProvider.notifier).saveChanges((current) => current.copyWith(superResolutionMode: selected));
  }

  Future<void> _editCustomParameters(BuildContext context, WidgetRef ref, AppSettings settings) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _CustomParametersDialog(initial: settings.customParameters.join('\n')),
    );
    if (result == null) return;
    final parameters = result
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    await ref
        .read(settingsProvider.notifier)
        .saveChanges((current) => current.copyWith(customParameters: parameters));
  }
}

class _CustomParametersDialog extends StatefulWidget {
  const _CustomParametersDialog({required this.initial});
  final String initial;

  @override
  State<_CustomParametersDialog> createState() => _CustomParametersDialogState();
}

class _CustomParametersDialogState extends State<_CustomParametersDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.customParameters),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 8,
        decoration: InputDecoration(hintText: l10n.customParametersHint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(l10n.save)),
      ],
    );
  }
}

class _OptionTile extends SettingsCardItem {
  _OptionTile({required IconData icon, required String title, required String value, required bool enabled, required VoidCallback? onTap, String? description, Widget? trailing})
      : super(title: title, subtitle: description == null ? value : '$description · $value', leading: Icon(icon), trailing: trailing ?? const Icon(Icons.chevron_right), onTap: onTap, enabled: enabled);
}

class _ViewMenuTile extends SettingsMenuItem<VideoView> {
  _ViewMenuTile({required IconData icon, required String title, required VideoView value, required bool enabled, required String Function(VideoView) label, required ValueChanged<VideoView> onSelected})
      : super(title: title, subtitle: label(value), leading: Icon(icon), value: value, options: VideoView.values, label: label, onSelected: onSelected, enabled: enabled);
}
