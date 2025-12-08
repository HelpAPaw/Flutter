import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FaqsPage extends StatelessWidget {
  const FaqsPage({super.key});

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
        title: const Text('FAQs'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _FaqSection(
            title: 'General',
            items: [
              _FaqItem(
                question: 'What is Help A Paw?',
                answer:
                    'Help A Paw is a mobile application that helps connect people who spot animals in distress with volunteers who can provide assistance. By creating signals on the map, you can alert the community about animals that need help.',
              ),
              _FaqItem(
                question: 'Do I need to create an account?',
                answer:
                    'You can browse signals without an account, but to create new signals or leave comments, you\'ll need to sign in. This helps us maintain the quality of reports and allows you to track your contributions.',
              ),
              _FaqItem(
                question: 'Is the app free to use?',
                answer:
                    'Yes, Help A Paw is completely free to use. We are a non-profit initiative dedicated to helping animals in need.',
              ),
            ],
          ),
          _FaqSection(
            title: 'Creating Signals',
            items: [
              _FaqItem(
                question: 'How do I create a signal?',
                answer:
                    'Tap the "+" button on the map, select the location where you spotted the animal, choose the signal type (Emergency, Lost/Found, etc.), add a description, and optionally include photos. Your signal will be visible to other users in the area.',
              ),
              _FaqItem(
                question: 'What types of signals can I create?',
                answer:
                    'You can create signals for: Emergency situations, Lost or Found animals, Blood donation needs, Homeless animals, Unneutered animals, Wild animals, and Other situations.',
              ),
              _FaqItem(
                question: 'Can I edit or delete my signal?',
                answer:
                    'Yes, you can edit or delete signals that you\'ve created. Go to "My Signals" from the menu, select the signal you want to modify, and use the edit or delete options.',
              ),
              _FaqItem(
                question: 'What should I include in a signal description?',
                answer:
                    'Include details like: the type and condition of the animal, exact location landmarks, any urgent needs (food, medical attention), your availability to help, and a contact number if you\'re comfortable sharing it.',
              ),
            ],
          ),
          _FaqSection(
            title: 'Helping Animals',
            items: [
              _FaqItem(
                question: 'How can I help with a signal?',
                answer:
                    'When you see a signal on the map, tap it to view details. You can leave a comment to coordinate with others, update the signal status if you\'re helping, or contact the person who created the signal.',
              ),
              _FaqItem(
                question: 'What do the signal statuses mean?',
                answer:
                    'Red (Needs Help): The animal still needs assistance.\nOrange (In Progress): Someone is working on helping.\nGreen (Resolved): The animal has received help or the situation is resolved.',
              ),
              _FaqItem(
                question: 'I\'m not able to help directly. What can I do?',
                answer:
                    'You can share the signal with friends who might be able to help, leave helpful comments with advice or contacts of local animal rescue organizations, or simply spread awareness about the app to grow our community of helpers.',
              ),
            ],
          ),
          _FaqSection(
            title: 'Notifications',
            items: [
              _FaqItem(
                question: 'How do notifications work?',
                answer:
                    'You\'ll receive notifications when: a new signal appears in your area, someone comments on your signal, or the status of a signal you\'re following changes. You can customize notification settings in the app.',
              ),
              _FaqItem(
                question: 'How do I change my notification radius?',
                answer:
                    'Go to Settings > Notification Radius and adjust the slider. You can set it from 1km to 50km depending on how far you\'re willing to help.',
              ),
            ],
          ),
          _FaqSection(
            title: 'Privacy & Safety',
            items: [
              _FaqItem(
                question: 'Is my personal information safe?',
                answer:
                    'We take privacy seriously. Your email is only used for account management. Phone numbers shared in signals are optional and at your discretion. Location data is only used to show relevant signals.',
              ),
              _FaqItem(
                question: 'How do I report inappropriate content?',
                answer:
                    'If you see a signal that contains inappropriate content, spam, or false information, please use the report function on the signal or contact us through the Feedback option in the menu.',
              ),
            ],
          ),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  final String title;
  final List<_FaqItem> items;

  const _FaqSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.orange[800],
            ),
          ),
        ),
        ...items,
      ],
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              answer,
              style: TextStyle(
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
