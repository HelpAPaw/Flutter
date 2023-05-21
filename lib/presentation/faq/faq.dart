import 'package:flutter/material.dart';

class FAQSScreen extends StatelessWidget {
  const FAQSScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final widthSize = MediaQuery.of(context).size.width;
    final heightSize = MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _buildBody(widthSize, heightSize, context),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      centerTitle: true,
      leading: IconButton(
        color: Colors.white,
        onPressed: () {
          Navigator.pop(context);
        },
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text(
        'FAQs',
        style: TextStyle(
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBody(double widthSize, double heightSize, BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: widthSize * 0.05),
        children: faqsData
            .map(
              (item) => _buildFaqItem(
                title: item['title'],
                content: item['content'],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFaqItem({
    required String title,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${" " * 2} $title',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            content,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

final List<Map<String, dynamic>> faqsData = [
  {
    'title': 'How does this app work?',
    'content':
        'If you see a stray animal that needs help but for some reason cannot provide the help yourself you can submit a signal that marks the place and describes the situation. Other people that are nearby will receive a notification about it. Hopefully someone will react to the signal and help the animal.',
  },
  {
    'title': 'Who are the people that will help those animals?',
    'content':
        'Help A Paw connects a network of volunteers that care about animals - just like you.',
  },
  {
    'title': 'How does the status of the signal change?',
    'content':
        "When a signal is submitted it starts with status 'Help needed'. When somebody decides to answer the signal, he/she changes the status to 'Somebody on the way' so that other people know. If for example, the person arrives at the place but needs some assistance, the status can be changed back to 'Help needed'. When the animal finally receives the needed help, the signal is marked as 'Solved'. Signals are color-coded in red, orange, and green according to their status.",
  },
  {
    'title': 'Does this app track my location?',
    'content':
        'No, Your location is obtained and used only locally on your device. It will not be recorded on a server or used for any other purpose besides notifying you of animals in need in your area.',
  }
];
