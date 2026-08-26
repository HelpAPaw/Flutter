import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../models/help_tag.dart';
import '../models/signal_status.dart';
import '../models/signal_urgency.dart';
import '../services/app_badge_service.dart';
import '../services/notification_inbox_service.dart';
import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'status_view.dart';
import 'escape_leading.dart';

/// The in-app notification inbox.
///
/// Rows are rendered from the structured fields on each document
/// (`helpNeededTags`, `statusCode`, …) rather than from the stored `title`/`body`,
/// which are the English strings the push carried and exist only as a fallback.
/// The Cloud Function has no i18n, and this app is bilingual.
class MyNotificationsPage extends StatefulWidget {
  const MyNotificationsPage({super.key});

  @override
  State<MyNotificationsPage> createState() => _MyNotificationsPageState();
}

class _MyNotificationsPageState extends State<MyNotificationsPage> {
  /// Bumped by Retry, and used as the inbox StreamBuilder's key so a failed
  /// listen is torn down and restarted rather than rebuilt as-is.
  int _attempt = 0;

  // Memoized so a rebuild doesn't hand StreamBuilder a fresh Stream instance,
  // which would cancel and re-listen — flashing the spinner and re-reading up
  // to `pageSize` documents each time. Same `??=` shape as
  // SignalDetailsScreen's document stream.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _inboxStream;

  @override
  void initState() {
    super.initState();
    // Opening the inbox is the natural moment to repair the drifted unread
    // counter and drop the OS badge to match it.
    _syncBadge();
  }

  Future<void> _syncBadge() async {
    final unread = await NotificationInboxService().syncUnreadCounter();
    // Unknown count — leave the badge as it is rather than clearing it.
    if (unread == null) return;
    await AppBadgeService().setBadge(unread);
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'new_signal':
        return Icons.pin_drop;
      case 'new_comment':
        return Icons.comment;
      case 'status_change':
        return Icons.info;
      case 'urgency_change':
        return Icons.priority_high;
      case 'nearby_signal':
        return Icons.location_on;
      // Case ownership (master spec 4.5). An offer and its answer share the
      // "someone is asking you something" hand; a transfer gets the same icon
      // the details screen puts on the Take responsibility button.
      case 'ownership_change':
        return Icons.volunteer_activism;
      case 'takeover_request':
      case 'takeover_approved':
      case 'takeover_declined':
        return Icons.pan_tool_alt_outlined;
      default:
        return Icons.notifications;
    }
  }

  /// Whether an entry announces a Red Alert.
  ///
  /// Entries written before the urgency system carry no `urgency`, so a missing
  /// value is deliberately *not* a Red Alert.
  bool _isRedAlert(Map<String, dynamic> data) =>
      (data['urgency'] as int?) == SignalUrgency.red.code;

  /// Row accent colour.
  ///
  /// The inbox used to run six accents — blue, green, orange, grey and two
  /// different reds. `nearby_signal` was `Colors.red` and a Red Alert was
  /// `SignalUrgency.red.color`, so the one colour in the app that is supposed
  /// to mean "this animal may die" also meant "a signal exists near you".
  ///
  /// Same rule as everywhere else now: colour means urgency, and rows that do
  /// not announce an urgency do not get one. The icon already says what kind
  /// of row it is — see [_getNotificationIcon] — so nothing is lost by making
  /// the rest neutral, and the red rows now stand out because they are the
  /// only coloured thing in the list.
  Color _getNotificationColor(String type, Map<String, dynamic> data) {
    final neutral = Theme.of(context).colorScheme.onSurfaceVariant;

    switch (type) {
      // Announces a signal: coloured only when that signal is a Red Alert.
      case 'new_signal':
      case 'nearby_signal':
        return _isRedAlert(data) ? SignalUrgency.red.color : neutral;

      // Announces an urgency change, so it is the urgency by definition.
      //
      // No null special-case: fromCode already resolves an unknown/missing
      // level to amber, and inventing a red default here would contradict
      // the fallback the rest of the feature relies on.
      case 'urgency_change':
        return SignalUrgency.fromCode(data['urgency'] as int? ?? -1).color;

      // Comments, status changes and everything about case ownership are
      // progress, not severity.
      default:
        return neutral;
    }
  }

  /// Localized row title, falling back to the stored English text for a type
  /// this build does not know about.
  String _title(AppLocalizations l10n, Map<String, dynamic> data) {
    final signalTitle = data['signalTitle'] as String? ?? '';

    switch (data['type']) {
      case 'new_signal':
        // The push for a nearby Red Alert is prefixed; the inbox row has to
        // say so too, or a user who missed the push cannot tell a critical
        // case from a routine one in the list.
        return _isRedAlert(data)
            ? l10n.notificationNewRedAlertTitle
            : l10n.notificationNewSignalTitle;
      case 'status_change':
        return l10n.notificationStatusChangeTitle;
      case 'urgency_change':
        return _isRedAlert(data)
            ? l10n.notificationRedAlertTitle
            : l10n.notificationUrgencyChangeTitle;
      case 'new_comment':
        return l10n.notificationNewCommentTitle(signalTitle);
      case 'nearby_signal':
        return l10n.signalNearbyNotificationTitle;
      // A transfer and a release are one server type, told apart by whether
      // there is a new holder. `newHolderId` is explicitly null on a release —
      // a real answer, not a missing field — so the two render differently
      // without needing two types on the wire.
      case 'ownership_change':
        return data['newHolderId'] == null
            ? l10n.notificationOwnershipReleasedTitle
            : l10n.notificationOwnershipChangeTitle;
      case 'takeover_request':
        return l10n.notificationTakeoverRequestTitle;
      case 'takeover_approved':
        return l10n.notificationTakeoverApprovedTitle;
      case 'takeover_declined':
        return l10n.notificationTakeoverDeclinedTitle;
      default:
        return data['title'] as String? ?? l10n.notification;
    }
  }

  /// Localized row body. Comment text is user content and is shown as stored.
  String _body(AppLocalizations l10n, Map<String, dynamic> data) {
    final signalTitle = data['signalTitle'] as String? ?? '';
    // Rows written before signal types were folded into the tag vocabulary
    // carry a `signalType` int and no tags. They are not translated back — the
    // stored English body is shown instead, which is what `fallback` is for.
    // Keeping a retired 7-value bilingual type table alive purely to re-render
    // notification history is not worth it.
    final helpNeededTags =
        (data['helpNeededTags'] as List<dynamic>?)?.cast<String>();
    final statusCode = data['statusCode'] as int?;
    final fallback = data['body'] as String? ?? '';

    switch (data['type']) {
      // One format for both: a fan-out push and a catch-up announce the same
      // thing about the same signal. Catch-up rows carry no `urgency`, so they
      // simply always take the plain branch.
      case 'new_signal':
      case 'nearby_signal':
        if (helpNeededTags == null) return fallback;
        final headline = HelpTag.primaryOf(helpNeededTags).neededLabel(l10n);
        // Red repeats the urgency here because the row is often read without
        // its title, and it is the whole point of the level. Mirrors the
        // server's push body.
        return (data['urgency'] as int?) == SignalUrgency.red.code
            ? l10n.notificationNewSignalBodyUrgent(headline, signalTitle)
            : l10n.notificationNewSignalBody(headline, signalTitle);
      case 'status_change':
        if (statusCode == null) return fallback;
        return l10n.notificationStatusChangeBody(
          signalTitle,
          SignalStatus.fromCode(statusCode).label(l10n),
        );
      case 'urgency_change':
        final urgency = data['urgency'] as int?;
        if (urgency == null) return fallback;
        return l10n.notificationUrgencyChangeBody(
          signalTitle,
          SignalUrgency.fromCode(urgency).label(l10n),
        );
      case 'new_comment':
        return data['commentExcerpt'] as String? ?? fallback;
      // `newHolderName` is resolved server-side, once, rather than re-read per
      // reader: a name is not a translatable string, and the alternative is a
      // publicProfiles read for every row in the list on every rebuild.
      case 'ownership_change':
        if (data['newHolderId'] == null) {
          return l10n.notificationOwnershipReleasedBody;
        }
        final holderName = data['newHolderName'] as String?;
        if (holderName == null) return fallback;
        return l10n.notificationOwnershipChangeBody(holderName);
      case 'takeover_request':
        final requesterName = data['newHolderName'] as String?;
        if (requesterName == null) return fallback;
        return l10n.notificationTakeoverRequestBody(requesterName);
      case 'takeover_approved':
        return l10n.notificationTakeoverApprovedBody;
      case 'takeover_declined':
        return l10n.notificationTakeoverDeclinedBody;
      default:
        return fallback;
    }
  }

  Future<void> _runBulkAction(
    AppLocalizations l10n,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      await AppBadgeService().clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorGeneric)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final inbox = NotificationInboxService();
    final stream = _inboxStream ??= inbox.watchInbox();

    return Scaffold(
      appBar: AppBar(
        leading: escapeLeading(
            context,
            label: AppLocalizations.of(context).back,
            onLeave: () => context.popOrHome(),
          ),
        title: AppBarTitle(l10n.myNotifications),
        actions: [
          if (user != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'mark_all_read') {
                  _runBulkAction(l10n, inbox.markAllRead);
                } else if (value == 'clear_all') {
                  _runBulkAction(l10n, inbox.clearAll);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'mark_all_read',
                  child: Row(
                    children: [
                      const Icon(Icons.done_all, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.markAllAsRead),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_sweep, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.clearAllNotifications),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: user == null || stream == null
          ? StatusView.empty(
              icon: Icons.notifications_off,
              title: l10n.pleaseSignInToViewNotifications,
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey(_attempt),
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  // Logged, not shown: a raw Firebase exception is a fact
                  // about our rules, not something a reader can act on.
                  debugPrint('Inbox stream failed: ${snapshot.error}');
                  return StatusView.error(
                    title: l10n.couldNotLoadNotifications,
                    hint: l10n.couldNotLoadSignalsHint,
                    onRetry: () => setState(() => _attempt++),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return StatusView.empty(
                    icon: Icons.notifications_none,
                    title: l10n.noNotifications,
                    hint: l10n.notifiedAboutSignalUpdates,
                  );
                }

                // Captured from the page's own context, not the list item's:
                // both are used after an await, and a dismissed or rebuilt item
                // element is defunct by then.
                final messenger = ScaffoldMessenger.of(this.context);
                final router = GoRouter.of(this.context);

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final type = data['type'] as String? ?? 'general';
                    final title = _title(l10n, data);
                    final body = _body(l10n, data);
                    final read = data['read'] as bool? ?? false;
                    final signalId = data['signalId'] as String?;
                    final createdAt = data['createdAt'] as Timestamp?;
                    final timeStr = createdAt != null
                        ? _formatTime(createdAt.toDate(), l10n)
                        : '';

                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),  // theme-independent: on the red swipe-to-delete background
                      ),
                      onDismissed: (_) async {
                        // A swipe deleted the document outright, with no way
                        // back — while a signal the user removes sits in a
                        // 30-day bin. The gesture is easy to trigger by
                        // accident and the two were wildly out of proportion,
                        // so the row's data is kept in hand and Undo writes it
                        // back at the same id.
                        final restore = Map<String, dynamic>.from(data);

                        // Surfaced rather than swallowed: a denied delete makes
                        // the row reappear on the next rebuild, which reads as a
                        // glitch unless the failure is stated.
                        try {
                          await doc.reference.delete();
                        } catch (_) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(l10n.errorGeneric)),
                          );
                          return;
                        }

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.notificationDeleted),
                            action: SnackBarAction(
                              label: l10n.undo,
                              onPressed: () async {
                                try {
                                  await doc.reference.set(restore);
                                } catch (_) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                        content: Text(l10n.errorGeneric)),
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      },
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _getNotificationColor(type, data).withAlpha(51),
                          child: Icon(
                            _getNotificationIcon(type),
                            color: _getNotificationColor(type, data),
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: read ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        trailing: !read
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                        onTap: () async {
                          if (!read) {
                            try {
                              await inbox.markRead(doc.reference);
                              await _syncBadge();
                            } catch (_) {}
                          }
                          if (signalId != null && mounted) {
                            router.push(Routes.signalDetails(signalId));
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatTime(DateTime time, AppLocalizations l10n) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      return DateFormat('MMM d').format(time);
    }
  }
}
