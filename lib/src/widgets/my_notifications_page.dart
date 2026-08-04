import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../models/signal.dart';
import '../models/signal_status.dart';
import '../services/app_badge_service.dart';
import '../services/notification_inbox_service.dart';
import '../utils/nav_extensions.dart';

/// The in-app notification inbox.
///
/// Rows are rendered from the structured fields on each document
/// (`signalType`, `statusCode`, …) rather than from the stored `title`/`body`,
/// which are the English strings the push carried and exist only as a fallback.
/// The Cloud Function has no i18n, and this app is bilingual.
class MyNotificationsPage extends StatefulWidget {
  const MyNotificationsPage({super.key});

  @override
  State<MyNotificationsPage> createState() => _MyNotificationsPageState();
}

class _MyNotificationsPageState extends State<MyNotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Opening the inbox is the natural moment to repair the drifted unread
    // counter and drop the OS badge to match it.
    _syncBadge();
  }

  Future<void> _syncBadge() async {
    final unread = await NotificationInboxService().syncUnreadCounter();
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
      case 'nearby_signal':
        return Icons.location_on;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'new_signal':
        return Colors.blue;
      case 'new_comment':
        return Colors.green;
      case 'status_change':
        return Colors.orange;
      case 'nearby_signal':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Localized row title, falling back to the stored English text for a type
  /// this build does not know about.
  String _title(AppLocalizations l10n, Map<String, dynamic> data) {
    final signalTitle = data['signalTitle'] as String? ?? '';

    switch (data['type']) {
      case 'new_signal':
        return l10n.notificationNewSignalTitle;
      case 'status_change':
        return l10n.notificationStatusChangeTitle;
      case 'new_comment':
        return l10n.notificationNewCommentTitle(signalTitle);
      case 'nearby_signal':
        return l10n.signalNearbyNotificationTitle;
      default:
        return data['title'] as String? ?? l10n.notification;
    }
  }

  /// Localized row body. Comment text is user content and is shown as stored.
  String _body(AppLocalizations l10n, Map<String, dynamic> data) {
    final signalTitle = data['signalTitle'] as String? ?? '';
    final signalType = data['signalType'] as int?;
    final statusCode = data['statusCode'] as int?;
    final fallback = data['body'] as String? ?? '';

    switch (data['type']) {
      case 'new_signal':
        if (signalType == null) return fallback;
        return l10n.notificationNewSignalBody(
          Signal.signalTypeName(l10n, signalType),
          signalTitle,
        );
      case 'nearby_signal':
        if (signalType == null) return fallback;
        return l10n.notificationNearbySignalBody(
          Signal.signalTypeName(l10n, signalType),
          signalTitle,
        );
      case 'status_change':
        if (statusCode == null) return fallback;
        return l10n.notificationStatusChangeBody(
          signalTitle,
          SignalStatus.fromCode(statusCode).label(l10n),
        );
      case 'new_comment':
        return data['commentExcerpt'] as String? ?? fallback;
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
    final stream = inbox.watchInbox();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrHome(),
        ),
        title: Text(l10n.myNotifications),
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_off, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l10n.pleaseSignInToViewNotifications),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.push(Routes.signIn),
                    child: Text(l10n.signIn),
                  ),
                ],
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(l10n.errorWithMessage(snapshot.error.toString())),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.noNotifications,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.notifiedAboutSignalUpdates,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
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
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        // Surfaced rather than swallowed: a denied delete makes
                        // the row reappear on the next rebuild, which reads as a
                        // glitch unless the failure is stated.
                        try {
                          await doc.reference.delete();
                        } catch (_) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(l10n.errorGeneric)),
                          );
                        }
                      },
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getNotificationColor(type).withAlpha(51),
                          child: Icon(
                            _getNotificationIcon(type),
                            color: _getNotificationColor(type),
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
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        trailing: !read
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
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
