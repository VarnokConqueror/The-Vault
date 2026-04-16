import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ui/settings_sections.dart';
import '../models/vault_theme.dart';
import '../state/date_time_format_store.dart';
import '../state/text_scale_store.dart';
import '../state/vault_theme_store.dart';

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  late Color _background;
  late Color _surface;
  late Color _accent;
  late Color _accent2;
  late Color _header;

  @override
  void initState() {
    super.initState();
    _syncDraftFromStore();
  }

  void _syncDraftFromStore() {
    final custom = VaultThemeStore.config.customPalette;
    _background = custom.background;
    _surface = custom.surface;
    _accent = custom.accent;
    _accent2 = custom.accent2;
    _header = custom.header;
  }

  Future<void> _applyCustomTheme() async {
    final isDark =
        ThemeData.estimateBrightnessForColor(_background) == Brightness.dark;
    final backgroundAlt = Color.lerp(_background, _surface, 0.35) ?? _surface;
    final surfaceAlt = Color.lerp(_surface, _background, 0.18) ?? _surface;
    final border = Color.lerp(_accent, _background, 0.7) ?? _accent;
    final text = isDark ? const Color(0xFFF8F2FF) : const Color(0xFF14091D);
    final textSoft = Color.lerp(text, _background, 0.28) ?? text;
    final buttonText =
        ThemeData.estimateBrightnessForColor(_accent) == Brightness.dark
        ? const Color(0xFFF8F2FF)
        : const Color(0xFF14091D);

    await VaultThemeStore.setCustomPalette(
      VaultThemePalette(
        id: VaultThemePalette.customId,
        name: 'Custom',
        description: 'Your own color set',
        background: _background,
        backgroundAlt: backgroundAlt,
        surface: _surface,
        surfaceAlt: surfaceAlt,
        accent: _accent,
        accent2: _accent2,
        header: _header,
        border: border,
        text: text,
        textSoft: textSoft,
        buttonText: buttonText,
        danger: const Color(0xFFFF4D6D),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Custom theme saved.')));
  }

  Future<void> _resetToDefault() async {
    await VaultThemeStore.reset();
    if (!mounted) return;
    setState(_syncDraftFromStore);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Theme reset to Obsidian Rose.')),
    );
  }

  Future<void> _editColor({
    required String label,
    required Color initialColor,
    required ValueChanged<Color> onChanged,
  }) async {
    var hue = HSLColor.fromColor(initialColor).hue;
    var saturation = HSLColor.fromColor(initialColor).saturation;
    var lightness = HSLColor.fromColor(initialColor).lightness;

    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final preview = HSLColor.fromAHSL(
              1,
              hue,
              saturation,
              lightness,
            ).toColor();
            return AlertDialog(
              title: Text(label),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: preview,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _colorToHex(preview),
                            style: TextStyle(
                              color:
                                  ThemeData.estimateBrightnessForColor(
                                        preview,
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFF14091D),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: _HueWheel(
                          hue: hue,
                          onChanged: (value) {
                            setDialogState(() => hue = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Saturation',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Slider(
                        value: saturation,
                        onChanged: (value) {
                          setDialogState(() => saturation = value);
                        },
                      ),
                      Text(
                        'Lightness',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Slider(
                        value: lightness,
                        onChanged: (value) {
                          setDialogState(() => lightness = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, preview),
                  child: const Text('Use Color'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    setState(() {
      onChanged(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VaultThemeStore.themeNotifier,
      builder: (context, _) {
        final config = VaultThemeStore.config;
        final active = config.activePalette;
        final presets = VaultThemePalette.presets;
        final customPreview = _buildPreviewPalette();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Themes'),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: _resetToDefault,
                child: const Text('Reset'),
              ),
            ],
          ),
          body: SettingsPageBody(
            children: [
              SettingsHeroCard(
                title: active.name,
                body:
                    'Preset themes are one tap away, and custom colors now use visual pickers instead of manual code entry.',
                trailing: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SmallSwatch(color: active.accent),
                    _SmallSwatch(color: active.accent2),
                    _SmallSwatch(color: active.header),
                    _SmallSwatch(color: active.surface),
                    _SmallSwatch(color: active.background),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SettingsSectionLabel(text: 'Interface'),
              const SizedBox(height: 8),
              SettingsCard(
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: TextScaleStore.scaleNotifier,
                    builder: (context, scale, _) {
                      final percent = (scale * 100).round();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Text Size',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  '$percent%',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Scale all app text without stretching the cards and controls.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Slider(
                              min: TextScaleStore.minScale,
                              max: TextScaleStore.maxScale,
                              divisions: 7,
                              value: scale,
                              onChanged: (value) {
                                TextScaleStore.setScale(value);
                              },
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Preview: The Vault keeps the chrome compact while the text stays readable.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: active.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: () => TextScaleStore.reset(),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SettingsDivider(),
                  ValueListenableBuilder<VaultDateTimeFormatConfig>(
                    valueListenable: DateTimeFormatStore.formatNotifier,
                    builder: (context, formatConfig, _) {
                      final previewSample = DateTime(2026, 4, 8, 21, 17);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date & Time Format',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose how message timestamps and chat list dates are shown across the Vault.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Time',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: Text(
                                    DateTimeFormatStore.sampleTimeLabel(
                                      VaultTimeFormat.twelveHour,
                                    ),
                                  ),
                                  selected:
                                      formatConfig.timeFormat ==
                                      VaultTimeFormat.twelveHour,
                                  onSelected: (_) {
                                    DateTimeFormatStore.setTimeFormat(
                                      VaultTimeFormat.twelveHour,
                                    );
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(
                                    DateTimeFormatStore.sampleTimeLabel(
                                      VaultTimeFormat.twentyFourHour,
                                    ),
                                  ),
                                  selected:
                                      formatConfig.timeFormat ==
                                      VaultTimeFormat.twentyFourHour,
                                  onSelected: (_) {
                                    DateTimeFormatStore.setTimeFormat(
                                      VaultTimeFormat.twentyFourHour,
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Date',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in VaultDateFormat.values)
                                  ChoiceChip(
                                    label: Text(
                                      DateTimeFormatStore.sampleDateLabel(
                                        option,
                                      ),
                                    ),
                                    selected: formatConfig.dateFormat == option,
                                    onSelected: (_) {
                                      DateTimeFormatStore.setDateFormat(option);
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: active.surfaceAlt.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: active.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: active.accent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Preview: ${DateTimeFormatStore.formatMessageTimestamp(context, previewSample)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: active.text,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton(
                                    onPressed: () =>
                                        DateTimeFormatStore.reset(),
                                    child: const Text('Reset'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SettingsSectionLabel(text: 'Preset Themes'),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumn = constraints.maxWidth >= 430;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: presets.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: twoColumn ? 2 : 1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: twoColumn ? 1.28 : 2.05,
                    ),
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      return _PresetThemeCard(
                        preset: preset,
                        selected: config.selectedId == preset.id,
                        onTap: () => VaultThemeStore.setPreset(preset.id),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              const SettingsSectionLabel(text: 'Custom Theme Studio'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      customPreview.backgroundAlt,
                      customPreview.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: customPreview.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Theme Preview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: customPreview.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Shape the palette visually, then judge it against a faux Vault thread before you save it.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: customPreview.textSoft,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _PreviewPill(
                          label: 'Surface',
                          color: customPreview.surfaceAlt,
                          textColor: customPreview.text,
                        ),
                        _PreviewPill(
                          label: 'Accent',
                          color: customPreview.accent,
                          textColor: customPreview.buttonText,
                        ),
                        _PreviewPill(
                          label: 'Alt Accent',
                          color: customPreview.accent2,
                          textColor: customPreview.buttonText,
                        ),
                        _PreviewPill(
                          label: 'Header',
                          color: customPreview.header,
                          textColor:
                              ThemeData.estimateBrightnessForColor(
                                    customPreview.header,
                                  ) ==
                                  Brightness.dark
                              ? Colors.white
                              : const Color(0xFF14091D),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ThemeConversationPreview(palette: customPreview),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: customPreview.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: customPreview.border.withValues(alpha: 0.9),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                            color: customPreview.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'If the bubbles, header, and composer all feel readable here, the palette will usually hold up across the app.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: customPreview.textSoft,
                                    height: 1.35,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _EditableColorTile(
                      label: 'Background',
                      subtitle: 'Overall app backdrop',
                      color: _background,
                      onTap: () => _editColor(
                        label: 'Background',
                        initialColor: _background,
                        onChanged: (value) => _background = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EditableColorTile(
                      label: 'Surface',
                      subtitle: 'Cards and panels',
                      color: _surface,
                      onTap: () => _editColor(
                        label: 'Surface',
                        initialColor: _surface,
                        onChanged: (value) => _surface = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EditableColorTile(
                      label: 'Accent',
                      subtitle: 'Primary buttons and highlights',
                      color: _accent,
                      onTap: () => _editColor(
                        label: 'Accent',
                        initialColor: _accent,
                        onChanged: (value) => _accent = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EditableColorTile(
                      label: 'Secondary Accent',
                      subtitle: 'Secondary highlight color',
                      color: _accent2,
                      onTap: () => _editColor(
                        label: 'Secondary Accent',
                        initialColor: _accent2,
                        onChanged: (value) => _accent2 = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EditableColorTile(
                      label: 'Header Color',
                      subtitle: 'Section titles and emphasis text',
                      color: _header,
                      onTap: () => _editColor(
                        label: 'Header Color',
                        initialColor: _header,
                        onChanged: (value) => _header = value,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(_syncDraftFromStore);
                            },
                            icon: const Icon(Icons.refresh_outlined),
                            label: const Text('Reload Custom'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _applyCustomTheme,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Use Custom'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SettingsFooter(),
            ],
          ),
        );
      },
    );
  }

  VaultThemePalette _buildPreviewPalette() {
    final backgroundAlt = Color.lerp(_background, _surface, 0.35) ?? _surface;
    final surfaceAlt = Color.lerp(_surface, _background, 0.18) ?? _surface;
    final border = Color.lerp(_accent, _background, 0.7) ?? _accent;
    final isDark =
        ThemeData.estimateBrightnessForColor(_background) == Brightness.dark;
    final text = isDark ? const Color(0xFFF8F2FF) : const Color(0xFF14091D);
    final textSoft = Color.lerp(text, _background, 0.28) ?? text;
    final buttonText =
        ThemeData.estimateBrightnessForColor(_accent) == Brightness.dark
        ? const Color(0xFFF8F2FF)
        : const Color(0xFF14091D);
    return VaultThemePalette(
      id: VaultThemePalette.customId,
      name: 'Custom',
      description: 'Your own color set',
      background: _background,
      backgroundAlt: backgroundAlt,
      surface: _surface,
      surfaceAlt: surfaceAlt,
      accent: _accent,
      accent2: _accent2,
      header: _header,
      border: border,
      text: text,
      textSoft: textSoft,
      buttonText: buttonText,
      danger: const Color(0xFFFF4D6D),
    );
  }

  static String _colorToHex(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(value.length - 6).toUpperCase()}';
  }
}

class _PresetThemeCard extends StatelessWidget {
  const _PresetThemeCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final VaultThemePalette preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [preset.backgroundAlt, preset.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: selected ? preset.accent : preset.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: preset.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: preset.accent, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              preset.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: preset.textSoft,
                height: 1.3,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                _SmallSwatch(color: preset.accent),
                const SizedBox(width: 8),
                _SmallSwatch(color: preset.accent2),
                const SizedBox(width: 8),
                _SmallSwatch(color: preset.header),
                const SizedBox(width: 8),
                _SmallSwatch(color: preset.surface),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableColorTile extends StatelessWidget {
  const _EditableColorTile({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: theme.textSoft, height: 1.3),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _ThemeSettingsScreenState._colorToHex(color),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.textSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Icon(Icons.colorize_outlined, color: theme.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallSwatch extends StatelessWidget {
  const _SmallSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ThemeConversationPreview extends StatelessWidget {
  const _ThemeConversationPreview({required this.palette});

  final VaultThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [palette.background, palette.backgroundAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.arrow_back_rounded, color: palette.text, size: 20),
                const SizedBox(width: 12),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [palette.accent, palette.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'N',
                      style: TextStyle(
                        color: palette.buttonText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nyx of the Court',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'End-to-end encrypted',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                _PreviewChip(
                  color: palette.accent,
                  label: 'LIVE',
                  textColor: palette.buttonText,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              children: [
                _ThemePreviewBubble(
                  palette: palette,
                  sender: 'Nyx',
                  body: 'Meet me by the east gate at dusk.',
                  alignEnd: false,
                  bubbleColor: palette.surfaceAlt,
                  textColor: palette.text,
                  metaColor: palette.textSoft,
                ),
                const SizedBox(height: 10),
                _ThemePreviewBubble(
                  palette: palette,
                  sender: 'You',
                  body: 'Understood. I will arrive under silence.',
                  alignEnd: true,
                  bubbleColor: palette.accent,
                  textColor: palette.buttonText,
                  metaColor: palette.buttonText.withValues(alpha: 0.78),
                ),
                const SizedBox(height: 10),
                _ThemePreviewBubble(
                  palette: palette,
                  sender: 'Nyx',
                  body: 'Bring the sigil and keep this thread clean.',
                  alignEnd: false,
                  bubbleColor: palette.surface,
                  textColor: palette.text,
                  metaColor: palette.textSoft,
                  trailingChip: _PreviewChip(
                    color: palette.accent2,
                    label: 'Secure',
                    textColor: palette.buttonText,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: 0.98),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: palette.border.withValues(alpha: 0.9),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        color: palette.textSoft,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Message Nyx...',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textSoft),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: palette.buttonText,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePreviewBubble extends StatelessWidget {
  const _ThemePreviewBubble({
    required this.palette,
    required this.sender,
    required this.body,
    required this.alignEnd,
    required this.bubbleColor,
    required this.textColor,
    required this.metaColor,
    this.trailingChip,
  });

  final VaultThemePalette palette;
  final String sender;
  final String body;
  final bool alignEnd;
  final Color bubbleColor;
  final Color textColor;
  final Color metaColor;
  final Widget? trailingChip;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(alignEnd ? 18 : 6),
              bottomRight: Radius.circular(alignEnd ? 6 : 18),
            ),
            border: Border.all(
              color: alignEnd
                  ? bubbleColor.withValues(alpha: 0.2)
                  : palette.border.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sender,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: metaColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (trailingChip != null) ...[
                    const SizedBox(width: 8),
                    trailingChip!,
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                alignEnd ? 'Delivered now' : 'Just now',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: metaColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HueWheel extends StatelessWidget {
  const _HueWheel({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;
  static const double _size = 190;

  void _updateFromPosition(Offset localPosition) {
    final center = const Offset(_size / 2, _size / 2);
    final vector = localPosition - center;
    final distance = vector.distance;
    final outerRadius = _size / 2;
    final innerRadius = outerRadius - 28;
    if (distance < innerRadius || distance > outerRadius) return;
    final angle = math.atan2(vector.dy, vector.dx);
    final degrees = (angle * 180 / math.pi + 360) % 360;
    onChanged(degrees);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => _updateFromPosition(details.localPosition),
      onPanUpdate: (details) => _updateFromPosition(details.localPosition),
      child: CustomPaint(
        size: const Size.square(_size),
        painter: _HueWheelPainter(hue: hue),
      ),
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.width / 2;
    final ringWidth = 28.0;
    final innerRadius = outerRadius - ringWidth;

    final ringPaint = Paint()
      ..shader = SweepGradient(
        colors: List<Color>.generate(
          13,
          (index) => HSVColor.fromAHSV(1, index * 30.0, 1, 1).toColor(),
        ),
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;

    canvas.drawCircle(center, outerRadius - ringWidth / 2, ringPaint);

    final markerAngle = hue * math.pi / 180;
    final markerRadius = outerRadius - ringWidth / 2;
    final markerOffset = Offset(
      center.dx + math.cos(markerAngle) * markerRadius,
      center.dy + math.sin(markerAngle) * markerRadius,
    );

    final markerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(markerOffset, 10, markerPaint);
    canvas.drawCircle(
      markerOffset,
      6,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );

    canvas.drawCircle(
      center,
      innerRadius - 2,
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );
    final previewColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawCircle(center, innerRadius - 18, Paint()..color = previewColor);
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}
