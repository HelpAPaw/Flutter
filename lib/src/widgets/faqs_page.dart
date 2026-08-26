import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'escape_leading.dart';

class FaqsPage extends StatelessWidget {
  const FaqsPage({super.key});

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
        title: AppBarTitle(l10n.faqsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FaqSection(
            title: l10n.faqSectionGeneral,
            items: [
              _FaqItem(
                question: l10n.faqWhatIsHelpAPaw,
                answer: l10n.faqWhatIsHelpAPawAnswer,
              ),
              _FaqItem(
                question: l10n.faqNeedAccount,
                answer: l10n.faqNeedAccountAnswer,
              ),
              _FaqItem(
                question: l10n.faqIsFree,
                answer: l10n.faqIsFreeAnswer,
              ),
            ],
          ),
          _FaqSection(
            title: l10n.faqSectionCreatingSignals,
            items: [
              _FaqItem(
                question: l10n.faqHowCreateSignal,
                answer: l10n.faqHowCreateSignalAnswer,
              ),
              _FaqItem(
                question: l10n.faqWhatTypesSignals,
                answer: l10n.faqWhatTypesSignalsAnswer,
              ),
              _FaqItem(
                question: l10n.faqCanEditDelete,
                answer: l10n.faqCanEditDeleteAnswer,
              ),
              _FaqItem(
                question: l10n.faqWhatIncludeDescription,
                answer: l10n.faqWhatIncludeDescriptionAnswer,
              ),
            ],
          ),
          _FaqSection(
            title: l10n.faqSectionHelpingAnimals,
            items: [
              _FaqItem(
                question: l10n.faqHowHelp,
                answer: l10n.faqHowHelpAnswer,
              ),
              _FaqItem(
                question: l10n.faqWhatUrgencyMeans,
                answer: l10n.faqWhatUrgencyMeansAnswer,
              ),
              _FaqItem(
                question: l10n.faqWhatStatusesMean,
                answer: l10n.faqWhatStatusesMeanAnswer,
              ),
              _FaqItem(
                question: l10n.faqCantHelpDirectly,
                answer: l10n.faqCantHelpDirectlyAnswer,
              ),
            ],
          ),
          _FaqSection(
            title: l10n.faqSectionNotifications,
            items: [
              _FaqItem(
                question: l10n.faqHowNotificationsWork,
                answer: l10n.faqHowNotificationsWorkAnswer,
              ),
              _FaqItem(
                question: l10n.faqChangeNotificationRadius,
                answer: l10n.faqChangeNotificationRadiusAnswer,
              ),
            ],
          ),
          _FaqSection(
            title: l10n.faqSectionPrivacySafety,
            items: [
              _FaqItem(
                question: l10n.faqPersonalInfoSafe,
                answer: l10n.faqPersonalInfoSafeAnswer,
              ),
              _FaqItem(
                question: l10n.faqReportInappropriate,
                answer: l10n.faqReportInappropriateAnswer,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  final String title;
  final List<_FaqItem> items;

  const _FaqSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ...items,
      ],
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              answer,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
