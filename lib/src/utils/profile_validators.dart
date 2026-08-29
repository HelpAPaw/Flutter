import 'package:help_a_paw/l10n/app_localizations.dart';

/// The rules for a person's name and phone number, in one place.
///
/// They were written twice and had drifted. "Complete your profile" required a
/// name of at least two characters and a phone number of at least eight, both
/// inline under the field. The profile *editor* — the same two fields, one tap
/// from the drawer — checked only that the name was not blank, and said so in
/// a snackbar. So a name that could not be entered on one screen could be
/// saved on the other, and the same mistake was reported two different ways.
///
/// Both are nullable-in, nullable-out so they can be handed straight to a
/// `TextFormField.validator`.
String? validateDisplayName(AppLocalizations l10n, String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return l10n.nameIsRequired;
  if (name.length < 2) return l10n.nameTooShort;
  return null;
}

/// The phone number is optional everywhere — but if one is given it has to be
/// long enough to dial, because a signal's phone number is how a volunteer
/// reaches the person standing next to the animal.
String? validatePhone(AppLocalizations l10n, String? value) {
  final phone = value?.trim() ?? '';
  if (phone.isEmpty) return null;
  if (phone.length < 8) return l10n.validPhoneNumber;
  return null;
}
