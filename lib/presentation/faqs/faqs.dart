import 'package:flutter/material.dart';
import 'package:help_a_paw/presentation/faqs/widgets/Answer.dart';
import 'package:help_a_paw/presentation/faqs/widgets/Question.dart';

class FAQSScreen extends StatelessWidget {
  const FAQSScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final heightSize = MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: AppBar(
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
              fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: Stack(
        //alignment: Alignment.center,
        children: [
          IgnorePointer(
              child: Center(
                  child: Opacity(
            opacity: 0.05,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                ),
                child: Image.asset('assets/images/logo.jpg')),
          ))),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Question(text: 'How does this app work?'),
                Answer(
                    text:
                        'if you see a stray animal that needs help but for some reason cannot provide the help yourself you can submit a signal that marks the place and describes the situation. Other people that are nearby will receive a notification about it.\nHopefully someone will react the signal and help the animal.'),
                SizedBox(
                  height: heightSize * 0.05,
                ),
                Question(
                    text: 'Who are the people that will help those animals?'),
                Answer(
                    text:
                        'Help A Paw connects a network of volunteers that care about animals - just like you!'),
                SizedBox(
                  height: heightSize * 0.05,
                ),
                Question(text: 'Who does the status of the signal change?'),
                Answer(
                    text:
                        'When a signal is submitted it starts with status \'Help needed\'. When somebody decides to answer the signal he/she changes the status to \'Somebody on the way\' so that other people know. If for example the person arrives at the place but needs some assistance the status can be changed back to \'Help needed\'.When the animal finally receives the needed help the signal is marked as \'Solves\'. Signals are color-coded in red, orange and green according to the status.'),
                SizedBox(
                  height: heightSize * 0.05,
                ),
                Question(text: 'Does this app track my location?'),
                Answer(
                    text:
                        'No. Your location is obtained and used only locally on your device. It will not be recorded on a server or used with any other purpose beside notifying you of animals in need in your area.')
              ],
            ),
          ),
        ],
      ),
    );
  }
}
