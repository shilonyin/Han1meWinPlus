import 'settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/playback_speed_policy.dart';
import '../../core/settings.dart';
import '../../core/video_decoders.dart';
import '../account/account_controller.dart';
import '../explore/explore_controller.dart';
import 'settings_controller.dart';

class SiteSettingsPage extends ConsumerWidget {
  const SiteSettingsPage({super.key});

  static const _hosts = ['https://hanime1.com', 'https://hanimeone.me', 'https://hanime1.me', 'https://javchu.com'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final current = settings.comicMode ? 'https://hanimeone.me' : settings.baseUrl;
    final hosts = settings.comicMode ? const ['https://hanimeone.me'] : _hosts;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.site)),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text(l10n.site, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            tiles: [
              for (final host in hosts)
                SettingsTile<String>.radioTile(
                  radioValue: host,
                  groupValue: current,
                  title: Text(host),
                  onChanged: (value) async {
                    if (value == null || value == current) return;
                    await ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(baseUrl: value, videoBaseUrl: settings.comicMode ? settings.videoBaseUrl : value, useCustomMirrorSite: false, customMirrorSite: ''));
                    ref.invalidate(accountProvider);
                    ref.invalidate(homeSectionsProvider);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DecoderSettingsPage extends ConsumerWidget {
  const DecoderSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsProvider).valueOrNull?.playerEngine ?? PlayerEngine.libMpv;
    return _RadioSettingsPage<PlayerEngine>(
      title: l10n.decoder,
      current: current,
      options: PlaybackSpeedPolicy.isHarmonyOs ? const [PlayerEngine.libMpv] : PlayerEngineX.available,
      label: (value) => switch (value) { PlayerEngine.exoPlayer => l10n.exoPlayer, PlayerEngine.avPlayer => l10n.avPlayer, PlayerEngine.libMpv => l10n.libMpv },
      onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(playerEngine: value)),
    );
  }
}

class RendererSettingsPage extends ConsumerWidget {
  const RendererSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsProvider).valueOrNull?.videoRenderer ?? VideoRenderer.auto;
    return _RadioSettingsPage<VideoRenderer>(
      title: l10n.videoRenderer,
      current: current,
      options: VideoRenderer.values,
      label: (value) => switch (value) { VideoRenderer.auto => l10n.rendererAuto, VideoRenderer.gpu => l10n.rendererGpu, VideoRenderer.gpuNext => l10n.rendererGpuNext, VideoRenderer.mediacodecEmbed => l10n.rendererMediacodecEmbed },
      onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(videoRenderer: value)),
    );
  }
}

class HardwareDecoderSettingsPage extends ConsumerWidget {
  const HardwareDecoderSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = knownHardwareDecoder(ref.watch(settingsProvider).valueOrNull?.hardwareDecoder);
    final decoders = hardwareDecodersFor(Localizations.localeOf(context));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.hardwareDecoder)),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text(l10n.hardwareDecoderHint, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            tiles: [
              for (final decoder in decoders.entries)
                SettingsTile<String>.radioTile(
                  radioValue: decoder.key,
                  groupValue: current,
                  title: Text(decoder.key),
                  description: Text(decoder.value),
                  onChanged: (value) {
                    if (value != null) ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(hardwareDecoder: value));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 新番预告的数据源：默认站点的预告表常年不可用，所以默认选「自动」，
/// 由 `PreviewsPage` 在加载失败时换到 Getchu。
class PreviewSourceSettingsPage extends ConsumerWidget {
  const PreviewSourceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto';
    return _RadioSettingsPage<String>(
      title: l10n.previewSource,
      current: current,
      options: const ['auto', 'default', 'getchu'],
      label: (value) => switch (value) { 'getchu' => l10n.previewSourceGetchu, 'default' => l10n.previewSourceDefault, _ => l10n.previewSourceAuto },
      description: (value) => switch (value) { 'getchu' => l10n.previewSourceGetchuDescription, 'default' => l10n.previewSourceDefaultDescription, _ => l10n.previewSourceAutoDescription },
      onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(previewSource: value)),
    );
  }
}

class SuperResolutionSettingsPage extends ConsumerWidget {
  const SuperResolutionSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsProvider).valueOrNull?.superResolutionMode ?? SuperResolutionMode.off;
    return _RadioSettingsPage<SuperResolutionMode>(
      title: l10n.superResolution,
      current: current,
      options: SuperResolutionMode.values,
      label: (value) => _superResolutionLabel(l10n, value),
      description: (value) => _superResolutionDescription(l10n, value),
      onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(superResolutionMode: value)),
    );
  }
}

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

class _RadioSettingsPage<T> extends StatelessWidget {
  const _RadioSettingsPage({required this.title, required this.current, required this.options, required this.label, required this.onChanged, this.description});

  final String title;
  final T current;
  final List<T> options;
  final String Function(T value) label;
  final String Function(T value)? description;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SettingsList(
          sections: [
            SettingsSection(
              title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              tiles: [
                for (final option in options)
                  SettingsTile<T>.radioTile(radioValue: option, groupValue: current, title: Text(label(option)), description: description == null ? null : Text(description!(option)), onChanged: (value) { if (value != null) onChanged(value); }),
              ],
            ),
          ],
        ),
      );
}
