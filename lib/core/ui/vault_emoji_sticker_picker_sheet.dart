import 'package:flutter/foundation.dart';
import 'package:emoji_extension/emoji_extension.dart' as emoji;
import 'package:flutter/material.dart';

import '../../models/vault_theme.dart';
import '../../state/sticker_store.dart';
import '../../state/vault_theme_store.dart';
import '../stickers/animated_emoji.dart';
import '../stickers/sticker_cache.dart';
import '../stickers/sticker_catalog.dart';

VaultThemeColors _pickerTheme(BuildContext context) {
  return Theme.of(context).extension<VaultThemeColors>() ??
      VaultThemeStore.activePalette.colors;
}

enum _PickerSurface { emoji, vault }

class VaultEmojiStickerPickerSheet extends StatefulWidget {
  const VaultEmojiStickerPickerSheet({
    super.key,
    required this.onSelectEmoji,
    required this.onSelectSticker,
    required this.onLongPressSticker,
    this.emojiOnly = false,
    this.headerTitle,
    this.headerSubtitle,
  });

  final ValueChanged<String> onSelectEmoji;
  final Future<void> Function(StickerAsset sticker) onSelectSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;
  final bool emojiOnly;
  final String? headerTitle;
  final String? headerSubtitle;

  @override
  State<VaultEmojiStickerPickerSheet> createState() =>
      _VaultEmojiStickerPickerSheetState();
}

class _VaultEmojiStickerPickerSheetState
    extends State<VaultEmojiStickerPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  _PickerSurface _surface = _PickerSurface.emoji;
  emoji.Group _selectedGroup = _emojiSections.first.group;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.emojiOnly) {
      _surface = _PickerSurface.emoji;
    }
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
  }

  List<_EmojiEntry> get _visibleEmojis {
    if (_searchQuery.isNotEmpty) {
      return _allEmojiEntries
          .where((entry) => entry.searchIndex.contains(_searchQuery))
          .toList(growable: false);
    }
    return _emojiEntriesByGroup[_selectedGroup] ?? const <_EmojiEntry>[];
  }

  Future<void> _handleEmojiTap(String value) async {
    widget.onSelectEmoji(value);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _showSkinTonePicker(
    _EmojiEntry entry,
    Offset globalPosition,
  ) async {
    final variants = _toneFamilyFor(entry);
    if (variants.length <= 1) {
      await _handleEmojiTap(entry.value);
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = _pickerTheme(dialogContext);
        final media = MediaQuery.of(dialogContext);
        final width = (variants.length * 44.0 + 16)
            .clamp(120.0, 320.0)
            .toDouble();
        final left = (globalPosition.dx - (width / 2))
            .clamp(12.0, media.size.width - width - 12.0)
            .toDouble();
        final top =
            (globalPosition.dy < 92
                    ? (globalPosition.dy + 18)
                    : (globalPosition.dy - 66))
                .clamp(12.0, media.size.height - 70.0)
                .toDouble();
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(dialogContext),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: Material(
                  color: theme.surface,
                  elevation: 18,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: theme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final variant in variants)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  Navigator.pop(dialogContext, variant.value),
                              child: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                child: Text(
                                  variant.value,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected.isEmpty) return;
    await _handleEmojiTap(selected);
  }

  Future<void> _handleStickerTap(StickerAsset sticker) async {
    await widget.onSelectSticker(sticker);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _pickerTheme(context);
    final emojis = _visibleEmojis;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A0024),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: theme.border)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.headerTitle ??
                              (_surface == _PickerSurface.emoji
                              ? 'Emoji'
                              : 'Vault Animated Emoji'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.headerSubtitle ??
                              (_surface == _PickerSurface.emoji
                              ? 'Search every emoji, browse by category, or long-press for skin tones.'
                              : 'Recents, favorites, and your animated Vault reactions.'),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.emojiOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: SegmentedButton<_PickerSurface>(
                  segments: const [
                    ButtonSegment<_PickerSurface>(
                      value: _PickerSurface.emoji,
                      icon: Icon(Icons.emoji_emotions_outlined),
                      label: Text('Emoji'),
                    ),
                    ButtonSegment<_PickerSurface>(
                      value: _PickerSurface.vault,
                      icon: Icon(Icons.auto_awesome_outlined),
                      label: Text('Vault'),
                    ),
                  ],
                  selected: <_PickerSurface>{_surface},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(theme.header),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return theme.surfaceAlt;
                      }
                      return theme.surface.withValues(alpha: 0.72);
                    }),
                    side: WidgetStatePropertyAll(
                      BorderSide(color: theme.border),
                    ),
                  ),
                  onSelectionChanged: (selection) {
                    setState(() => _surface = selection.first);
                  },
                ),
              ),
            if (_surface == _PickerSurface.emoji) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search emojis',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white54,
                            ),
                          ),
                    filled: true,
                    fillColor: theme.surface.withValues(alpha: 0.82),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: theme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: theme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: theme.accent),
                    ),
                  ),
                ),
              ),
              if (_searchQuery.isEmpty)
                SizedBox(
                  height: 54,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final section = _emojiSections[index];
                      final selected = section.group == _selectedGroup;
                      return Tooltip(
                        message: section.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () =>
                              setState(() => _selectedGroup = section.group),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: selected
                                  ? theme.surfaceAlt
                                  : theme.surface.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected ? theme.accent : theme.border,
                              ),
                            ),
                            child: Icon(
                              section.icon,
                              size: 20,
                              color: selected ? theme.accent : theme.textSoft,
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: _emojiSections.length,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'Search Results'
                            : _emojiSections
                                  .firstWhere(
                                    (section) =>
                                        section.group == _selectedGroup,
                                  )
                                  .label,
                        style: TextStyle(
                          color: theme.header,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '${emojis.length}',
                      style: TextStyle(
                        color: theme.textSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: emojis.isEmpty
                    ? Center(
                        child: Text(
                          'No emojis match that search yet.',
                          style: TextStyle(color: theme.textSoft),
                        ),
                      )
                    : _EmojiGrid(
                        emojis: emojis,
                        onTapEmoji: (entry) => _handleEmojiTap(entry.value),
                        onLongPressEmoji: (entry, position) =>
                            _showSkinTonePicker(entry, position),
                      ),
              ),
            ] else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  children: [
                    _StickerCollectionSection(
                      title: 'Recent',
                      source: StickerStore.recentsNotifier,
                      emptyLabel: 'No recent Vault reactions yet.',
                      onTapSticker: _handleStickerTap,
                      onLongPressSticker: widget.onLongPressSticker,
                    ),
                    const SizedBox(height: 18),
                    _StickerCollectionSection(
                      title: 'Favorites',
                      source: StickerStore.favoritesNotifier,
                      emptyLabel: 'No favorites yet.',
                      onTapSticker: _handleStickerTap,
                      onLongPressSticker: widget.onLongPressSticker,
                    ),
                    if (StickerCatalog.vaultAnimatedEmojiPack != null) ...[
                      const SizedBox(height: 18),
                      _VaultPackSection(
                        pack: StickerCatalog.vaultAnimatedEmojiPack!,
                        onTapSticker: _handleStickerTap,
                        onLongPressSticker: widget.onLongPressSticker,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
    required this.emojis,
    required this.onTapEmoji,
    required this.onLongPressEmoji,
  });

  final List<_EmojiEntry> emojis;
  final ValueChanged<_EmojiEntry> onTapEmoji;
  final Future<void> Function(_EmojiEntry entry, Offset globalPosition)
  onLongPressEmoji;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width ~/ 52).clamp(6, 9);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      itemCount: emojis.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final entry = emojis[index];
        return GestureDetector(
          onLongPressStart: (details) async {
            if (!entry.supportsSkinTone) return;
            await onLongPressEmoji(entry, details.globalPosition);
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTapEmoji(entry),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Center(
                child: Text(
                  entry.value,
                  style: const TextStyle(fontSize: 28, height: 1),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StickerCollectionSection extends StatelessWidget {
  const _StickerCollectionSection({
    required this.title,
    required this.source,
    required this.emptyLabel,
    required this.onTapSticker,
    required this.onLongPressSticker,
  });

  final String title;
  final ValueListenable<List<StickerRef>> source;
  final String emptyLabel;
  final Future<void> Function(StickerAsset sticker) onTapSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<StickerRef>>(
      valueListenable: source,
      builder: (context, refs, _) {
        final stickers = <StickerAsset>[];
        for (final ref in refs) {
          final sticker = StickerCatalog.findSticker(ref.packId, ref.stickerId);
          if (sticker != null) {
            stickers.add(sticker);
          }
        }
        return _StickerSectionShell(
          title: title,
          subtitle: stickers.isEmpty ? emptyLabel : null,
          child: stickers.isEmpty
              ? null
              : _StickerGrid(
                  stickers: stickers,
                  onTapSticker: onTapSticker,
                  onLongPressSticker: onLongPressSticker,
                ),
        );
      },
    );
  }
}

class _VaultPackSection extends StatelessWidget {
  const _VaultPackSection({
    required this.pack,
    required this.onTapSticker,
    required this.onLongPressSticker,
  });

  final StickerPack pack;
  final Future<void> Function(StickerAsset sticker) onTapSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;

  @override
  Widget build(BuildContext context) {
    return _StickerSectionShell(
      title: pack.title,
      subtitle: pack.description,
      child: _StickerGrid(
        stickers: pack.stickers,
        onTapSticker: onTapSticker,
        onLongPressSticker: onLongPressSticker,
      ),
    );
  }
}

class _StickerSectionShell extends StatelessWidget {
  const _StickerSectionShell({required this.title, this.subtitle, this.child});

  final String title;
  final String? subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = _pickerTheme(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.header,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
        if (child != null) ...[const SizedBox(height: 10), child!],
      ],
    );
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({
    required this.stickers,
    required this.onTapSticker,
    required this.onLongPressSticker,
  });

  final List<StickerAsset> stickers;
  final Future<void> Function(StickerAsset sticker) onTapSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width ~/ 96).clamp(3, 6);
    final previewSize = (width / crossAxisCount * 0.42).clamp(50.0, 72.0);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stickers.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        StickerCache.precacheSticker(context, sticker);
        return InkWell(
          onTap: () => onTapSticker(sticker),
          onLongPress: () => onLongPressSticker(sticker),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: SizedBox.square(
                dimension: previewSize,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _StickerThumb(sticker: sticker),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StickerThumb extends StatelessWidget {
  const _StickerThumb({required this.sticker});

  final StickerAsset sticker;

  @override
  Widget build(BuildContext context) {
    if (sticker.type == StickerAssetType.staticImage ||
        sticker.type == StickerAssetType.animatedWebp) {
      return Image.asset(sticker.assetPath, fit: BoxFit.contain);
    }
    if (sticker.type == StickerAssetType.animatedEmoji) {
      return AnimatedEmoji(assetPath: sticker.assetPath);
    }
    return AnimatedEmoji(assetPath: sticker.assetPath);
  }
}

class _EmojiSection {
  const _EmojiSection({
    required this.group,
    required this.label,
    required this.icon,
  });

  final emoji.Group group;
  final String label;
  final IconData icon;
}

class _EmojiEntry {
  const _EmojiEntry({
    required this.data,
    required this.searchIndex,
    required this.toneKey,
    required this.toneModifierCount,
    required this.supportsSkinTone,
  });

  final emoji.Emoji data;
  final String searchIndex;
  final String toneKey;
  final int toneModifierCount;
  final bool supportsSkinTone;

  String get value => data.value;
}

const List<_EmojiSection> _emojiSections = <_EmojiSection>[
  _EmojiSection(
    group: emoji.Group.smileysAndEmotion,
    label: 'Smileys & Emotion',
    icon: Icons.emoji_emotions_outlined,
  ),
  _EmojiSection(
    group: emoji.Group.peopleAndBody,
    label: 'People & Body',
    icon: Icons.waving_hand_outlined,
  ),
  _EmojiSection(
    group: emoji.Group.animalsAndNature,
    label: 'Animals & Nature',
    icon: Icons.pets_outlined,
  ),
  _EmojiSection(
    group: emoji.Group.foodAndDrink,
    label: 'Food & Drink',
    icon: Icons.icecream_outlined,
  ),
  _EmojiSection(
    group: emoji.Group.travelAndPlaces,
    label: 'Travel & Places',
    icon: Icons.travel_explore_outlined,
  ),
  _EmojiSection(
    group: emoji.Group.activities,
    label: 'Activities',
    icon: Icons.sports_esports_outlined,
  ),
  _EmojiSection(
    group: emoji.Group.objects,
    label: 'Objects',
    icon: Icons.lightbulb_outline_rounded,
  ),
  _EmojiSection(
    group: emoji.Group.symbols,
    label: 'Symbols',
    icon: Icons.favorite_border_rounded,
  ),
  _EmojiSection(
    group: emoji.Group.flags,
    label: 'Flags',
    icon: Icons.flag_outlined,
  ),
];

final List<_EmojiEntry> _allEmojiEntries = _buildEmojiEntries();
final Map<emoji.Group, List<_EmojiEntry>> _emojiEntriesByGroup =
    _buildEmojiGroupMap(_allEmojiEntries);
final Map<String, List<_EmojiEntry>> _emojiToneFamilies = _buildToneFamilyMap(
  _allEmojiEntries,
);

List<_EmojiEntry> _buildEmojiEntries() {
  final seen = <String>{};
  final entries = <_EmojiEntry>[];
  for (final item in emoji.Emojis.all) {
    if (item.group == emoji.Group.component ||
        item.status == emoji.Status.component ||
        item.status == emoji.Status.unqualified) {
      continue;
    }
    final value = item.value.trim();
    if (value.isEmpty || !seen.add(value)) continue;
    final toneKey = _normalizeToneKey(value);
    final toneModifierCount = _toneModifierCount(value);
    entries.add(
      _EmojiEntry(
        data: item,
        searchIndex: _buildEmojiSearchIndex(item),
        toneKey: toneKey,
        toneModifierCount: toneModifierCount,
        supportsSkinTone: false,
      ),
    );
  }

  final toneFamilies = _buildToneFamilyMap(entries);
  return entries
      .map(
        (entry) => _EmojiEntry(
          data: entry.data,
          searchIndex: entry.searchIndex,
          toneKey: entry.toneKey,
          toneModifierCount: entry.toneModifierCount,
          supportsSkinTone:
              (toneFamilies[entry.toneKey]?.length ?? 0) > 1 &&
              entry.toneModifierCount <= 1,
        ),
      )
      .toList(growable: false);
}

Map<emoji.Group, List<_EmojiEntry>> _buildEmojiGroupMap(
  List<_EmojiEntry> entries,
) {
  final map = <emoji.Group, List<_EmojiEntry>>{};
  for (final section in _emojiSections) {
    map[section.group] = entries
        .where((entry) => entry.data.group == section.group)
        .toList(growable: false);
  }
  return map;
}

Map<String, List<_EmojiEntry>> _buildToneFamilyMap(List<_EmojiEntry> entries) {
  final grouped = <String, List<_EmojiEntry>>{};
  for (final entry in entries) {
    if (entry.toneModifierCount > 1) continue;
    grouped.putIfAbsent(entry.toneKey, () => <_EmojiEntry>[]).add(entry);
  }
  final toneOrder = <emoji.SkinTone?, int>{
    null: 0,
    emoji.SkinTone.light: 1,
    emoji.SkinTone.mediumLight: 2,
    emoji.SkinTone.medium: 3,
    emoji.SkinTone.mediumDark: 4,
    emoji.SkinTone.dark: 5,
  };
  for (final family in grouped.values) {
    family.sort((a, b) {
      final aRank = toneOrder[a.data.skinTone] ?? 99;
      final bRank = toneOrder[b.data.skinTone] ?? 99;
      return aRank.compareTo(bRank);
    });
  }
  return grouped;
}

List<_EmojiEntry> _toneFamilyFor(_EmojiEntry entry) {
  return _emojiToneFamilies[entry.toneKey] ?? <_EmojiEntry>[entry];
}

String _buildEmojiSearchIndex(emoji.Emoji item) {
  final buffer = StringBuffer()
    ..write(item.value)
    ..write(' ')
    ..write(item.name);
  if ((item.appleName ?? '').trim().isNotEmpty) {
    buffer
      ..write(' ')
      ..write(item.appleName!.trim());
  }
  for (final alias in item.alsoKnownAs) {
    buffer
      ..write(' ')
      ..write(alias);
  }
  for (final shortcode in item.shortcodes) {
    for (final value in shortcode.values) {
      buffer
        ..write(' ')
        ..write(value);
    }
  }
  return buffer.toString().toLowerCase();
}

String _normalizeToneKey(String value) {
  return String.fromCharCodes(
    value.runes.where((rune) {
      if (rune == 0xFE0F || rune == 0xFE0E) return false;
      return rune < 0x1F3FB || rune > 0x1F3FF;
    }),
  );
}

int _toneModifierCount(String value) {
  return value.runes.where((rune) => rune >= 0x1F3FB && rune <= 0x1F3FF).length;
}
