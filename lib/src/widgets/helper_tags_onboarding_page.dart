import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/help_tag.dart';
import '../services/auth_service.dart';
import 'help_tag_selector.dart';

/// Full-screen, non-skippable picker for helper tags and animal types.
///
/// Shown by [HelperTagsGate] when the user has no tags — including existing
/// accounts, who would otherwise sit on the default tag forever and make the
/// whole matching system inert for the installed base.
///
/// There is no skip. The gate is the only place these are collected, and a
/// dismissible version collects them from nobody: the notification the tags
/// shape arrives days later, so there is no moment where the user feels the
/// cost of having skipped.
class HelperTagsOnboardingPage extends StatefulWidget {
  const HelperTagsOnboardingPage({
    super.key,
    required this.onSaved,
    required this.onSaveFailed,
  });

  /// Called after the choices are persisted, so the gate can re-read and hand
  /// the user through to the map.
  final VoidCallback onSaved;

  /// Called on a save that failed outright, so the gate can count it and decide
  /// when to stop blocking the app.
  ///
  /// The offline path never reaches this — that write is durable in the local
  /// cache and is treated as success. This is for the failures that repeat
  /// identically forever (rules, App Check, no session), where retrying is not
  /// a route out of a screen that has no skip, no back button and no drawer.
  /// The threshold lives in `GateBypassNotifier`, which outlives this page.
  final VoidCallback onSaveFailed;

  @override
  State<HelperTagsOnboardingPage> createState() =>
      _HelperTagsOnboardingPageState();
}

class _HelperTagsOnboardingPageState extends State<HelperTagsOnboardingPage> {

  List<String> _helperTags = const [];
  List<String> _animalTypes = const [];
  bool _isSaving = false;
  String? _error;

  bool get _isValid => _helperTags.isNotEmpty && _animalTypes.isNotEmpty;

  void _toggleHelperTag(String code) {
    setState(() {
      _error = null;
      _helperTags = toggledCode(_helperTags, code);
    });
  }

  void _toggleAnimalType(String code) {
    setState(() {
      _error = null;
      _animalTypes = toggledCode(_animalTypes, code);
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // The app always holds a session, but this screen can be the very first
      // thing a fresh install renders — so make sure of it rather than assuming.
      await AuthService().ensureAnonymousSession();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('no session');

      // Merged partial write, like every other writer of this document. A full
      // set here would wipe fcmTokens and signalSubscriptions.
      //
      // **Time-boxed, and a timeout is treated as success.** A Firestore write
      // future does not complete until the *server* acknowledges it, so with no
      // connectivity this await never returns. This screen has no skip and no
      // back button, so that leaves the user on a spinner with the map
      // unreachable — the exact opposite of the gate's own rule that we never
      // lock anyone out of reporting an animal. Retrying does not help either,
      // because offline it will always time out.
      //
      // Proceeding is safe rather than optimistic: the write is already durable
      // in Firestore's offline cache and will sync on its own, and the gate's
      // re-read falls back to that same cache, so it sees the tags and lets the
      // user through. A write that genuinely *fails* (rules, bad data) throws
      // immediately instead, and is handled below.
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(
              {
                'notificationPreferences': {
                  'helperTags': _helperTags,
                  'animalTypes': _animalTypes,
                },
              },
              SetOptions(merge: true),
            )
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        debugPrint('Helper tags: write not acknowledged; queued offline');
      }

      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      // The gate counts these and decides when to let the user through; the
      // tags stay unset either way, so the next launch asks again.
      widget.onSaveFailed();
      setState(() {
        _isSaving = false;
        _error = l10n.helperTagsSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // No AppBar back button and no drawer: there is nothing to go back to,
      // and offering an exit that does not exist reads as a bug.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.helperTagsOnboardingTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.helperTagsOnboardingIntro,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 20),
                    _sectionHeader(
                        context, l10n.helperTagsOnboardingHelpSection),
                    HelpTagChoiceList(
                      selected: _helperTags,
                      onToggle: _toggleHelperTag,
                    ),
                    const SizedBox(height: 20),
                    _sectionHeader(
                        context, l10n.helperTagsOnboardingAnimalSection),
                    const SizedBox(height: 8),
                    AnimalTypeSelector(
                      selected: _animalTypes,
                      onToggle: _toggleAnimalType,
                      semanticPrefix: 'onboardingAnimalType',
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: Semantics(
                  identifier: 'helperTagsContinue',
                  button: true,
                  enabled: _isValid && !_isSaving,
                  child: FilledButton(
                    onPressed: (_isValid && !_isSaving) ? _save : null,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.helperTagsOnboardingContinue),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      );
}
