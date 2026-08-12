import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What kind of animal a signal is about.
///
/// Kept as its own axis rather than folded into [HelpTag], because species and
/// need are independent: "can foster" and "can foster cats" are the same
/// capability applied to different animals. Crossing the two produces the
/// cross-product the spec's 27-tag helper list writes out by hand; keeping them
/// apart means nine tags times three species, and either axis can grow without
/// touching the other (the spec starts with cats and dogs and adds more later).
///
/// A signal declares exactly one; a user subscribes to one or more.
///
/// [code] is the value persisted in Firestore — a **stable, opaque identifier**.
/// Never rename or reuse one once it has shipped.
enum AnimalType {
  cat(code: 'cat', icon: Icons.pets),
  dog(code: 'dog', icon: Icons.pets),
  other(code: 'other', icon: Icons.cruelty_free);

  const AnimalType({required this.code, required this.icon});

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final String code;

  /// Icon shown on selector chips and on signal details.
  final IconData icon;

  /// Every code, for validation and for building selector UIs.
  static final List<String> allCodes =
      List.unmodifiable(values.map((t) => t.code));

  /// Resolve a persisted [code], or null if it is unknown or absent.
  ///
  /// Nullable on purpose. A signal from an app version predating this field has
  /// no species, and that must read as "unspecified" — the fan-out then matches
  /// it to everyone rather than filtering it out. Substituting [other] here
  /// would quietly hide those signals from anyone who only wants cats or dogs.
  static AnimalType? fromCode(String? code) {
    if (code == null) return null;
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }

  /// Localized display label. Exhaustive switch so adding a species is a
  /// compile error until its label is provided here.
  String label(AppLocalizations l10n) {
    switch (this) {
      case AnimalType.cat:
        return l10n.animalTypeCat;
      case AnimalType.dog:
        return l10n.animalTypeDog;
      case AnimalType.other:
        return l10n.animalTypeOther;
    }
  }
}
