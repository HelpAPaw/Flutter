import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../../models/signal_urgency.dart';
import '../../models/vet_clinic.dart';
import '../../repositories/signal_repository.dart';
import '../../utils/map_marker_builder.dart';
import '../urgency_picker.dart';
import '../urgency_tag_avatar.dart';

/// Lists what is inside a cluster bubble the map cannot split any further.
///
/// Tapping a cluster zooms to its bounds, and for most clusters that is the
/// whole answer: the members spread out and become their own pins. It stops
/// being an answer when the members are closer together than max zoom can
/// resolve — about 3 m at Sofia's latitude — or sit on byte-identical
/// coordinates, which two people reporting the same stray from the same spot
/// do routinely. Then the camera arrives at max zoom, the bubble is still a
/// bubble, and every further tap is a no-op. Before this sheet existed, the
/// signals inside were unreachable from the map.
///
/// Generic over the member so the signal layer and the vet clinic layer share
/// it, each supplying its own [row].
Future<void> showClusterItemsSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required Widget Function(BuildContext sheetContext, T item) row,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    // A long list has to scroll inside the sheet rather than overflow it, and
    // `isScrollControlled` is what lets the sheet grow past half the screen for
    // a cluster of a dozen. `useSafeArea` keeps the title out from under the
    // status bar when it does — ModalBottomSheetRoute drops the top padding in
    // that mode.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Semantics(
        identifier: 'clusterItemsSheet',
        child: ConstrainedBox(
          // Never taller than most of the screen, so the map stays visible
          // behind it and the sheet still reads as a sheet.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
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
                  itemCount: items.length,
                  itemBuilder: (_, index) => row(sheetContext, items[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
    return _ClusterRow(
      identifier: 'clusterSignalRow',
      leading: ClipOval(
        child: UrgencyTagAvatar(
          urgency: SignalUrgency.fromCode(signal.urgency),
          tag: signal.signal.primaryTag,
          size: 40,
        ),
      ),
      title: signal.signal.displayTitle(l10n),
      subtitle: UrgencyChip(urgency: signal.urgency),
      onTap: onTap,
    );
  }
}

/// One vet clinic inside a cluster: name and address, with the clinic pin's
/// blue so the row matches the bubble it came out of.
class ClinicClusterRow extends StatelessWidget {
  const ClinicClusterRow({super.key, required this.clinic, required this.onTap});

  final VetClinic clinic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ClusterRow(
      identifier: 'clusterClinicRow',
      leading: CircleAvatar(
        // The same tint UrgencyTagAvatar gives a signal, in the clinic's blue.
        backgroundColor: MapMarkerBuilder.clinicBlue.withAlpha(51),
        child: const Icon(
          Icons.local_hospital,
          color: MapMarkerBuilder.clinicBlue,
        ),
      ),
      title: clinic.name,
      subtitle: clinic.address.isEmpty
          ? null
          : Text(clinic.address, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

/// The shape both rows share, so the leading tint, the title clamp and the
/// semantics cannot drift apart between the two layers.
class _ClusterRow extends StatelessWidget {
  const _ClusterRow({
    required this.identifier,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String identifier;
  final Widget leading;
  final String title;
  final Widget? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: identifier,
      child: ListTile(
        leading: leading,
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: subtitle,
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}
