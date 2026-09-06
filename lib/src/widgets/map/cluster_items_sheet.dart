import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../../models/signal_urgency.dart';
import '../../repositories/signal_repository.dart';
import '../urgency_picker.dart';

/// Lists what is inside a cluster bubble the map cannot split any further.
///
/// Tapping a cluster zooms to its bounds, and for most clusters that is the
/// whole answer: the members spread out and become their own pins. It stops
/// being an answer when the members are closer together than max zoom can
/// resolve — about 5 m at Sofia's latitude — or sit on byte-identical
/// coordinates, which two people reporting the same stray from the same spot
/// do routinely. Then the camera arrives at max zoom, the bubble is still a
/// bubble, and every further tap is a no-op. Before this sheet existed, the
/// signals inside were unreachable from the map.
///
/// Generic over the row so the vet clinic layer can use the same sheet with
/// its own rows.
Future<void> showClusterItemsSheet({
  required BuildContext context,
  required String title,
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // A long list has to scroll inside the sheet rather than overflow it, and
    // `isScrollControlled` is what lets the sheet grow past half the screen for
    // a cluster of a dozen. `useSafeArea` keeps the title out from under the
    // status bar when it does — ModalBottomSheetRoute drops the top padding in
    // that mode.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ClusterItemsSheet(
      title: title,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    ),
  );
}

class _ClusterItemsSheet extends StatelessWidget {
  const _ClusterItemsSheet({
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Semantics(
        identifier: 'clusterItemsSheet',
        child: ConstrainedBox(
          // Never taller than most of the screen, so the map stays visible
          // behind it and the sheet still reads as a sheet.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One signal inside a cluster: the My Signals row's avatar treatment (tint
/// says how bad, icon says what is needed) beside the title, so a signal looks
/// like itself here, in the list and in its bubble.
class SignalClusterRow extends StatelessWidget {
  const SignalClusterRow({super.key, required this.signal, required this.onTap});

  final SignalWithId signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final urgency = SignalUrgency.fromCode(signal.urgency);
    final title = signal.signal.title.isNotEmpty
        ? signal.signal.title
        : signal.signal.primaryTag.neededLabel(l10n);
    return Semantics(
      identifier: 'clusterSignalRow',
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: urgency.color.withAlpha(51),
          child: Icon(signal.signal.primaryTag.icon, color: urgency.color),
        ),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: UrgencyChip(urgency: signal.urgency),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
