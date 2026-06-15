import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/signal.dart';
import '../../models/signal_status.dart';
import '../../state/map_state.dart';
import '../../viewmodels/map_view_model.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

/// Shows the filter bottom sheet for signal types and statuses
void showFilterBottomSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
    ),
    builder: (BuildContext context) {
      return _FilterBottomSheetContent(l10n: l10n);
    },
  );
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
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.filterSignals,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
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
                    Text(
                      l10n.timeRange,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildTimeRangeChip(
                          label: l10n.last24Hours,
                          value: TimeRange.last24Hours,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                        _buildTimeRangeChip(
                          label: l10n.last7Days,
                          value: TimeRange.last7Days,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                        _buildTimeRangeChip(
                          label: l10n.last30Days,
                          value: TimeRange.last30Days,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                        _buildTimeRangeChip(
                          label: l10n.allTime,
                          value: TimeRange.allTime,
                          selected: filterState.selectedTimeRange,
                          onSelected: (range) => viewModel.setTimeRange(range),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Text(
                      l10n.status,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...SignalStatus.values.map(
                      (status) => _buildStatusCheckbox(
                        status: status.code,
                        label: status.label(l10n),
                        iconPath: status.pinAsset,
                        isSelected:
                            filterState.selectedStatuses.contains(status.code),
                        onToggle: () => viewModel.toggleStatus(status.code),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Text(
                      l10n.signalType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(Signal.signalTypes.length, (index) {
                      return _buildTypeCheckbox(
                        type: index,
                        label: Signal.getLocalizedSignalTypeName(context, index),
                        isSelected:
                            filterState.selectedSignalTypes.contains(index),
                        onToggle: () => viewModel.toggleSignalType(index),
                      );
                    }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: Text(
                          l10n.applyFilters,
                          style: const TextStyle(fontSize: 16),
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
  }

  Widget _buildStatusCheckbox({
    required int status,
    required String label,
    required String iconPath,
    required bool isSelected,
    required VoidCallback onToggle,
  }) {
    return CheckboxListTile(
      value: isSelected,
      onChanged: (_) => onToggle(),
      title: Row(
        children: [
          Image.asset(iconPath, width: 24, height: 24),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
      activeColor: Colors.orange,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildTypeCheckbox({
    required int type,
    required String label,
    required bool isSelected,
    required VoidCallback onToggle,
  }) {
    return CheckboxListTile(
      value: isSelected,
      onChanged: (_) => onToggle(),
      title: Text(label),
      activeColor: Colors.orange,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildTimeRangeChip({
    required String label,
    required TimeRange value,
    required TimeRange selected,
    required void Function(TimeRange) onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onSelected(value),
      selectedColor: Colors.orange.shade100,
      checkmarkColor: Colors.orange.shade800,
    );
  }
}
