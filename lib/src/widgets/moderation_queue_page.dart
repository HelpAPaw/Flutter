import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../models/report_reason.dart';
import '../services/app_preferences_service.dart';
import '../services/moderation_service.dart';
import '../utils/nav_extensions.dart';
import 'escape_leading.dart';
import 'moderation_action_sheet.dart';

/// The moderator's queue of open reports (master spec §18).
///
/// **Not router-gated.** The role check is an async Firestore read and a
/// GoRouter `redirect` has to answer synchronously — the same constraint that
/// made `HelperTagsGate` a widget rather than a redirect (SPECIFICATION §7.15),
/// and router bootstrap here is known-fragile. Instead this screen watches the
/// role and renders a plain refusal for anyone without it. Nothing is leaked by
/// that: `firestore.rules` denies the underlying query, so a non-moderator who
/// types the URL gets an empty stream regardless of what this widget does.
///
/// Split by test mode, exactly like the notification inbox, so reports filed
/// against `signals_test` while QA-ing do not clutter the real queue.
class ModerationQueuePage extends StatefulWidget {
  const ModerationQueuePage({super.key});

  @override
  State<ModerationQueuePage> createState() => _ModerationQueuePageState();
}

class _ModerationQueuePageState extends State<ModerationQueuePage> {
  /// One capped page, no pagination — the same shape as `MyNotificationsPage`.
  /// A queue that needs a second page of 50 open reports is a signal to build
  /// filtering, not infinite scroll.
  static const int _pageSize = 50;

  // Memoized so a rebuild does not hand StreamBuilder a fresh Stream instance,
  // which would cancel, re-listen, flash the spinner and re-read the page.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _reportsStream;
  Stream<bool>? _roleStream;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _reports =>
      _reportsStream ??= FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'open')
          .where('testMode', isEqualTo: AppPreferencesService().isTestMode())
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moderationQueue),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        // A deep link can cold-launch onto any route, leaving no back
        // affordance at all (R6-003).
        leading: escapeLeading(
          context,
          label: l10n.back,
          onLeave: () => context.popOrHome(),
        ),
      ),
      body: StreamBuilder<bool>(
        // Live rather than a one-shot read: a revoked moderator should lose the
        // screen without restarting the app. This is the property a custom auth
        // claim could not give us — a claim lives in the ID token until it
        // expires.
        stream: _roleStream ??= ModerationService.instance.watchIsModerator(),
        builder: (context, roleSnapshot) {
          if (!roleSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (roleSnapshot.data != true) {
            return _message(
              icon: Icons.lock_outline,
              text: l10n.moderationNotAModerator,
            );
          }
          return _buildQueue(l10n);
        },
      ),
    );
  }

  Widget _buildQueue(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message(
            icon: Icons.error_outline,
            text: l10n.errorGeneric,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _message(
            icon: Icons.inbox_outlined,
            text: l10n.moderationQueueEmpty,
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _reportTile(l10n, docs[index]),
        );
      },
    );
  }

  Widget _reportTile(
    AppLocalizations l10n,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final reasonCode = data['reason'] as String? ?? '';
    final reason = ReportReason.fromCode(reasonCode);
    final details = (data['details'] as String? ?? '').trim();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final targetType = data['targetType'] as String? ?? '';
    final signalId = data['signalId'] as String?;

    return ListTile(
      isThreeLine: details.isNotEmpty,
      leading: Icon(reason?.icon ?? Icons.flag_outlined),
      // A reason this build does not know still has to be legible, so the raw
      // code is shown rather than folded into "Other" — see ReportReason.fromCode.
      title: Text(reason?.label(l10n) ?? reasonCode),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              targetType,
              if (createdAt != null) DateFormat.yMMMd().add_Hm().format(createdAt),
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          if (details.isNotEmpty)
            Text(
              details,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Semantics(
        label: l10n.moderationOpenTarget,
        button: true,
        child: IconButton(
          icon: const Icon(Icons.open_in_new),
          // A user report has no signal to open; the actions sheet still does.
          onPressed: signalId == null
              ? null
              : () => context.push(Routes.signalDetails(signalId)),
        ),
      ),
      onTap: () => showModerationActionSheet(
        context,
        reportId: doc.id,
        report: data,
      ),
    );
  }

  Widget _message({required IconData icon, required String text}) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(text, textAlign: TextAlign.center),
            ),
          ],
        ),
      );
}
