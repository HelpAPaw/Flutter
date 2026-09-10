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
/// member, named like the member, and a tap that reports which one.
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

  VetClinic clinicWith(String id, {required String name, String address = ''}) =>
      VetClinic(
        id: id,
        name: name,
        address: address,
        latitude: 42.69,
        longitude: 23.32,
      );

  /// Opens the sheet the way the map does, for whatever member type the test
  /// is about.
  Future<void> open<T>(
    WidgetTester tester,
    List<T> members, {
    required String Function(AppLocalizations l10n, int count) title,
    required Widget Function(T item) row,
    Locale locale = const Locale('en'),
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
                onPressed: () => showClusterItemsSheet<T>(
                  context: context,
                  title: title(AppLocalizations.of(context), members.length),
                  items: members,
                  row: (_, item) => row(item),
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

  testWidgets('one row per signal, titled like the signal', (tester) async {
    await open<SignalWithId>(
      tester,
      [
        signalWith('a', title: 'Cat on the roof'),
        signalWith('b', title: 'Dog by the tram stop'),
        signalWith('c', title: 'Pigeon with a broken wing'),
        signalWith('d', title: 'Kitten in a drain'),
      ],
      title: (l10n, count) => l10n.clusterSignalsHere(count),
      row: (signal) => SignalClusterRow(signal: signal, onTap: () {}),
    );

    expect(find.text('4 signals here'), findsOneWidget);
    expect(find.bySemanticsIdentifier('clusterSignalRow'), findsNWidgets(4));
    expect(find.text('Cat on the roof'), findsOneWidget);
    expect(find.text('Kitten in a drain'), findsOneWidget);
  });

  testWidgets('a signal row tap reports its signal', (tester) async {
    String? tapped;
    await open<SignalWithId>(
      tester,
      [signalWith('a', title: 'First'), signalWith('b', title: 'Second')],
      title: (l10n, count) => l10n.clusterSignalsHere(count),
      row: (signal) =>
          SignalClusterRow(signal: signal, onTap: () => tapped = signal.id),
    );

    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(tapped, 'b');
  });

  testWidgets('an untitled signal falls back to what it needs', (tester) async {
    await open<SignalWithId>(
      tester,
      [signalWith('a', title: '')],
      title: (l10n, count) => l10n.clusterSignalsHere(count),
      row: (signal) => SignalClusterRow(signal: signal, onTap: () {}),
    );

    expect(find.text('1 signal here'), findsOneWidget);
    expect(find.bySemanticsIdentifier('clusterSignalRow'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('clinic rows show name and address and report a tap',
      (tester) async {
    String? tapped;
    await open<VetClinic>(
      tester,
      [
        clinicWith('c1', name: 'Central Vet', address: '1 Vitosha Blvd'),
        clinicWith('c2', name: 'Paws & Claws'),
      ],
      title: (l10n, count) => l10n.clusterClinicsHere(count),
      row: (clinic) =>
          ClinicClusterRow(clinic: clinic, onTap: () => tapped = clinic.id),
    );

    expect(find.text('2 vet clinics here'), findsOneWidget);
    expect(find.bySemanticsIdentifier('clusterClinicRow'), findsNWidgets(2));
    expect(find.text('1 Vitosha Blvd'), findsOneWidget);

    await tester.tap(find.text('Paws & Claws'));
    await tester.pump();

    expect(tapped, 'c2');
  });

  testWidgets('the title pluralises in Bulgarian', (tester) async {
    await open<SignalWithId>(
      tester,
      [signalWith('a'), signalWith('b')],
      title: (l10n, count) => l10n.clusterSignalsHere(count),
      row: (signal) => SignalClusterRow(signal: signal, onTap: () {}),
      locale: const Locale('bg'),
    );

    expect(find.text('2 сигнала тук'), findsOneWidget);
  });
}

class _FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
