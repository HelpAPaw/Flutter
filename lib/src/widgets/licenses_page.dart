import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  // Licenses State
  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  final Uri gitHubSource = Uri(
    host: 'github.com',
    path: 'HelpAPaw/Flutter',
    scheme: 'https',
  );
  final Uri ourSite = Uri(
    host: 'www.helpapaw.org',
    path: 'index_en.html',
    scheme: 'https',
  );
  Future<void>? _browserLaunched;

  Future<void> _launchInBrowser(Uri url) async {
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Launch Failed: $url');
    }
  }

  // Licenses Widgets
  @override
  Widget build(BuildContext context) {
    FutureBuilder<void>(future: _browserLaunched, builder: _launchStatus);
    return Scaffold(
      appBar: AdaptiveAppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () => {
                  context.go('/home'),
                }),
        title: const Text('Licenses'),
      ),
      body: AdaptiveContainer(
        child: ListView(children: <Widget>[
          const AboutDialog(
            applicationName: 'Help a Paw',
            applicationLegalese: 'BSD 3-Clause "New" or "Revised" License',
            applicationVersion: '0.2.0',
          ),
          ButtonBar(
            alignment: MainAxisAlignment.end,
            children: <Widget>[
              ElevatedButton(
                child: const Text('GitHub Source'),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    content: const Text('Launch in Browser'),
                    elevation: 6,
                    icon: const Icon(Icons.open_in_browser_rounded),
                    title: const Text('Launch Mode'),
                    actions: <Widget>[
                      ElevatedButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(context, 'Cancel'),
                      ),
                      ElevatedButton(
                        child: const Text('OK'),
                        onPressed: () => setState(() {
                          Navigator.pop(context, 'OK');
                          _browserLaunched = _launchInBrowser(gitHubSource);
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              ElevatedButton(
                child: const Text('Our Site'),
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    content: const Text('Launch in Browser'),
                    elevation: 6,
                    icon: const Icon(Icons.open_in_browser_rounded),
                    title: const Text('Launch Mode'),
                    actions: <Widget>[
                      ElevatedButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(context, 'Cancel'),
                      ),
                      ElevatedButton(
                        child: const Text('OK'),
                        onPressed: () => setState(() {
                          Navigator.pop(context, 'OK');
                          _browserLaunched = _launchInBrowser(ourSite);
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _launchStatus(BuildContext context, AsyncSnapshot<void> snapshot) {
    if (snapshot.hasError) {
      throw Exception('Error: ${snapshot.error}');
    } else {
      throw Exception('Launched: $snapshot');
    }
  }
}
