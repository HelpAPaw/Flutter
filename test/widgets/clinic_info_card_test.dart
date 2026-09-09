import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/vet_clinic.dart';
import 'package:help_a_paw/src/widgets/map/clinic_info_card.dart';
import 'package:help_a_paw/src/widgets/map/map_bubble.dart';

/// The clinic bubble shares its shell with the signal bubble, so what is worth
/// testing here is the content: a Places result can carry a very long name and
/// a very long address, and the bubble is only 260dp wide.
void main() {
  VetClinic clinicWith({
    String name = 'Central Vet Clinic',
    String address = '12 Vitosha Blvd, Sofia',
  }) =>
      VetClinic(
        id: 'clinic-1',
        name: name,
        address: address,
        latitude: 42.6977,
        longitude: 23.3219,
      );

  Future<void> pump(WidgetTester tester, VetClinic clinic,
      {VoidCallback? onTap, double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(1233, 2154); // 411dp phone
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('bg'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: ClinicInfoCard(clinic: clinic, onTap: onTap ?? () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the clinic name and address', (tester) async {
    await pump(tester, clinicWith());
    expect(find.text('Central Vet Clinic'), findsOneWidget);
    expect(find.text('12 Vitosha Blvd, Sofia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long name and address are clipped, not overflowed',
      (tester) async {
    await pump(
      tester,
      clinicWith(
        name: 'Многопрофилна ветеринарна клиника "България" — денонощна',
        address:
            'ж.к. Горна баня, ул. "Лилия" 8, 1614 София, България, ет. 2, ап. 5',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ClinicInfoCard)).width, MapBubble.width);
  });

  testWidgets('the whole bubble is one tap target', (tester) async {
    var taps = 0;
    await pump(tester, clinicWith(), onTap: () => taps++);
    await tester.tap(find.text('Central Vet Clinic'));
    expect(taps, 1);
  });

  /// [ClinicInfoCard.maxHeightFor] decides whether the bubble fits above its
  /// pin or has to flip below it, so it has to be an upper bound — and a *tight*
  /// one. It used to count the name in both of its halves and add the badge to
  /// the text beside it, over-estimating by about half a bubble, which flipped
  /// bubbles that would have cleared the pin comfortably.
  group('maxHeightFor', () {
    for (final scale in [0.85, 1.0, 1.3, 2.0]) {
      testWidgets('bounds the worst case at text scale $scale, tightly',
          (tester) async {
        await pump(
          tester,
          clinicWith(
            name: 'Ветеринарна клиника и хотел за кучета и котки „Добро сърце“',
            address: 'ж.к. Младост 4, бул. „Александър Малинов“ 78, 1712 София',
          ),
          textScale: scale,
        );

        final rendered = tester.getSize(find.byType(ClinicInfoCard)).height;
        final estimate = ClinicInfoCard.maxHeightFor(
          tester.element(find.byType(ClinicInfoCard)),
        );

        expect(rendered, lessThanOrEqualTo(estimate),
            reason: 'the estimate has to be an upper bound');
        expect(estimate, lessThan(rendered * 1.25),
            reason: 'and close enough to it to be worth having');
      });
    }
  });
}
