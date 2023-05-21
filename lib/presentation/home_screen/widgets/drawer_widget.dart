import 'package:flutter/material.dart';
import 'package:help_a_paw/presentation/about/about.dart';
import 'package:help_a_paw/presentation/faq/faq.dart';
import 'package:url_launcher/url_launcher_string.dart';

typedef VoidCallbackWithContext = void Function(BuildContext);

const String emailTo = "help.a.paw@outlook.com";

class MyDrawer extends StatelessWidget {
  final String userName;
  final String userImage;

  const MyDrawer({Key? key, required this.userName, required this.userImage})
      : super(key: key);

  void handleNavigation(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  Map<String, Function(BuildContext)> get screensMap {
    return {
      'Profile': (BuildContext context) => {},
      'My Signals': (BuildContext context) => {},
      'My Notifications': (BuildContext context) => {},
      'FAQS': (BuildContext context) => {
            handleNavigation(context, const FAQSScreen()),
          },
      'Settings': (BuildContext context) => {},
      'Feedback': (BuildContext context) => {
            launchUrlString("mailto:$emailTo"),
          },
      'Privacy Policy': (BuildContext context) => {},
      'About': (BuildContext context) {
        handleNavigation(context, const AboutScreen());
      },
      'Share': (BuildContext context) => {},
    };
  }

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
                      screensMap[item]!(context);
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
