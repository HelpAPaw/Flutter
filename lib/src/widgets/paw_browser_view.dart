import 'dart:async';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/model/browser_view_model.dart';
import 'package:url_launcher/url_launcher.dart';

class PawBrowserView extends StatefulWidget {
  const PawBrowserView({super.key});

  // Help a Paw Browser View State
  @override
  State<PawBrowserView> createState() => _PawBrowserViewState();
}

class _PawBrowserViewState extends State<PawBrowserView> {
  Future<void>? _browserLaunched;

  Future<void> _launchBrowser(Uri url) async {
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Browser Launch Failed: $url');
    }
  }

  // Help a Paw Browser View Widgets
  @override
  Widget build(BuildContext context) {
    final Uri launchUrl = Uri(
        scheme: 'https', host: 'www.helpapaw.org', path: 'subjects/view-all');
    FutureBuilder<void>(
        future: _browserLaunched, builder: _browserLaunchStatus);
    return Scaffold(
      appBar: AdaptiveAppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () => {
                  context.go('/home'),
                }),
        title: const Text(
          'Help a Paw',
          softWrap: true,
        ),
      ),
      body: AdaptiveContainer(
        child: Card(
          child: Column(children: <Widget>[
            Image.asset('lib/assets/pawww.png'),
            ListTile(
              leading: Image.asset('lib/assets/icon/pet/shiba_inu.png'),
              subtitle: const Text(
                'Send emergency signals about animals in need',
                softWrap: true,
              ),
              title: const Text(
                'Help a Paw',
                softWrap: true,
              ),
            ),
            ButtonBar(alignment: MainAxisAlignment.end, children: <Widget>[
              ElevatedButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => BrowserViewModel(
                    browserLaunchedAspect: _browserLaunched,
                    child: AlertDialog(
                        content: const Text(
                          'View Help a Paw Website',
                          softWrap: true,
                        ),
                        title: const Text(
                          'Launch Browser',
                          softWrap: true,
                        ),
                        actions: <Widget>[
                          ButtonBar(
                            alignment: MainAxisAlignment.center,
                            children: <Widget>[
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(context, 'Cancel'),
                                child: const Text(
                                  'Cancel',
                                  softWrap: true,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => setState(() {
                                  _browserLaunched = _launchBrowser(launchUrl);
                                }),
                                child: const Text(
                                  'Launch',
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ]),
                  ),
                ),
                child: const Text(
                  'Visit Help a Paw',
                  softWrap: true,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

Widget _browserLaunchStatus(
    BuildContext context, AsyncSnapshot<void> snapshot) {
  if (snapshot.hasError) {
    return Text('Snapshot Error: ${snapshot.error}');
  } else {
    return const Text('Launching Browser');
  }
}
