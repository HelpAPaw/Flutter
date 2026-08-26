import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;

import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _feedbackController = TextEditingController();
  final _emailController = TextEditingController();
  String _feedbackType = 'general';
  bool _includeDeviceInfo = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Prefill email for logged-in users
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      _emailController.text = user!.email!;
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Conservative syntax check mirroring the Firestore rule and Cloud Function.
  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  bool _isValidEmail(String email) =>
      email.length <= 254 && _emailRegExp.hasMatch(email);

  Future<void> _submitFeedback() async {
    final l10n = AppLocalizations.of(context);
    if (_feedbackController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterFeedback)),
      );
      return;
    }

    // Email is optional, but if provided it must be well-formed — the backend
    // rules reject malformed addresses, so validate here for a clear message.
    final emailInput = _emailController.text.trim();
    if (emailInput.isNotEmpty && !_isValidEmail(emailInput)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidEmail)),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final packageInfo = await PackageInfo.fromPlatform();

      final feedbackData = {
        'type': _feedbackType,
        'message': _feedbackController.text.trim(),
        'userId': user?.uid,
        'email': emailInput.isNotEmpty ? emailInput : null,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'new',
      };

      if (_includeDeviceInfo) {
        feedbackData['deviceInfo'] = {
          'platform': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'appVersion': packageInfo.version,
          'buildNumber': packageInfo.buildNumber,
        };
      }

      await FirebaseFirestore.instance.collection('feedback').add(feedbackData);

      if (mounted) {
        _feedbackController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.thankYouFeedback),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorSubmittingFeedback(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.popOrHome(),
          ),
          title: AppBarTitle(l10n.sendFeedback),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.weLoveToHear,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.feedbackHelpsImprove,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.feedbackType,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.general),
                    selected: _feedbackType == 'general',
                    onSelected: (_) => setState(() => _feedbackType = 'general'),
                  ),
                  ChoiceChip(
                    label: Text(l10n.bugReport),
                    selected: _feedbackType == 'bug',
                    onSelected: (_) => setState(() => _feedbackType = 'bug'),
                  ),
                  ChoiceChip(
                    label: Text(l10n.featureRequest),
                    selected: _feedbackType == 'feature',
                    onSelected: (_) => setState(() => _feedbackType = 'feature'),
                  ),
                  ChoiceChip(
                    label: Text(l10n.other),
                    selected: _feedbackType == 'other',
                    onSelected: (_) => setState(() => _feedbackType = 'other'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.yourEmailOptional,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: l10n.emailPlaceholder,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.provideEmailForFollowUp,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.yourFeedback,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _feedbackController,
                maxLines: 6,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: _feedbackType == 'bug'
                      ? l10n.bugReportHint
                      : _feedbackType == 'feature'
                          ? l10n.featureRequestHint
                          : l10n.generalFeedbackHint,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.includeDeviceInfo),
                subtitle: Text(
                  l10n.helpsUsDiagnose,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                value: _includeDeviceInfo,
                onChanged: (value) => setState(() => _includeDeviceInfo = value ?? true),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitFeedback,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.submitFeedback),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Text(
                      l10n.otherWaysToReach,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        // Would launch email client
                      },
                      icon: const Icon(Icons.email),
                      label: const Text('contact@helpapaw.org'),
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
