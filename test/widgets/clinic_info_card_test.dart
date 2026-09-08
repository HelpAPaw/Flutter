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
      {VoidCallback? onTap}) async {
    tester.view.physicalSize = const Size(1233, 2154); // 411dp phone
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('bg'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: ClinicInfoCard(clinic: clinic, onTap: onTap ?? () {}),
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
}
