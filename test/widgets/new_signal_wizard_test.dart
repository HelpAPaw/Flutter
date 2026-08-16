import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/animal_type.dart';
import 'package:help_a_paw/src/models/help_tag.dart';
import 'package:help_a_paw/src/models/new_signal_step.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/viewmodels/map_view_model.dart';
import 'package:help_a_paw/src/widgets/new_signal/new_signal_wizard_page.dart';

/// The wizard's whole promise is that each screen asks one thing and will not
/// let the reporter past it half-answered. These are the tests for the rules
/// that hold that up — the Next gate, the back path, and the auto-advance
/// that has to fire exactly once.
void main() {
  late ProviderContainer container;
  late MapViewModel viewModel;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    viewModel = container.read(mapViewModelProvider.notifier);
    // Every test starts where the map hands over: pin confirmed, wizard open
    // on the first in-route question.
    viewModel.confirmLocation(42.0, 23.0);
  });

  Future<void> pumpWizard(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/new_signal',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('map')),
        ),
        GoRoute(
          path: '/new_signal',
          builder: (_, __) => const NewSignalWizardPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  NewSignalStep currentStep() =>
      container.read(mapViewModelProvider).formState.step;

  /// The footer's primary button — the only FilledButton on any step.
  Finder nextButton() => find.byType(FilledButton);

  bool nextIsEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(nextButton()).onPressed != null;

  testWidgets('Next stays disabled until the step is answered',
      (tester) async {
    // Checked on the help step because it is the one required step that does
    // not auto-advance, so the gate can be observed opening in place.
    viewModel.goToStep(NewSignalStep.helpTags);
    await pumpWizard(tester);

    expect(nextIsEnabled(tester), false,
        reason: 'at least one kind of help is required');

    await tester.tap(find.text(HelpTag.rescue.label(l10n)));
    await tester.pumpAndSettle();

    expect(nextIsEnabled(tester), true);
  });

  testWidgets('the photo step can be skipped but the details step cannot',
      (tester) async {
    await pumpWizard(tester);

    expect(currentStep(), NewSignalStep.photo);
    expect(nextIsEnabled(tester), true, reason: 'the photo is optional');
    // The button says what it will actually do when there is nothing to keep.
    expect(find.text(l10n.skip), findsOneWidget);

    await tester.tap(nextButton());
    await tester.pumpAndSettle();

    expect(currentStep(), NewSignalStep.details);
    expect(nextIsEnabled(tester), false,
        reason: 'title and description are both required');
  });

  testWidgets('a single-choice step advances itself, once', (tester) async {
    viewModel.goToStep(NewSignalStep.animal);
    await pumpWizard(tester);

    await tester.tap(find.text(AnimalType.dog.label(l10n)));
    await tester.pumpAndSettle();

    expect(currentStep(), NewSignalStep.urgency,
        reason: 'a first answer should carry the reporter forward');

    // Now go back and change it. This is the regression that matters: an
    // unconditional auto-advance makes an answered step impossible to revise,
    // because every tap throws the reporter forward again.
    await tester.tap(find.text(l10n.back));
    await tester.pumpAndSettle();
    expect(currentStep(), NewSignalStep.animal);

    await tester.tap(find.text(AnimalType.cat.label(l10n)));
    await tester.pumpAndSettle();

    expect(currentStep(), NewSignalStep.animal,
        reason: 'a revision must leave the reporter where they are');
    expect(
      container.read(mapViewModelProvider).formState.animalType,
      AnimalType.cat.code,
    );
  });

  testWidgets('the multi-select help step never advances itself',
      (tester) async {
    viewModel.goToStep(NewSignalStep.helpTags);
    await pumpWizard(tester);

    await tester.tap(find.text(HelpTag.rescue.label(l10n)));
    await tester.pumpAndSettle();

    expect(currentStep(), NewSignalStep.helpTags,
        reason: 'one tag chosen is not the same as finished choosing');
    expect(nextIsEnabled(tester), true);
  });

  testWidgets('Back preserves the answers already given', (tester) async {
    viewModel.goToStep(NewSignalStep.details);
    await pumpWizard(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.title),
      'Injured cat',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.description),
      'By the bus stop',
    );
    await tester.pump();

    await tester.tap(find.text(l10n.back));
    await tester.pumpAndSettle();
    expect(currentStep(), NewSignalStep.photo);

    await tester.tap(nextButton());
    await tester.pumpAndSettle();

    // Only the visible step is mounted, so returning here rebuilds the fields
    // from scratch — they have to be seeded back out of form state.
    expect(find.text('Injured cat'), findsOneWidget);
    expect(find.text('By the bus stop'), findsOneWidget);
  });

  testWidgets('leaving an untouched draft asks nothing', (tester) async {
    await pumpWizard(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text(l10n.newSignalDiscardTitle), findsNothing);
    expect(find.text('map'), findsOneWidget);
  });

  testWidgets('leaving a started draft asks before throwing it away',
      (tester) async {
    viewModel.setFormAnimalType(AnimalType.dog.code);
    await pumpWizard(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text(l10n.newSignalDiscardTitle), findsOneWidget);

    // Keep editing leaves everything exactly as it was.
    await tester.tap(find.text(l10n.newSignalDiscardKeep));
    await tester.pumpAndSettle();
    expect(find.text('map'), findsNothing);
    expect(
      container.read(mapViewModelProvider).formState.animalType,
      AnimalType.dog.code,
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.newSignalDiscardConfirm));
    await tester.pumpAndSettle();

    expect(find.text('map'), findsOneWidget);
    expect(container.read(mapViewModelProvider).isAddingNewSignal, false);
    expect(container.read(mapViewModelProvider).formState.isLocationUnset, true);
  });

  testWidgets('the review step reaches submit only on a complete form',
      (tester) async {
    viewModel.goToStep(NewSignalStep.review);
    await pumpWizard(tester);

    expect(find.text(l10n.submitSignal), findsOneWidget);
    expect(nextIsEnabled(tester), false,
        reason: 'nothing but the pin has been answered');

    viewModel.updateFormTitle('Title');
    viewModel.updateFormDescription('Description');
    viewModel.setFormUrgency(SignalUrgency.amber.code);
    viewModel.toggleFormHelpTag(HelpTag.rescue.code);
    viewModel.setFormAnimalType(AnimalType.dog.code);
    await tester.pumpAndSettle();

    expect(nextIsEnabled(tester), true);
  });

  testWidgets('changing the location from review returns to the map and back',
      (tester) async {
    viewModel.goToStep(NewSignalStep.review);
    await pumpWizard(tester);

    await tester.tap(find.text(l10n.change).first);
    await tester.pumpAndSettle();

    expect(find.text('map'), findsOneWidget);
    // The step is left on review, which is what lets the map's confirm bar
    // hand the reporter back to where they were instead of restarting them.
    expect(currentStep(), NewSignalStep.review);
    expect(container.read(mapViewModelProvider).formState.latitude, 42.0);

    // What the map's location bar does when Continue is tapped again.
    viewModel.confirmLocation(43.0, 24.0);
    expect(currentStep(), NewSignalStep.review);
    expect(container.read(mapViewModelProvider).formState.latitude, 43.0);
  });

  testWidgets('Back off the first question returns to the map, keeping the '
      'draft', (tester) async {
    // The pin is asked on the map, so there is no wizard page behind the photo
    // step. Stepping onto it would render nothing at all.
    viewModel.setFormAnimalType(AnimalType.dog.code);
    await pumpWizard(tester);
    expect(currentStep(), NewSignalStep.photo);

    await tester.tap(find.text(l10n.back));
    await tester.pumpAndSettle();

    expect(find.text('map'), findsOneWidget);
    expect(find.text(l10n.newSignalDiscardTitle), findsNothing,
        reason: 'going back to move the pin is not abandoning the report');
    expect(
      container.read(mapViewModelProvider).formState.animalType,
      AnimalType.dog.code,
    );
  });
}
