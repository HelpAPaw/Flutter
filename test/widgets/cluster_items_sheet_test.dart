import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/vet_clinic.dart';
import 'package:help_a_paw/src/repositories/signal_repository.dart';
import 'package:help_a_paw/src/widgets/map/cluster_items_sheet.dart';

/// The sheet that opens for a cluster the camera cannot split. Its whole job is
/// to make every member reachable, so the tests are about the rows: one per
/// signal, titled like the signal, and a tap that reports which one.
void main() {
  SignalWithId signalWith(String id, {String title = 'Injured dog'}) {
    final signal = Signal(
      title: title,
      description: 'description',
      phoneNumber: '',
      location: const {},
      reporter: _FakeDocumentReference(),
      contactPhone: '',
      createdAt: null,
      urgency: 1,
      helpNeededTags: const [],
      photoUrls: const [],
    );
    return SignalWithId(
      id: id,
      signal: signal,
      rawData: {
        'location': {'geopoint': const GeoPoint(42.6977, 23.3219)},
        'status': 0,
      },
    );
  }

  Future<void> open(
    WidgetTester tester,
    List<SignalWithId> members, {
    Locale locale = const Locale('en'),
    void Function(SignalWithId)? onRowTap,
  }) async {
    tester.view.physicalSize = const Size(1233, 2154); // 411dp phone
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showClusterItemsSheet(
                  context: context,
                  title: AppLocalizations.of(context)
                      .clusterSignalsHere(members.length),
                  itemCount: members.length,
                  itemBuilder: (_, index) => SignalClusterRow(
                    signal: members[index],
                    onTap: () => onRowTap?.call(members[index]),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('one row per member, titled like the signal', (tester) async {
    await open(tester, [
      signalWith('a', title: 'Cat on the roof'),
      signalWith('b', title: 'Dog by the tram stop'),
      signalWith('c', title: 'Pigeon with a broken wing'),
      signalWith('d', title: 'Kitten in a drain'),
    ]);

    expect(find.text('4 signals here'), findsOneWidget);
    expect(find.bySemanticsIdentifier('clusterSignalRow'), findsNWidgets(4));
    expect(find.text('Cat on the roof'), findsOneWidget);
    expect(find.text('Kitten in a drain'), findsOneWidget);
  });

  testWidgets('a row tap reports its signal', (tester) async {
    SignalWithId? tapped;
    await open(
      tester,
      [signalWith('a', title: 'First'), signalWith('b', title: 'Second')],
      onRowTap: (s) => tapped = s,
    );

    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(tapped?.id, 'b');
  });

  testWidgets('clinic rows show name and address and report a tap',
      (tester) async {
    String? tapped;
    final clinics = [
      VetClinic(
        id: 'c1',
        name: 'Central Vet',
        address: '1 Vitosha Blvd',
        latitude: 42.69,
        longitude: 23.32,
      ),
      VetClinic(
        id: 'c2',
        name: 'Paws & Claws',
        address: '',
        latitude: 42.69,
        longitude: 23.32,
      ),
    ];
    tester.view.physicalSize = const Size(1233, 2154);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showClusterItemsSheet(
                  context: context,
                  title: AppLocalizations.of(context)
                      .clusterClinicsHere(clinics.length),
                  itemCount: clinics.length,
                  itemBuilder: (_, i) => ClinicClusterRow(
                    clinic: clinics[i],
                    onTap: () => tapped = clinics[i].id,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('2 vet clinics here'), findsOneWidget);
    expect(find.bySemanticsIdentifier('clusterClinicRow'), findsNWidgets(2));
    expect(find.text('1 Vitosha Blvd'), findsOneWidget);
    await tester.tap(find.text('Paws & Claws'));
    await tester.pump();
    expect(tapped, 'c2');
  });

  testWidgets('the title pluralises in Bulgarian', (tester) async {
    await open(
      tester,
      [signalWith('a'), signalWith('b')],
      locale: const Locale('bg'),
    );
    expect(find.text('2 сигнала тук'), findsOneWidget);
  });
}

class _FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
