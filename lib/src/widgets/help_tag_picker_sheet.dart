import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/help_tag.dart';
import 'help_tag_selector.dart';

/// Asks which needs a case has now (master spec §4.2).
///
/// > As needs are resolved, the case holder removes/completes tags and the next
/// > priority becomes active.
///
/// A sheet rather than a trip through the edit screen, because the two answer
/// different questions. The edit screen carries the **reporter's account of what
/// they saw** — the title, the description, the photos, the phone number — and
/// stays theirs. What the case *needs right now* changes as the case is worked,
/// and belongs to whoever is working it.
///
/// Wraps [HelpTagSelector] rather than restating the chips: the cap, the
/// disabled-at-limit behaviour and the per-chip accessibility labels are all
/// decisions that should exist once.
///
/// Returns null when the sheet was dismissed, which means "change nothing" —
/// distinct from an empty selection, which the confirm button refuses because a
/// case with no needs is one nobody can be matched to.
///
/// Returns a **List**, not a Set: array order is priority order on the signal
/// document (SPECIFICATION 4.4, `helpNeededTags[0]` is the category), and a Set
/// at the boundary would leave that resting on LinkedHashSet insertion order.
Future<List<HelpTag>?> showHelpTagPicker(
  BuildContext context, {
  required List<HelpTag> initial,
}) {
  return showModalBottomSheet<List<HelpTag>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _HelpTagPickerSheet(initial: initial),
  );
}

class _HelpTagPickerSheet extends StatefulWidget {
  const _HelpTagPickerSheet({required this.initial});

  final List<HelpTag> initial;

  @override
  State<_HelpTagPickerSheet> createState() => _HelpTagPickerSheetState();
}

class _HelpTagPickerSheetState extends State<_HelpTagPickerSheet> {
  /// Codes rather than [HelpTag]s, because that is what [HelpTagSelector]
  /// speaks and what the signal document stores — and because **order is
  /// priority** (`helpNeededTags[0]` is the case's category, SPECIFICATION
  /// §4.4). A `Set<HelpTag>` at the boundary would silently discard that
  /// ordering, so the list is what is edited here and the set is only the
  /// caller's convenience.
  late final List<String> _selected =
      widget.initial.map((tag) => tag.code).toList();

  void _toggle(String code) {
    setState(() {
      if (!_selected.remove(code)) _selected.add(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.helpNeeded,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: HelpTagSelector(
                  selected: _selected,
                  onToggle: _toggle,
                  maxSelection: HelpTag.maxPerSignal,
                  semanticPrefix: 'editHelpTag',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  // `isValidHelpNeededTags()` bounds the list at 1..3 when the
                  // field is present, so an empty selection is a denied write
                  // rather than a cleared field. Disabling the button says so
                  // before the round trip.
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                            HelpTag.fromCodes(_selected),
                          ),
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
