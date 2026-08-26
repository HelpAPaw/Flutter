import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/animal_type.dart';
import '../../models/help_tag.dart';
import '../../models/signal_status.dart';
import '../../models/signal_urgency.dart';
import '../../state/map_state.dart';
import '../../viewmodels/map_view_model.dart';
import '../section_header.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

/// Shows the filter bottom sheet for help tags, species, urgency and status
void showFilterBottomSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);

  // Every toggle applies to the map immediately, which is the good part — you
  // watch pins appear and disappear as you tick. It also meant there was no
  // way back: "Apply Filters" only called Navigator.pop, and dismissing with
  // the back gesture left the edits applied just the same. Unticking Red and
  // changing your mind was unrecoverable except by re-ticking from memory.
  //
  // So the sheet remembers what it opened with and Cancel puts it back.
  final opened = ref.read(mapViewModelProvider).filterState;

  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return _FilterBottomSheetContent(l10n: l10n);
    },
  ).then((keep) {
    // null = dismissed by the back gesture or by tapping the scrim, which is
    // a cancel like any other.
    if (keep != true) {
      ref.read(mapViewModelProvider.notifier).restoreFilterState(opened);
    }
  });
}

class _FilterBottomSheetContent extends ConsumerWidget {
  final AppLocalizations l10n;

  const _FilterBottomSheetContent({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(
      mapViewModelProvider.select((state) => state.filterState),
    );
    final viewModel = ref.read(mapViewModelProvider.notifier);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A Row here pushed "Clear All" off-screen entirely in
                    // Bulgarian at 411dp — the title, "Избери всички" and
                    // "Изчисти всички" do not fit on one line, and a Row
                    // silently overflows rather than reflowing. Unreachable,
                    // with no way to undo a filter. Wrap moves the buttons to
                    // their own line instead.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          l10n.filterSignals,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => viewModel.selectAllFilters(),
                              child: Text(l10n.selectAll),
                            ),
                            TextButton(
                              onPressed: () => viewModel.clearAllFilters(),
                              child: Text(l10n.clearAll),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    SectionHeader(l10n.timeRange),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildTimeRangeChip(
                        context: context,
                          label: l10n.last24Hours,
                          value: TimeRange.last24Hours,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                        _buildTimeRangeChip(
                        context: context,
                          label: l10n.last7Days,
                          value: TimeRange.last7Days,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                        _buildTimeRangeChip(
                        context: context,
                          label: l10n.last30Days,
                          value: TimeRange.last30Days,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                        _buildTimeRangeChip(
                        context: context,
                          label: l10n.allTime,
                          value: TimeRange.allTime,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                      ],
                    ),
                    ..._section(
                      l10n.urgency,
                      SignalUrgency.values.map(
                        (urgency) => _buildCheckbox(
                          label: urgency.label(l10n),
                          leading: Image.asset(
                            urgency.pinAsset,
                            width: 24,
                            height: 24,
                          ),
                          isSelected: filterState.selectedUrgencies
                              .contains(urgency.code),
                          onToggle: () => viewModel.toggleUrgency(urgency.code),
                        ),
                      ),
                    ),
                    // Status rows deliberately carry no icon: the map pin means
                    // urgency now, so showing one here would re-imply the old
                    // status/colour link this change exists to break.
                    ..._section(
                      l10n.status,
                      SignalStatus.values.map(
                        (status) => _buildCheckbox(
                          label: status.label(l10n),
                          isSelected: filterState.selectedStatuses
                              .contains(status.code),
                          onToggle: () => viewModel.toggleStatus(status.code),
                        ),
                      ),
                    ),
                    // A signal declares up to three needs and passes if *any*
                    // of them is ticked — see MapFilterState.signalPassesFilter.
                    ..._section(
                      l10n.helpNeeded,
                      HelpTag.values.map(
                        (tag) => _buildCheckbox(
                          label: tag.label(l10n),
                          leading: Icon(tag.icon, size: 22),
                          isSelected:
                              filterState.selectedHelpTags.contains(tag.code),
                          onToggle: () => viewModel.toggleHelpTag(tag.code),
                        ),
                      ),
                    ),
                    ..._section(
                      l10n.animalTypes,
                      AnimalType.values.map(
                        (type) => _buildCheckbox(
                          label: type.label(l10n),
                          leading: Icon(type.icon, size: 22),
                          isSelected: filterState.selectedAnimalTypes
                              .contains(type.code),
                          onToggle: () =>
                              viewModel.toggleAnimalType(type.code),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(l10n.done),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One filter row. [leading] is the only thing that varied between the three
  /// copies this replaced — a pin asset for urgency, a Material icon for tags
  /// and species, nothing for status — and they had already drifted apart on
  /// label wrapping and icon size.
  Widget _buildCheckbox({
    required String label,
    required bool isSelected,
    required VoidCallback onToggle,
    Widget? leading,
  }) {
    return CheckboxListTile(
      value: isSelected,
      onChanged: (_) => onToggle(),
      title: leading == null
          ? Text(label)
          : Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Flexible(child: Text(label)),
              ],
            ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  /// A divider, a heading and its rows — the four-line preamble each filter
  /// section repeated verbatim.
  ///
  /// The heading is the shared [SectionHeader] rather than a local `Text`: this
  /// sheet used a hardcoded `fontSize: 16`, which would have been a third size
  /// for one heading style and, unlike `titleMedium`, does not scale with the
  /// user's text-size setting.
  List<Widget> _section(String title, Iterable<Widget> rows) => [
        const SizedBox(height: 16),
        const Divider(),
        SectionHeader(title),
        const SizedBox(height: 8),
        ...rows,
      ];

  Widget _buildTimeRangeChip({
    required BuildContext context,
    required String label,
    required TimeRange value,
    required TimeRange selected,
    required void Function(TimeRange) onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onSelected(value),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }
}
