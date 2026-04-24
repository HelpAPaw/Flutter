import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../utils/nav_extensions.dart';

class MySignalsPage extends StatelessWidget {
  const MySignalsPage({super.key});

  Color _getStatusColor(int status) {
    switch (status) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(int status, AppLocalizations l10n) {
    switch (status) {
      case 0:
        return l10n.statusNeedsHelp;
      case 1:
        return l10n.statusInProgress;
      case 2:
        return l10n.statusResolved;
      default:
        return l10n.statusUnknown;
    }
  }

  IconData _getSignalTypeIcon(int type) {
    switch (type) {
      case 0:
        return Icons.emergency;
      case 1:
        return Icons.search;
      case 2:
        return Icons.bloodtype;
      case 3:
        return Icons.home_outlined;
      case 4:
        return Icons.pets;
      case 5:
        return Icons.forest;
      default:
        return Icons.help_outline;
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
        title: Text(l10n.mySignals),
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pin_drop, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l10n.pleaseSignInToViewSignals),
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
                  .collection(AppPreferencesService().signalsCollectionName)
                  .where('reporter',
                      isEqualTo: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid))
                  .orderBy('createdAt', descending: true)
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
                          Icons.pin_drop_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.noSignalsYet,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.submittedSignalsAppearHere,
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
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final signal = Signal.fromJson(data);
                    final createdAt = signal.createdAt as Timestamp?;
                    final dateStr = createdAt != null
                        ? DateFormat('MMM d, yyyy', Localizations.localeOf(context).languageCode).format(createdAt.toDate())
                        : l10n.unknownDate;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(signal.status).withAlpha(51),
                          child: Icon(
                            _getSignalTypeIcon(signal.signalType),
                            color: _getStatusColor(signal.status),
                          ),
                        ),
                        title: Text(
                          signal.title.isNotEmpty ? signal.title : Signal.getLocalizedSignalTypeName(context, signal.signalType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              signal.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(signal.status).withAlpha(51),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _getStatusText(signal.status, l10n),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _getStatusColor(signal.status),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.signalDetails(doc.id)),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
