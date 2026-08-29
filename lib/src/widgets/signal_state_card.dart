import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/animal_type.dart';
import '../models/help_tag.dart';
import '../models/signal.dart';
import '../models/signal_status.dart';
import '../models/signal_urgency.dart';
import 'level_chip.dart';

/// The coordination state of a signal, in one bounded surface.
///
/// Urgency, status, who is responsible and what the animal needs used to be
/// four sibling blocks with four headings, spread down the page between the
/// description and the timeline. They are not four things: they are the answer
/// to "where has this got to", and they are the part of the screen that changes
/// while everything above it stays fixed. Drawing a border around them is what
/// makes that legible — and it is why the urgency rail is on the card rather
/// than on the page.
///
/// The rail carries urgency **colour only**. Status keeps the neutral outlined
/// treatment [LevelChip] defines for it, because status and urgency run on
/// opposite scales and colouring both put two contradictory traffic lights on
/// one card (see the class doc on [LevelChip]).
///
/// This widget renders; it does not write. [owner] is whatever the caller's
/// signal-owner block builds, and [onManage] opens the sheet that owns editing.
class SignalStateCard extends StatelessWidget {
  const SignalStateCard({
    super.key,
    required this.signal,
    required this.owner,
    required this.canCoordinate,
    required this.busy,
    required this.onManage,
  });

  final Signal signal;

  /// The signal-owner row and its actions.
  final Widget owner;

  /// Whether this viewer may change urgency, status or the help tags.
  ///
  /// A UI affordance only — `firestore.rules` draws the same line, so hiding
  /// the button just means nobody meets the refusal.
  final bool canCoordinate;

  final bool busy;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final urgency = SignalUrgency.fromCode(signal.urgency);

    final species = AnimalType.fromCode(signal.animalType);
    // Unknown codes are dropped: one means the signal came from a newer build,
    // and there is no label for it here.
    final tags = HelpTag.fromCodes(signal.helpNeededTags);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        // The rail has to be exactly as tall as the content beside it, and the
        // content's height is whatever its text wraps to.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: urgency.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LabelledRow(
                        label: l10n.urgency,
                        trailing: canCoordinate
                            ? Semantics(
                                label: l10n.change,
                                button: true,
                                enabled: !busy,
                                child: IconButton(
                                  icon: const Icon(Icons.tune, size: 20),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: busy ? null : onManage,
                                ),
                              )
                            : null,
                        // Aligned, not bare: `_LabelledRow` hands its value an
                        // Expanded, and a `LevelChip` is a Container — left to
                        // itself it stretches into a full-width bar instead of
                        // reading as a badge.
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: LevelChip.urgency(
                            color: urgency.color,
                            label: urgency.label(l10n),
                            iconAsset: urgency.pinAsset,
                          ),
                        ),
                      ),
                      _divider(scheme),
                      // Status is the one field that does not take the label
                      // column: a three-step track needs the full width to put
                      // its labels under its steps, and squeezing it into the
                      // ~230dp left over would wrap every one of them. The
                      // label still starts on the same left edge as the others,
                      // so the column reads as a column.
                      Text(l10n.status, style: _labelStyle(context)),
                      const SizedBox(height: 8),
                      _StatusTrack(status: SignalStatus.fromCode(signal.status)),
                      _divider(scheme),
                      _LabelledRow(
                        label: l10n.signalOwner,
                        child: owner,
                      ),
                      // Two rows, not one. The species and the help tags used
                      // to share a single "Help needed" heading, which made
                      // "Help needed: Dog" — and a dog is what the signal is
                      // about, not what it needs. They are two different facts
                      // and the label column is what makes saying so free.
                      if (species case final species?) ...[
                        _divider(scheme),
                        _LabelledRow(
                          label: l10n.animalType,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _Tag(
                                icon: species.icon, label: species.label(l10n)),
                          ),
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        _divider(scheme),
                        _LabelledRow(
                          label: l10n.helpNeeded,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final tag in tags)
                                _Tag(icon: tag.icon, label: tag.label(l10n)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
      );
}

TextStyle? _labelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

/// One `Label   value` row.
///
/// The label is the whole point of this widget: urgency and status are two
/// scales that run in opposite directions, and shown as two bare chips side by
/// side they read as agreeing or disagreeing when they are answering different
/// questions — "Low" next to "Waiting for help" is an ordinary case, not a
/// contradiction. Naming the field is what stops the reader having to infer it.
///
/// It also pays for itself in width: once the row says "Urgency", the value no
/// longer has to, which is what let the urgency labels drop from
/// "Red — immediate critical help" to "Critical".
class _LabelledRow extends StatelessWidget {
  const _LabelledRow({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;

  /// Sits at the far end of the label's line, not the value's, so it clears a
  /// value that wraps.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: Text(label, style: _labelStyle(context)),
          ),
        ),
        Expanded(child: child),
        if (trailing case final trailing?) trailing,
      ],
    );
  }
}

/// Status as three steps, with the signal's own step marked.
///
/// A badge and a track cannot be mistaken for each other, which is the point:
/// urgency keeps the filled coloured pill [LevelChip] gives it, and progress
/// gets a form that can only mean "how far along". Showing all three steps also
/// means the vocabulary explains itself, instead of being something to look up
/// in the FAQ.
///
/// Three weights, not two. Filling every reached step in one ink drew a solid
/// black rule across a resolved signal and left "which one are we on" resting
/// entirely on the bold label. So a done step is a quiet grey, the step the
/// signal is actually on is the brand ink and a little taller, and steps still
/// ahead are the faintest line on the card. Reading left to right you can see
/// where it got to without reading a word.
///
/// The brand ink is the app's "orange as content" token — the same colour the
/// text buttons and the selected filter chip use — so it reads as *here*,
/// which is what it means everywhere else in the app, rather than as a
/// severity. Severity stays the rail's job.
class _StatusTrack extends StatelessWidget {
  const _StatusTrack({required this.status});

  final SignalStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final steps = SignalStatus.values;
    final currentIndex = steps.indexOf(status);

    return Semantics(
      label: '${l10n.status}: ${status.label(l10n)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, step) in steps.indexed)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 4,
                  right: index == steps.length - 1 ? 0 : 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The current step's bar is taller as well as darker, so
                    // the step reads at a glance and not only in colour — the
                    // one cue that survives a colour-blind reader and a
                    // greyscale screenshot alike.
                    Container(
                      height: index == currentIndex ? 6 : 4,
                      margin: EdgeInsets.only(
                        top: index == currentIndex ? 0 : 1,
                        bottom: index == currentIndex ? 0 : 1,
                      ),
                      decoration: BoxDecoration(
                        color: switch (index.compareTo(currentIndex)) {
                          < 0 => scheme.outline,
                          0 => scheme.secondary,
                          _ => scheme.outlineVariant,
                        },
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      step.label(l10n),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: index == currentIndex
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontWeight: index == currentIndex
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A help-needed or species tag.
///
/// Lighter than a Material [Chip]: these are labels on a card that already has
/// a border, and chip-on-card was two nested containers of nearly the same
/// tone.
class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
