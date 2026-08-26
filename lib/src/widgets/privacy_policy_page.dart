import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'status_view.dart';
import 'escape_leading.dart';

/// The privacy policy, loaded from the site.
///
/// Remote content on a screen a user is often sent to from a store listing or
/// a consent prompt, so it has to fail out loud: there was no
/// `onWebResourceError` at all, which meant a flight-mode tap left a blank
/// white page with a spinner that never stopped.
class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  static final _url = Uri.parse('https://www.helpapaw.org/privacypolicy');

  late WebViewController _controller;
  bool _isLoading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _isLoading = true;
      _failed = false;
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // Sub-resource failures (a missing font, a blocked tracker) are
            // not worth throwing the whole page away for — only the main
            // document failing means there is nothing to read.
            if (!error.isForMainFrame!) return;
            if (mounted) {
              setState(() {
                _isLoading = false;
                _failed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(_url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: escapeLeading(
            context,
            label: AppLocalizations.of(context).back,
            onLeave: () => context.popOrHome(),
          ),
        // Was `const Text('Privacy Policy')` — the app's only untranslated
        // string, on the one screen a Bulgarian user is most likely to be
        // sent to by a consent prompt.
        title: AppBarTitle(l10n.privacyPolicy),
      ),
      body: _failed
          ? StatusView.error(
              title: l10n.couldNotLoadPrivacyPolicy,
              hint: l10n.couldNotLoadPrivacyPolicyHint,
              onRetry: _load,
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
