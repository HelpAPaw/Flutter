import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        title: const Text('Privacy Policy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final url = Uri.parse('https://www.helpapaw.org/privacy-policy');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            tooltip: 'Open in browser',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last updated: December 2025',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            const _PolicySection(
              title: 'Introduction',
              content:
                  'Help A Paw ("we", "our", or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.',
            ),
            const _PolicySection(
              title: 'Information We Collect',
              content: '''We collect information that you provide directly to us:

• Account Information: When you create an account, we collect your email address and display name.

• Signal Data: When you create a signal, we collect the location, description, photos, and contact information you provide.

• Device Information: With your consent, we may collect device information to improve our services and troubleshoot issues.

• Location Data: We collect your location to show relevant signals near you and to place signals you create on the map.''',
            ),
            const _PolicySection(
              title: 'How We Use Your Information',
              content: '''We use the information we collect to:

• Provide, maintain, and improve our services
• Display signals on the map and notify nearby users
• Send you notifications about signals you've created or followed
• Respond to your feedback and support requests
• Detect and prevent fraud and abuse''',
            ),
            const _PolicySection(
              title: 'Information Sharing',
              content: '''We may share your information in the following circumstances:

• Signal Information: When you create a signal, the information you provide (except your email) is visible to other users.

• Service Providers: We may share information with third-party service providers who assist us in operating our app (e.g., Firebase, Google Maps).

• Legal Requirements: We may disclose information if required by law or to protect our rights and the safety of others.''',
            ),
            const _PolicySection(
              title: 'Data Security',
              content:
                  'We implement appropriate technical and organizational measures to protect your personal information. However, no method of transmission over the internet is 100% secure, and we cannot guarantee absolute security.',
            ),
            const _PolicySection(
              title: 'Your Rights',
              content: '''You have the right to:

• Access, correct, or delete your personal information
• Opt out of receiving notifications
• Request a copy of your data
• Delete your account at any time

To exercise these rights, please contact us through the Feedback section of the app or email us directly.''',
            ),
            const _PolicySection(
              title: 'Children\'s Privacy',
              content:
                  'Our service is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13.',
            ),
            const _PolicySection(
              title: 'Changes to This Policy',
              content:
                  'We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last updated" date.',
            ),
            const _PolicySection(
              title: 'Contact Us',
              content:
                  'If you have questions about this Privacy Policy, please contact us at:',
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Help A Paw',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final url = Uri.parse('mailto:contact@helpapaw.org');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.email, size: 16, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'contact@helpapaw.org',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final url = Uri.parse('https://www.helpapaw.org');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.language, size: 16, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'www.helpapaw.org',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String content;

  const _PolicySection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
