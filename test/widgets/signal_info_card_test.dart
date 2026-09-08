import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/help_tag.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/repositories/signal_repository.dart';
import 'package:help_a_paw/src/widgets/help_tag_pill.dart';
import 'package:help_a_paw/src/widgets/map/map_bubble.dart';
import 'package:help_a_paw/src/widgets/map/signal_info_card.dart';

/// The bubble that replaced the native Maps InfoWindow. It renders whatever a
/// signal happens to carry, and most of what it carries is optional: signals
/// are commonly reported with no photo, often with no title, and everything
/// written before the tags feature has no tags at all.
void main() {
  SignalWithId signalWith({
    String title = 'Injured dog by the bus stop',
    List<String> photoUrls = const [],
    List<String> tags = const [],
    int urgency = 1,
    int? legacySignalType,
  }) {
    final signal = Signal(
      title: title,
      description: 'description',
      phoneNumber: '',
      location: const {},
      reporter: _FakeDocumentReference(),
      contactPhone: '',
      createdAt: null,
      urgency: urgency,
      helpNeededTags: tags,
      legacySignalType: legacySignalType,
      photoUrls: photoUrls,
    );
    return SignalWithId(
      id: 'signal-1',
      signal: signal,
      rawData: {
        'location': {'geopoint': const GeoPoint(42.6977, 23.3219)},
        'status': 0,
      },
    );
  }

  Future<void> pump(
    WidgetTester tester,
    SignalWithId signal, {
    Locale locale = const Locale('en'),
    bool tailDown = true,
    VoidCallback onTap = _noop,
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
          body: Center(
            child: SignalInfoCard(
              signal: signal,
              tailDown: tailDown,
              onTap: onTap,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the title and one pill per need', (tester) async {
    await pump(
      tester,
      signalWith(tags: [
        HelpTag.vetCare.code,
        HelpTag.food.code,
        HelpTag.transport.code,
      ]),
    );

    expect(find.text('Injured dog by the bus stop'), findsOneWidget);
    expect(find.byType(HelpTagPill), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an untagged signal shows no pills at all', (tester) async {
    // Deliberately not the fallback tag: SignalStateCard drops unknown and
    // absent tags the same way, and a bubble that invented "Rescue" would be
    // claiming the reporter asked for something they never did.
    await pump(tester, signalWith());
    expect(find.byType(HelpTagPill), findsNothing);
  });

  testWidgets('an unknown tag code is dropped, known ones survive',
      (tester) async {
    await pump(tester, signalWith(tags: ['not-a-tag', HelpTag.food.code]));
    expect(find.byType(HelpTagPill), findsOneWidget);
  });

  testWidgets('a signal with no title falls back to what it needs',
      (tester) async {
    await pump(tester, signalWith(title: '', tags: [HelpTag.vetCare.code]));
    expect(find.text('Vet care needed'), findsOneWidget);
  });

  testWidgets('a signal with no photo shows its need on an urgency tint',
      (tester) async {
    await pump(
      tester,
      signalWith(tags: [HelpTag.food.code], urgency: SignalUrgency.red.code),
    );

    final icon = tester.widget<Icon>(find.byIcon(HelpTag.food.icon).first);
    expect(icon.color, SignalUrgency.red.color);
  });

  testWidgets('the tail flips to the top when the bubble sits below the pin',
      (tester) async {
    final tail = find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.size == const Size(16, MapBubble.tailHeight));

    await pump(tester, signalWith(), tailDown: true);
    expect(tester.getRect(tail).bottom,
        tester.getRect(find.byType(SignalInfoCard)).bottom);

    await pump(tester, signalWith(), tailDown: false);
    expect(tester.getRect(tail).top,
        tester.getRect(find.byType(SignalInfoCard)).top);
  });

  testWidgets('the whole bubble is one tap target', (tester) async {
    var taps = 0;
    await pump(
      tester,
      signalWith(tags: [HelpTag.food.code]),
      onTap: () => taps++,
    );

    // On a pill, which is the part most likely to swallow the tap.
    await tester.tap(find.byType(HelpTagPill));
    expect(taps, 1);
  });

  testWidgets('three Bulgarian needs fit without overflowing', (tester) async {
    // Bulgarian labels run 40–70% longer than English, and the bubble is only
    // 260dp wide — this is where it breaks first, and RenderFlex overflow
    // paints nothing at all in a release build.
    await pump(
      tester,
      signalWith(
        title: 'Ранено куче до автобусната спирка на бул. Витоша',
        tags: [
          HelpTag.vetCare.code,
          HelpTag.transport.code,
          HelpTag.fundraising.code,
        ],
      ),
      locale: const Locale('bg'),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(SignalInfoCard)).width,
        MapBubble.width);
  });
}

void _noop() {}

/// A signal's `reporter` is a [DocumentReference], which cannot be built
/// without an initialised Firebase app. The bubble never reads it — and this
/// throws rather than returning null so that an accidental read shows up as a
/// failure instead of silently rendering nothing.
class _FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
