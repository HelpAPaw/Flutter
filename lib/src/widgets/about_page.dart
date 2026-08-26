import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/nav_extensions.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final version = _packageInfo?.version ?? '...';
    final build = _packageInfo?.buildNumber ?? '...';
    final year = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrHome(),
        ),
        title: Text(l10n.aboutTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Image.asset(
              'assets/logo.png',
              height: 120,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.helpAPaw,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.version(version, build),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.appDescription,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              l10n.aboutDescription,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text(
              l10n.connectWithUs,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _launchUrl('https://www.helpapaw.org'),
                  icon: const Icon(Icons.language),
                  label: Text(l10n.website),
                ),
                OutlinedButton.icon(
                  onPressed: () => _launchUrl('https://www.facebook.com/HelpAPaw'),
                  icon: const Icon(Icons.facebook),
                  label: Text(l10n.facebook),
                ),
                OutlinedButton.icon(
                  onPressed: () => _launchUrl('https://github.com/HelpAPaw'),
                  icon: const Icon(Icons.code),
                  label: Text(l10n.gitHub),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                showLicensePage(
                  context: context,
                  applicationName: l10n.helpAPaw,
                  applicationVersion: _packageInfo?.version,
                  applicationIcon: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.asset('assets/logo.png', height: 48),
                  ),
                );
              },
              child: Text(l10n.openSourceLicenses),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.copyright(year),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
