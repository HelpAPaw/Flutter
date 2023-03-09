import 'package:flutter/material.dart';
import 'package:help_a_paw/about/about.dart';

class MyDrawer extends StatelessWidget {
  final String userName;
  final String userImage;

  MyDrawer({Key? key, required this.userName, required this.userImage})
      : super(key: key);

  final Map<String, Widget> screensMap = {
    'Profile': const ProfileScreen(),
    'My Signals': const MySignalsScreen(),
    'My Notifications': const MyNotificationsScreen(),
    'FAQS': const FAQSScreen(),
    'Settings': const SettingsScreen(),
    'Feedback': const FeedbackScreen(),
    'Privacy Policy': const PrivacyPolicyScreen(),
    'About': const AboutScreen(),
    'Share': const ShareScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final widthSize = MediaQuery.of(context).size.width;
    final heightSize = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Drawer(
        backgroundColor: Colors.orange,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              height: heightSize * 0.25,
              width: widthSize,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: widthSize * 0.8,
                    height: heightSize * 0.17,
                    child: Image.asset(userImage),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    userName,
                    style: const TextStyle(fontSize: 18, color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: screensMap.length,
                itemBuilder: (BuildContext context, int index) {
                  String item = screensMap.keys.toList()[index];
                  return ListTile(
                    title: Text(
                      item,
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                    onTap: () {
                      // Handle item tap here
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => screensMap[item]!),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('ShareScreen');
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('PrivacyPolicyScreen');
  }
}

class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('FeedbackScreen');
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('SettingsScreen');
  }
}

class FAQSScreen extends StatelessWidget {
  const FAQSScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('FAQSScreen');
  }
}

class MyNotificationsScreen extends StatelessWidget {
  const MyNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('MyNotificationsScreen');
  }
}

class MySignalsScreen extends StatelessWidget {
  const MySignalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('MySignalsScreen');
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('ProfileScreen');
  }
}
