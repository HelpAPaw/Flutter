import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../services/auth_service.dart';
import '../services/public_profile_service.dart';

class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({super.key});

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _prefillFromAuth();
  }

  void _prefillFromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Pre-fill the name field so it's never blank: prefer the Google/Auth
    // display name, otherwise fall back to the local part of the email.
    final suggested = _suggestedName(user);
    if (suggested != null) {
      _nameController.text = suggested;
    }
  }

  /// Best-available display name for [user]: the Auth display name (Google
  /// OAuth / existing), else the name on a linked provider record, else the
  /// local part of the email (e.g. "john.doe" from "john.doe@example.com").
  /// Returns null if none is available.
  String? _suggestedName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    // The sign-in path copies Google's name onto the Auth record, so this only
    // catches accounts that predate that or whose copy didn't land (R5-001).
    // Worth keeping: whatever ends up here is published to publicProfiles as
    // the name every other user sees, so an email local part is a poor last
    // resort.
    final fromProvider = AuthService.providerDisplayName(user);
    if (fromProvider != null) return fromProvider;

    final email = user.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Pops back through the auth stack to return to the original screen.
  /// The stack may be: original → sign_in → [verify_email] → complete_profile.
  /// If nothing non-auth is underneath (router redirects replace the stack),
  /// fall back to /home so the user doesn't get stranded on an auth screen.
  void _popAuthStack(BuildContext context) {
    void popNext() {
      if (!context.mounted) return;

      final currentPath = GoRouterState.of(context).matchedLocation;
      if (!Routes.authRoutes.contains(currentPath)) return;

      if (context.canPop()) {
        context.pop();
        WidgetsBinding.instance.addPostFrameCallback((_) => popNext());
      } else {
        context.go(Routes.home);
      }
    }

    popNext();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update Firebase Auth display name if different
      if (user.displayName != _nameController.text.trim()) {
        await user.updateDisplayName(_nameController.text.trim());
      }

      // Save profile data to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': user.email,
        'profileCompleted': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Mirror the display name to the world-readable public profile so it
      // resolves for every viewer (see PublicProfileService).
      await PublicProfileService.setName(user.uid, _nameController.text.trim());

      if (mounted) {
        // Pop back through auth screens to return to original screen
        _popAuthStack(context);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorSavingProfile(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Header
                  Center(
                    child: Column(
                      children: [
                        Image.asset('assets/logo.png', height: 60),
                        const SizedBox(height: 16),
                        Text(
                          l10n.completeYourProfile,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.helpUsPersonalize,
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Name field (mandatory)
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.fullNameRequired,
                      hintText: l10n.enterFullName,
                      prefixIcon: const Icon(Icons.person, color: Colors.orange),
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange, width: 2),
                      ),
                      labelStyle: const TextStyle(color: Colors.orange),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.nameIsRequired;
                      }
                      if (value.trim().length < 2) {
                        return l10n.nameTooShort;
                      }
                      return null;
                    },
                    textCapitalization: TextCapitalization.words,
                    // Mirrors the publicProfiles rules' bounds, so an over-long
                    // or multi-line name is capped as it's typed instead of
                    // failing the write with an opaque PERMISSION_DENIED.
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                          PublicProfileService.maxNameLength),
                      FilteringTextInputFormatter.singleLineFormatter,
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Phone field (optional)
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: l10n.phoneNumberOptional,
                      hintText: l10n.enterPhoneNumber,
                      prefixIcon: const Icon(Icons.phone, color: Colors.orange),
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange, width: 2),
                      ),
                      labelStyle: const TextStyle(color: Colors.orange),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        // Basic phone validation if provided
                        if (value.length < 8) {
                          return l10n.validPhoneNumber;
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Complete Profile button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            l10n.completeProfile,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Skip link (for optional completion)
                  TextButton(
                    onPressed: _isLoading ? null : () {
                      final user = FirebaseAuth.instance.currentUser;
                      // Still save minimal profile data even if skipped
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(user?.uid)
                          .set({
                        'profileCompleted': true,
                        'createdAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true)).catchError((_) {});
                      // Mirror a name to the world-readable public profile so the
                      // user resolves for every viewer instead of showing as
                      // "Unknown". Use whatever is in the field (it's editable),
                      // falling back to the Auth/email-derived suggestion.
                      if (user != null) {
                        final typed = _nameController.text.trim();
                        final name =
                            typed.isNotEmpty ? typed : _suggestedName(user);
                        if (name != null && name.isNotEmpty) {
                          PublicProfileService.setName(user.uid, name)
                              .catchError((_) {});
                        }
                      }
                      // Pop back through auth screens to return to original screen
                      _popAuthStack(context);
                    },
                    child: Text(
                      l10n.skipForNowProfile,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}