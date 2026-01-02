import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;

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

  Future<void> _submitFeedback() async {
    if (_feedbackController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final packageInfo = await PackageInfo.fromPlatform();

      final email = _emailController.text.trim();
      final feedbackData = {
        'type': _feedbackType,
        'message': _feedbackController.text.trim(),
        'userId': user?.uid,
        'email': email.isNotEmpty ? email : null,
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
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting feedback: $e')),
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          title: const Text('Send Feedback'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We\'d love to hear from you!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your feedback helps us improve Help A Paw for everyone.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Feedback Type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('General'),
                    selected: _feedbackType == 'general',
                    onSelected: (_) => setState(() => _feedbackType = 'general'),
                  ),
                  ChoiceChip(
                    label: const Text('Bug Report'),
                    selected: _feedbackType == 'bug',
                    onSelected: (_) => setState(() => _feedbackType = 'bug'),
                  ),
                  ChoiceChip(
                    label: const Text('Feature Request'),
                    selected: _feedbackType == 'feature',
                    onSelected: (_) => setState(() => _feedbackType = 'feature'),
                  ),
                  ChoiceChip(
                    label: const Text('Other'),
                    selected: _feedbackType == 'other',
                    onSelected: (_) => setState(() => _feedbackType = 'other'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Your Email (optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'email@example.com',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Provide your email if you\'d like us to follow up',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Your Feedback',
                style: TextStyle(
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
                      ? 'Please describe the issue you encountered...'
                      : _feedbackType == 'feature'
                          ? 'Tell us about the feature you\'d like to see...'
                          : 'Share your thoughts with us...',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include device information'),
                subtitle: Text(
                  'Helps us diagnose issues faster',
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
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
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
                      : const Text('Submit Feedback'),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Other ways to reach us',
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
