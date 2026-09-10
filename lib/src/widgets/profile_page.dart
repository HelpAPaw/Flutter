import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/services/auth_service.dart';
import 'package:help_a_paw/src/services/public_profile_service.dart';
import 'package:help_a_paw/src/services/user_stats_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import '../config/routes.dart';
import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'escape_leading.dart';
import '../utils/error_text.dart';
import 'page_width.dart';
import 'stat_card.dart';
import 'user_avatar.dart';
import '../utils/profile_validators.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();

  /// What the fields held when the screen last loaded or saved — the baseline
  /// the X button compares against before offering to discard.
  String _savedName = '';
  String _savedPhone = '';

  bool _isLoading = false;
  UserStats? _stats;

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

  /// Load the same three numbers the public profile shows, through the same
  /// service.
  ///
  /// Shared rather than reimplemented here: two copies of "signals reported" is
  /// how your own profile and everyone else's view of it end up disagreeing
  /// about what the figure counts. What each number means, and where each one
  /// is under- or over-counted, is documented on [UserStatsService].
  Future<void> _loadStatistics() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final stats = await UserStatsService.forUser(user.uid);
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (e, stack) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reportAndDescribe(l10n, e, stack: stack,
                where: 'profile.loadStatistics', fallback: l10n.errorLoadingStatistics)),
          ),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // The same rules the fields display, so Save cannot write something the
    // form is already showing an error for. `PublicProfileService.setName`
    // no-ops on a blank name, so saving one would report success while
    // everyone else kept seeing the *old* name on this user's signals.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final displayName = _displayNameController.text.trim();

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
    } catch (e, stack) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reportAndDescribe(l10n, e, stack: stack,
                where: 'profile.save', fallback: l10n.errorUpdatingProfile)),
          ),
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

      // Through the mirror, not around it. Auth's `photoURL` is readable only
      // by its owner, so the public copy has to be written — but writing it
      // here directly meant this screen owning half of `mirrorProviderPhoto`'s
      // contract (its timeout, its permission-denied handling, its
      // write-avoidance cache) and getting a different answer than every other
      // caller. `updatePhotoURL` has already refreshed `currentUser`, so the
      // mirror sees the new URL.
      await AuthService.mirrorProviderPhoto(user);

      await user.reload();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.photoUpdatedSuccessfully)),
        );
      }
    } catch (e, stack) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reportAndDescribe(l10n, e, stack: stack,
                where: 'profile.uploadAvatar', fallback: l10n.errorUploadingPhoto)),
          ),
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
              tooltip: l10n.editProfile,
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            IconButton(
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close),
              onPressed: _cancelEditing,
            ),
        ],
      ),
      body: PageWidth(child: user == null
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
              child: Form(
                key: _formKey,
                child: Column(
                children: [
                  const SizedBox(height: 20),
                  Stack(
                    children: [
                      UserAvatar(url: user.photoURL, radius: 60),
                      if (_isEditing)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: IconButton(
                              tooltip: l10n.changeProfilePhoto,
                              icon: const Icon(Icons.camera_alt, color: Colors.white),  // theme-independent: over the avatar photo
                              onPressed: _isLoading ? null : _pickAndUploadPhoto,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isEditing) ...[
                    TextFormField(
                      controller: _displayNameController,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) => validateDisplayName(l10n, value),
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
                    TextFormField(
                      controller: _phoneController,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) => validatePhone(l10n, value),
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user.email ?? '',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    // Absent until the aggregations land, rather than three
                    // zeros that then jump: a zero is a real answer here, so
                    // showing one we do not have yet is a lie about this
                    // person's contribution.
                    if (_stats case final stats?)
                      UserStatsRow(stats: stats),
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
            )),
    );
  }
}
