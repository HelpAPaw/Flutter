import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:help_a_paw/src/services/auth_service.dart';
import 'package:help_a_paw/src/services/public_profile_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import '../config/routes.dart';
import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'escape_leading.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;

  /// What the fields held when the screen last loaded or saved — the baseline
  /// the X button compares against before offering to discard.
  String _savedName = '';
  String _savedPhone = '';

  bool _isLoading = false;
  int _signalsCount = 0;
  int _commentsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStatistics();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccountConfirmTitle),
        content: Text(l10n.deleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await AuthService().deleteAccount();
      await AuthService().signOutToAnonymous();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deleteAccountSuccess)),
        );
        context.go(Routes.home);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.deleteAccountError),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _displayNameController.text = user.displayName ?? '';
      _savedName = _displayNameController.text;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        setState(() {
          _phoneController.text = doc.data()?['phone'] ?? '';
          _savedPhone = _phoneController.text;
        });
      }
    }
  }

  Future<void> _loadStatistics() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // Two independent reads, so they overlap rather than queue. They used to
      // be sequential awaits, which made the stats block wait out two round
      // trips to show one row of numbers.
      final results = await Future.wait([
        _loadSignalsPosted(user.uid, userRef),
        FirebaseFirestore.instance
            .collectionGroup('comments')
            .where('author', isEqualTo: userRef)
            .count()
            .get()
            .then((snapshot) => snapshot.count ?? 0),
      ]);

      setState(() {
        _signalsCount = results[0];
        _commentsCount = results[1];
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorLoadingStatistics(e.toString()))),
        );
      }
    }
  }

  /// How many signals this account has reported (master spec §3.5.1).
  ///
  /// **A stored counter, not a query.** This used to be a live `count()` over
  /// `signals` filtered by reporter, which quietly measured something else:
  /// signals still *visible*. Every way a signal can leave that collection took
  /// the credit with it — the reporter removing it (#68), a moderator hiding
  /// it, and the ~6-month archive of §4.10 when it lands. §3.5.1 requires the
  /// opposite: "these stats remain even when old cases are deleted or
  /// archived". `handleSignalCreated` increments the counter once, at the
  /// moment of reporting, and nothing decrements it.
  ///
  /// It lives on `publicProfiles/{uid}` because the rules there already limit
  /// the client to the `name` field alone, so a server-written counter beside
  /// it cannot be forged. `userCounters` was the obvious alternative and is
  /// exactly wrong: that document *is* client-writable by design.
  ///
  /// **The fallback is the migration.** An account with no `signalsPosted`
  /// predates the counter, so it falls back to the old live count rather than
  /// showing a proud zero to someone who has reported for years. Drop the
  /// fallback once the backfill has run everywhere — and note it under-reports
  /// for exactly the accounts this change is meant to help, since a signal they
  /// already removed is no longer there to count.
  Future<int> _loadSignalsPosted(
    String uid,
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    final profile = await FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(uid)
        .get();
    final stored = profile.data()?['signalsPosted'];
    if (stored is int) return stored;

    final legacy = await FirebaseFirestore.instance
        .collection(AppPreferencesService().signalsCollectionName)
        .where('reporter', isEqualTo: userRef)
        .count()
        .get();
    return legacy.count ?? 0;
  }

  Future<void> _updateProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final displayName = _displayNameController.text.trim();
    // PublicProfileService.setName no-ops on a blank name, so saving one would
    // report success while everyone else kept seeing the *old* name on this
    // user's signals and comments. Profile completion already requires a name
    // (it validates with this same message); the editor has to agree.
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).nameIsRequired)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await user.updateDisplayName(displayName);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'displayName': displayName,
            'phone': _phoneController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Mirror the new name to the world-readable public profile.
      await PublicProfileService.setName(user.uid, displayName);
      _savedName = displayName;
      _savedPhone = _phoneController.text.trim();

      await user.reload();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileUpdatedSuccessfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorUpdatingProfile(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isLoading = true);

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('${user.uid}.jpg');

      await ref.putFile(
        File(pickedFile.path),
        // The rules require an `image/*` content type; the picker re-encodes
        // to JPEG (it is given an imageQuality).
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final photoUrl = await ref.getDownloadURL();

      await user.updatePhotoURL(photoUrl);
      await user.reload();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.photoUpdatedSuccessfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorUploadingPhoto(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Leave edit mode, asking first if there is anything to lose.
  ///
  /// This was a bare `setState(_isEditing = false)`: the X sat one tap away
  /// from Save, discarded everything typed, and said nothing. The dialog only
  /// appears when the fields actually differ from what is stored, so tapping X
  /// on an untouched form still just closes.
  Future<void> _cancelEditing() async {
    final l10n = AppLocalizations.of(context);
    final dirty = _displayNameController.text.trim() != _savedName ||
        _phoneController.text.trim() != _savedPhone;

    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.discardChanges),
          content: Text(l10n.discardChangesHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.keepEditing),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.discard),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }

    if (!mounted) return;
    setState(() {
      _displayNameController.text = _savedName;
      _phoneController.text = _savedPhone;
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: escapeLeading(
            context,
            label: AppLocalizations.of(context).back,
            onLeave: () => context.popOrHome(),
          ),
        title: AppBarTitle(l10n.profile),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _cancelEditing,
            ),
        ],
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_circle, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(l10n.pleaseSignInToViewProfile),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.push(Routes.signIn),
                    child: Text(l10n.signIn),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: user.photoURL != null
                            ? CachedNetworkImageProvider(user.photoURL!)
                            : null,
                        child: user.photoURL == null
                            ? const Icon(Icons.person, size: 60)
                            : null,
                      ),
                      if (_isEditing)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt, color: Colors.white),  // theme-independent: over the avatar photo
                              onPressed: _isLoading ? null : _pickAndUploadPhoto,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isEditing) ...[
                    TextField(
                      controller: _displayNameController,
                      decoration: InputDecoration(
                        labelText: l10n.displayName,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person),
                      ),
                      // Mirrors the publicProfiles rules' bounds, so an
                      // over-long or multi-line name is capped as it's typed
                      // instead of failing with an opaque PERMISSION_DENIED.
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                            PublicProfileService.maxNameLength),
                        FilteringTextInputFormatter.singleLineFormatter,
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: l10n.phoneNumber,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _updateProfile,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,  // theme-independent: over the avatar photo
                                ),
                              )
                            : Text(l10n.saveChanges),
                      ),
                    ),
                  ] else ...[
                    Text(
                      user.displayName ?? l10n.noNameSet,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user.email ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatCard(
                          icon: Icons.pin_drop,
                          value: _signalsCount.toString(),
                          label: l10n.signals,
                        ),
                        _StatCard(
                          icon: Icons.comment,
                          value: _commentsCount.toString(),
                          label: l10n.comments,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.email),
                      title: Text(l10n.email),
                      subtitle: Text(user.email ?? l10n.notSet),
                    ),
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(l10n.phoneNumber),
                      subtitle: Text(_phoneController.text.isEmpty ? l10n.notSet : _phoneController.text),
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified),
                      title: Text(l10n.emailVerified),
                      subtitle: Text(user.emailVerified ? l10n.yes : l10n.no),
                      trailing: !user.emailVerified
                          ? TextButton(
                              onPressed: () async {
                                await user.sendEmailVerification();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.verificationEmailSent),
                                    ),
                                  );
                                }
                              },
                              child: Text(l10n.verify),
                            )
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(l10n.memberSince),
                      subtitle: Text(
                        user.metadata.creationTime != null
                            ? '${user.metadata.creationTime!.day}/${user.metadata.creationTime!.month}/${user.metadata.creationTime!.year}'
                            : l10n.unknown,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: _isLoading ? null : _confirmDeleteAccount,
                        icon: const Icon(Icons.delete_forever),
                        label: Text(l10n.deleteAccount),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
