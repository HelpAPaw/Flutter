import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:help_a_paw/src/state/panel_list.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  // About Page State
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final Uri ourSite = Uri(
    host: 'www.helpapaw.org',
    path: 'index_en.html',
    scheme: 'https',
  );
  final List<PanelItem> _itemList = generateItems(1);
  Future<void>? _browserLaunched;
  Future<void> _launchInBrowser(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication,)) {
      throw Exception('Launch Failed: $url');
    }
  }

  // About Page Widgets
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
        title: const Text('About'),
      ),
      body: AdaptiveContainer(
        child: ListView(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Image.asset('lib/assets/pawww.png'),
                  ExpansionPanelList.radio(
                    elevation: 6,
                    children: _itemList.map<ExpansionPanelRadio>((PanelItem itemList) {
                      return ExpansionPanelRadio(
                        canTapOnHeader: true,
                        value: itemList.identity,
                        headerBuilder: (BuildContext context, bool isExpanded) {
                          return const ListTile(
                            leading: Icon(Icons.book_rounded),
                            subtitle: Text('Send emergency signals about animals in need'),
                            title: Text('Help A Paw'),
                          );},
                        body: ButtonBar(
                          alignment: MainAxisAlignment.end,
                          children: <Widget>[
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
