import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  AboutScreenState createState() => AboutScreenState();
}

class AboutScreenState extends State<AboutScreen> {
  String _buildVersion = 'Unknown';

  @override
  void initState() {
    super.initState();
    _getBuildVersion();
  }

  Future<void> _getBuildVersion() async {
    String yamlString = await rootBundle.loadString('pubspec.yaml');
    RegExp exp = RegExp(r'^version:\s+(\S+)$', multiLine: true);
    Match? match = exp.firstMatch(yamlString);
    if (match != null) {
      String buildNumber = match.group(1)!;
      setState(() {
        _buildVersion = buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final widthSize = MediaQuery.of(context).size.width;
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
          'About',
          style: TextStyle(
              fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Add your app's logo here
            Image.asset(
              'assets/images/paww.png',
              width: widthSize * 0.7,
              height: heightSize * 0.3,
            ),
            const SizedBox(height: 20.0),
            // Add your app's name here
            const Text(
              'Help A Paw',
              style: TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
            ),
            const SizedBox(height: 20.0),
            Text(
              _buildVersion,
              style: const TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
            ),
            const SizedBox(height: 20.0),
            // Add a button that links to your contact page
            SizedBox(
              width: widthSize * 0.5,
              height: heightSize * 0.07,
              child: ElevatedButton(
                onPressed: () {
                  // Add your code to navigate to your contact page
                },
                child: const Text('Contact Us',
                    style: TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
