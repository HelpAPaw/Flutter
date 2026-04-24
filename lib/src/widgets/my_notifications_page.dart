import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../utils/nav_extensions.dart';

class MyNotificationsPage extends StatelessWidget {
  const MyNotificationsPage({super.key});

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'signal_update':
        return Icons.pin_drop;
      case 'comment':
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
      case 'signal_update':
        return Colors.blue;
      case 'comment':
        return Colors.green;
      case 'status_change':
        return Colors.orange;
      case 'nearby_signal':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;

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
              onSelected: (value) async {
                try {
                  if (value == 'mark_all_read') {
                    final batch = FirebaseFirestore.instance.batch();
                    final docs = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('notifications')
                        .where('read', isEqualTo: false)
                        .get();

                    for (var doc in docs.docs) {
                      batch.update(doc.reference, {'read': true});
                    }
                    await batch.commit();
                  } else if (value == 'clear_all') {
                    final docs = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('notifications')
                        .get();

                    final batch = FirebaseFirestore.instance.batch();
                    for (var doc in docs.docs) {
                      batch.delete(doc.reference);
                    }
                    await batch.commit();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.errorGeneric)),
                    );
                  }
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
      body: user == null
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
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
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

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['type'] as String? ?? 'general';
                    final title = data['title'] as String? ?? l10n.notification;
                    final body = data['body'] as String? ?? '';
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
                      onDismissed: (_) {
                        doc.reference.delete().catchError((_) {});
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
                              await doc.reference.update({'read': true});
                            } catch (_) {}
                          }
                          if (signalId != null && context.mounted) {
                            context.push(Routes.signalDetails(signalId));
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
