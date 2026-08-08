import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../services/auth_service.dart';
import '../utils/nav_extensions.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage>
    with WidgetsBindingObserver {
  bool _isResending = false;
  bool _isChecking = false;
  Timer? _timer;
  Timer? _countdownTimer;
  int _countdown = 60;

  @override
  void initState() {
    super.initState();
    // The verification email is sent once at account creation (see sign_in_page
    // UserCreated handler), not on every mount - otherwise a returning unverified
    // sign-in would re-send an email each time the router redirects here (R2-005).
    // The resend cooldown still starts at 60s: a returning user already has an
    // earlier email to find, so we don't invite an immediate reflexive resend.
    _startResendCountdown();
    // Verification usually completes after the user leaves the app to click the
    // link in their email, so re-check the instant they return (didChange...
    // resumed). The periodic poll is just a slow fallback.
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkEmailVerified();
    }
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      await _checkEmailVerified();
    });
  }

  Future<void> _checkEmailVerified() async {
    if (_isChecking) return;

    setState(() => _isChecking = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;

        if (refreshedUser?.emailVerified ?? false) {
          // reload() updates the User object's emailVerified flag but NOT the
          // cached ID token that Firestore Security Rules read. Force-refresh
          // the token so its email_verified claim flips to true immediately;
          // otherwise rules gating writes on email_verified deny this
          // freshly-verified user until the token organically refreshes (~1h)
          // or they re-login.
          await refreshedUser!.getIdToken(true);
          _timer?.cancel();
          if (mounted) {
            // go (not push): /verify_email must not remain in the stack, or the
            // return-to-origin logic in profile_completion_page gets stuck on it.
            context.go(Routes.completeProfile);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking verification: $e');
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  /// (Re)starts the 60s resend cooldown. Called on mount and after each send so
  /// the Resend button is rate-limited consistently whether or not an email was
  /// just sent. Uses a plain assignment for the initial value so it is safe to
  /// call from initState; the per-second ticks use setState.
  void _startResendCountdown() {
    _countdownTimer?.cancel();
    _countdown = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        // Send verification email without action code settings
        // This uses Firebase's default email template which should work
        await user.sendEmailVerification();

        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.verificationEmailSentCheck),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Restart the resend cooldown.
        _startResendCountdown();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        String errorMessage;

        if (e.code == 'too-many-requests') {
          errorMessage = l10n.tooManyRequests;
        } else if (e.code == 'user-disabled') {
          errorMessage = l10n.accountDisabled;
        } else if (e.code == 'network-request-failed') {
          errorMessage = l10n.networkError;
        } else {
          errorMessage = l10n.errorWithCode(e.message ?? e.code);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.unexpectedErrorWithMessage(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResending = true);
    await _sendVerificationEmail();
    setState(() => _isResending = false);
  }

  Future<void> _exitVerification() async {
    // Await sign-out before navigating: once the user is anonymous the router
    // redirect no longer bounces back to /verify_email, so navigation works on
    // the first tap (previously it took two taps - F-004).
    _timer?.cancel();
    _countdownTimer?.cancel();
    await AuthService().signOutToAnonymous();
    if (!mounted) return;
    context.popOrHome();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _exitVerification();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verifyEmail),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _exitVerification(),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset('assets/logo.png', height: 80),
                        const SizedBox(height: 40),

                        const Icon(
                          Icons.email_outlined,
                          size: 80,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 24),

                        Text(
                          l10n.verifyYourEmail,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        Text(
                          l10n.verificationEmailSentTo,
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),

                        Text(
                          user?.email ?? '',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                l10n.instructions,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.instructionsSteps,
                                style: const TextStyle(fontSize: 14),
                              ),
                              if (_isChecking)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(l10n.checkingVerificationStatus),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        ElevatedButton.icon(
                          onPressed: _countdown == 0 && !_isResending
                              ? _resendVerificationEmail
                              : null,
                          icon: _isResending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            _countdown > 0
                                ? l10n.resendInSeconds(_countdown)
                                : l10n.resendVerificationEmail,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        OutlinedButton(
                          onPressed: _checkEmailVerified,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(l10n.iveVerifiedMyEmail),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Fixed bottom buttons - outside ScrollView for reliable tapping
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton(
                      onPressed: () => _exitVerification(),
                      child: Text(
                        l10n.cancelAndSignOut,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    // Development bypass (remove in production)
                    if (kDebugMode)
                      TextButton(
                        onPressed: () => context.push(Routes.completeProfile),
                        child: Text(
                          l10n.skipDevOnly,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}