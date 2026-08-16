import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/widgets/level_chip.dart';
import 'package:help_a_paw/src/widgets/urgency_picker.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../utils/nav_extensions.dart';

class MySignalsPage extends StatelessWidget {
  const MySignalsPage({super.key});

  Color _getStatusColor(int status) => SignalStatus.fromCode(status).color;

  Color _getUrgencyColor(int urgency) => SignalUrgency.fromCode(urgency).color;

  String _getStatusText(int status, AppLocalizations l10n) =>
      SignalStatus.fromCode(status).label(l10n);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
      body: StreamBuilder<User?>(
        initialData: FirebaseAuth.instance.currentUser,
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          final user = authSnapshot.data;

          if (user == null) {
            return Center(
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
            );
          }

          return StreamBuilder<QuerySnapshot>(
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
                        // Tinted by urgency, not status: colour means "how bad
                        // is it" everywhere in the app now, and a row whose
                        // avatar and chip disagreed about what red meant would
                        // reintroduce exactly the confusion this replaces.
                        leading: CircleAvatar(
                          backgroundColor: _getUrgencyColor(signal.urgency).withAlpha(51),
                          child: Icon(
                            // The tag already carries an icon, so the row and
                            // the chips on the details screen cannot drift.
                            signal.primaryTag.icon,
                            color: _getUrgencyColor(signal.urgency),
                          ),
                        ),
                        title: Text(
                          signal.title.isNotEmpty
                              ? signal.title
                              : signal.primaryTag.neededLabel(l10n),
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                UrgencyChip(urgency: signal.urgency),
                                LevelChip(
                                  color: _getStatusColor(signal.status),
                                  label: _getStatusText(signal.status, l10n),
                                ),
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
            );
        },
      ),
    );
  }
}
