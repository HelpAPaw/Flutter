import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

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
    if (user != null) {
      // Pre-fill name from Google OAuth or existing display name
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _nameController.text = user.displayName!;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Pops back through the auth stack to return to the original screen.
  /// The stack may be: original → sign_in → [verify_email] → complete_profile
  void _popAuthStack(BuildContext context) {
    // Auth routes that should be popped
    const authRoutes = {'/complete_profile', '/verify_email', '/sign_in'};

    void popNext() {
      if (!context.mounted) return;

      final currentPath = GoRouterState.of(context).matchedLocation;

      // If we're still on an auth route and can pop, continue popping
      if (authRoutes.contains(currentPath) && context.canPop()) {
        context.pop();
        // Schedule next check after this pop completes
        WidgetsBinding.instance.addPostFrameCallback((_) => popNext());
      }
      // Otherwise we've reached the original screen - stop popping
    }

    if (context.canPop()) {
      popNext();
    } else {
      // Fallback if somehow we can't pop
      context.go('/home');
    }
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
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
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
                      // Still save minimal profile data even if skipped
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .set({
                        'profileCompleted': true,
                        'createdAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true)).catchError((_) {});
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