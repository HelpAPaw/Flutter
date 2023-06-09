import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:help_a_paw/src/state/panel_list.dart';

class InDev extends StatefulWidget {
  const InDev({super.key});

  // In Development State
  @override
  State<InDev> createState() => _InDevState();
}

class _InDevState extends State<InDev> {
  final List<PanelItem> _itemList = generateItems(1);
  Future<void>? _browserLaunched;

  Future<void> _launchInBrowser(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication,)) {
      throw Exception('Launch Failed: $url');
    }
  }

  // In Development Widgets
  @override
  Widget build(BuildContext context) {
    final Uri gitHubSource = Uri(
      host: 'github.com',
      path: 'HelpAPaw/Flutter',
      scheme: 'https',
    );
    FutureBuilder<void>(future: _browserLaunched, builder: _launchStatus);
    return Scaffold(
      appBar: AdaptiveAppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () => {
              context.go('/home'),
            }),
        title: const Text('About'),
      ),
      body: AdaptiveContainer(
        child: ListView(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Image.asset('lib/assets/in_development.png'),
                  ExpansionPanelList.radio(
                    elevation: 6,
                    children: _itemList.map<ExpansionPanelRadio>((PanelItem itemList) {
                      return ExpansionPanelRadio(
                        canTapOnHeader: true,
                        value: itemList.identity,
                        headerBuilder: (BuildContext context, bool isExpanded) {
                          return const ListTile(
                            leading: Icon(Icons.book_rounded),
                            subtitle: Text('Feature is in Development'),
                            title: Text('Life Cycle'),
                          );},
                        body: ButtonBar(
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
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ]
        ),
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
