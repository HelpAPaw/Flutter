import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/animal_type.dart';
import '../models/help_tag.dart';

/// Chip picker for [HelpTag] values.
///
/// Shared by the new-signal form, the edit screen, the onboarding gate and
/// notification settings, so the vocabulary is rendered identically everywhere
/// and adding a tag needs no UI change. The two sides mean different things —
/// on a signal it is "this is needed", on a profile "I can do this" — but the
/// control is the same, so only the labels differ.
class HelpTagSelector extends StatelessWidget {
  const HelpTagSelector({
    super.key,
    required this.selected,
    required this.onToggle,
    this.maxSelection,
    this.semanticPrefix = 'helpTag',
  });

  /// Currently selected [HelpTag.code] values.
  final List<String> selected;

  final ValueChanged<String> onToggle;

  /// Cap on how many may be selected, or null for no cap. Once reached, the
  /// unselected chips are disabled rather than silently ignoring taps.
  final int? maxSelection;

  /// Prefix for the per-chip accessibility identifier. Element-based device
  /// automation is far more reliable than tapping coordinates, and these chips
  /// are small — so every one gets a stable label.
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final atLimit =
        maxSelection != null && selected.length >= maxSelection!;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: HelpTag.values.map((tag) {
        final isSelected = selected.contains(tag.code);
        return Semantics(
          identifier: '$semanticPrefix.${tag.code}',
          selected: isSelected,
          button: true,
          child: FilterChip(
            avatar: Icon(tag.icon, size: 18),
            label: Text(tag.label(l10n)),
            selected: isSelected,
            // Disabling rather than hiding keeps the layout stable as the user
            // approaches the cap, so chips don't jump under their finger.
            onSelected: (!isSelected && atLimit)
                ? null
                : (_) => onToggle(tag.code),
          ),
        );
      }).toList(),
    );
  }
}

/// Vertical [HelpTag] picker with the "what am I signing up for" descriptions.
///
/// Used by the onboarding gate, where people choose tags once and then live
/// with the resulting notifications — so the guidance travels with the choice
/// rather than living in a help page nobody opens.
class HelpTagChoiceList extends StatelessWidget {
  const HelpTagChoiceList({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: HelpTag.values.map((tag) {
        return Semantics(
          identifier: 'helperTag.${tag.code}',
          child: CheckboxListTile(
            value: selected.contains(tag.code),
            onChanged: (_) => onToggle(tag.code),
            title: Text(tag.label(l10n)),
            subtitle: Text(tag.helperDescription(l10n)),
            secondary: Icon(tag.icon),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        );
      }).toList(),
    );
  }
}

/// Chip picker for [AnimalType] values.
///
/// [singleSelect] switches between a signal's "this is one animal" choice and a
/// user's "these are the species I can help" preference.
class AnimalTypeSelector extends StatelessWidget {
  const AnimalTypeSelector({
    super.key,
    required this.selected,
    required this.onToggle,
    this.singleSelect = false,
    this.semanticPrefix = 'animalType',
  });

  final List<String> selected;
  final ValueChanged<String> onToggle;
  final bool singleSelect;
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: AnimalType.values.map((type) {
        final isSelected = selected.contains(type.code);
        return Semantics(
          identifier: '$semanticPrefix.${type.code}',
          selected: isSelected,
          button: true,
          child: ChoiceChip(
            avatar: Icon(type.icon, size: 18),
            label: Text(type.label(l10n)),
            selected: isSelected,
            // In single-select mode, re-tapping the chosen chip does nothing
            // rather than clearing it: the field is mandatory, so there is no
            // valid empty state to return to.
            onSelected: (singleSelect && isSelected)
                ? null
                : (_) => onToggle(type.code),
          ),
        );
      }).toList(),
    );
  }
}
