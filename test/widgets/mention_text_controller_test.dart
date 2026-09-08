import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/widgets/mention_text_controller.dart';

/// The composer's controller (§7.5).
///
/// Its whole design rests on one rule — **a mention that no longer reads exactly
/// as it was inserted stops being a mention** — chosen so that no edit needs
/// diffing. These tests are that rule from both sides, plus the two boundary
/// cases that decide whether a shorter name can steal a longer one's mention.
void main() {
  MentionTextEditingController controllerWith(String text, {int? caret}) {
    final controller = MentionTextEditingController();
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    );
    return controller;
  }

  group('activeQuery', () {
    test('is null with nothing typed and null with no @ at all', () {
      expect(MentionTextEditingController().activeQuery, isNull);
      expect(controllerWith('on my way').activeQuery, isNull);
    });

    test('opens on a bare @ and narrows as you type', () {
      expect(controllerWith('thanks @').activeQuery, (start: 7, query: ''));
      expect(controllerWith('thanks @iv').activeQuery, (start: 7, query: 'iv'));
    });

    test('opens at the very start of the box', () {
      expect(controllerWith('@an').activeQuery, (start: 0, query: 'an'));
    });

    // Otherwise pasting an address opens a mention picker in the middle of
    // somebody's own domain.
    test('does not open inside an email address', () {
      expect(controllerWith('mail me at ana@shelter.bg').activeQuery, isNull);
    });

    test('closes once the query is finished with a space', () {
      expect(controllerWith('thanks @Ana ').activeQuery, isNull);
    });

    test('is null while text is selected rather than a caret sitting in it', () {
      final controller = controllerWith('thanks @iv');
      controller.selection = const TextSelection(baseOffset: 7, extentOffset: 10);
      expect(controller.activeQuery, isNull);
    });
  });

  group('insertMention', () {
    test('replaces the query, closes it, and leaves the caret after it', () {
      final controller = controllerWith('thanks @iv');
      controller.insertMention(uid: 'ivan-uid', name: 'Ivan Petrov');

      expect(controller.text, 'thanks @Ivan Petrov ');
      expect(controller.selection.baseOffset, 20);
      expect(controller.activeQuery, isNull);
      expect(controller.mentions.single.uid, 'ivan-uid');
      expect(controller.mentions.single.start, 7);
      expect(controller.mentions.single.end, 19);
    });

    test('does nothing when there is no query to replace', () {
      final controller = controllerWith('thanks');
      controller.insertMention(uid: 'ivan-uid', name: 'Ivan');
      expect(controller.text, 'thanks');
      expect(controller.mentions, isEmpty);
    });

    test('keeps two mentions apart and reports them in text order', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'boris-uid', name: 'Boris');
      controller.value = TextEditingValue(
        text: '${controller.text}and @',
        selection: const TextSelection.collapsed(offset: 12),
      );
      controller.insertMention(uid: 'ana-uid', name: 'Ana');

      expect(controller.text, '@Boris and @Ana ');
      expect(controller.mentions.map((m) => m.uid), ['boris-uid', 'ana-uid']);
    });
  });

  group('the one rule: it has to still read as what was inserted', () {
    test('editing into the name demotes it to plain text', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'ivan-uid', name: 'Ivan');
      expect(controller.mentions, hasLength(1));

      controller.value = const TextEditingValue(text: '@Iva ');
      expect(controller.mentions, isEmpty);
    });

    // The pick is remembered, not the position — so typing the name back by hand
    // brings the mention back. That is a feature of the same rule, not an
    // accident of it, and it is why nothing is removed from the pick list.
    test('retyping the name verbatim brings it back', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'ivan-uid', name: 'Ivan');
      controller.value = const TextEditingValue(text: 'nothing here');
      expect(controller.mentions, isEmpty);

      controller.value = const TextEditingValue(text: 'hello @Ivan');
      expect(controller.mentions.single.start, 6);
    });

    test('a shorter name cannot steal a longer one it sits inside', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'ana-uid', name: 'Ana');
      controller.value = const TextEditingValue(text: '@Anastasia is here');
      expect(controller.mentions, isEmpty);
    });

    test('a name inside an email address is not the mention', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'ana-uid', name: 'Ana');
      controller.value = const TextEditingValue(text: 'write to me@Ana.bg');
      expect(controller.mentions, isEmpty);
    });

    test('trailing punctuation still counts as the end of a mention', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'ana-uid', name: 'Ana');
      controller.value = const TextEditingValue(text: 'thanks @Ana, on my way');
      expect(controller.mentions.single.uid, 'ana-uid');
    });

    test('clear() forgets the picks as well as the text', () {
      final controller = controllerWith('@');
      controller.insertMention(uid: 'ana-uid', name: 'Ana');
      controller.clear();
      controller.value = const TextEditingValue(text: '@Ana');
      expect(controller.mentions, isEmpty);
    });
  });

  testWidgets('the field draws the picked name without disturbing the text',
      (tester) async {
    final controller = MentionTextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));

    await tester.enterText(find.byType(TextField), 'thanks @iv');
    controller.insertMention(uid: 'ivan-uid', name: 'Ivan Petrov');
    await tester.pump();

    expect(controller.text, 'thanks @Ivan Petrov ');
    expect(tester.takeException(), isNull);
  });
}
