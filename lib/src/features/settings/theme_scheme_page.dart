import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_theme.dart';
import '../../core/settings.dart';
import 'settings_controller.dart';


Color _hexColor(String hex) {
  final value = int.tryParse('ff$hex', radix: 16);
  return value == null ? const Color(0xff6750a4) : Color(value);
}

/// Shows the colour scheme picker as a floating dialog, matching the reference
/// layout instead of pushing a full page.
Future<void> showThemeSchemeDialog(BuildContext context) => showDialog<void>(context: context, builder: (dialogContext) => const _ThemeSchemeDialog());

Future<void> _pickCustomColor(BuildContext context, SettingsController controller, String initial) async {
  final textController = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppLocalizations.of(dialogContext)!.colorScheme),
      content: TextField(
        controller: textController,
        autofocus: true,
        maxLength: 6,
        decoration: const InputDecoration(prefixText: '#', counterText: ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel)),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, textController.text.trim()), child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel)),
      ],
    ),
  );
  if (value == null || value.length != 6) return;
  await controller.saveChanges((current) => current.copyWith(useMonetColors: false, themeColor: AppThemeColor.custom, customThemeColor: value.toUpperCase()));
}

class _ThemeSchemeDialog extends ConsumerWidget {
  const _ThemeSchemeDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final presets = AppThemeColor.values.where((color) => color != AppThemeColor.custom).toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.colorScheme, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final color in presets)
                    _Swatch(
                      color: color.seedColor(settings.customThemeColor),
                      label: themeColorLabel(l10n, color),
                      selected: !settings.useMonetColors && settings.themeColor == color,
                      onTap: () => controller.saveChanges((current) => current.copyWith(useMonetColors: false, themeColor: color)),
                    ),
                  _Swatch(
                    color: _hexColor(settings.customThemeColor),
                    label: l10n.colorCustom,
                    icon: Icons.colorize_outlined,
                    selected: !settings.useMonetColors && settings.themeColor == AppThemeColor.custom,
                    onTap: () => _pickCustomColor(context, controller, settings.customThemeColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 配色方案的名称。公开给设置页当行副标题用（与「站点 / 代理」行的写法一致）。
String themeColorLabel(AppLocalizations l10n, AppThemeColor color) => switch (color) {
      AppThemeColor.rose => l10n.colorRose,
      AppThemeColor.blue => l10n.colorBlue,
      AppThemeColor.teal => l10n.colorTeal,
      AppThemeColor.amber => l10n.colorAmber,
      AppThemeColor.green => l10n.colorGreen,
      AppThemeColor.orange => l10n.colorOrange,
      AppThemeColor.indigo => l10n.colorIndigo,
      AppThemeColor.pink => l10n.colorPink,
      AppThemeColor.purple => l10n.colorPurple,
      AppThemeColor.white => l10n.colorWhite,
      AppThemeColor.custom => l10n.colorCustom,
    };

/// A colour swatch with its name underneath, matching the reference layout.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label, required this.selected, required this.onTap, this.icon});

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = icon != null ? color : (ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: icon != null ? colorScheme.surfaceContainerHighest : color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? colorScheme.onSurface : colorScheme.outlineVariant, width: selected ? 3 : 1),
              ),
              child: icon != null
                  ? Icon(icon, color: foreground)
                  : (selected ? Icon(Icons.check, color: foreground) : null),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null),
            ),
          ],
        ),
      ),
    );
  }
}
