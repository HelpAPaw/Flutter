import '../../l10n/app_localizations.dart';

/// One question in the create-a-signal wizard.
///
/// **Declaration order is the order the reporter is asked**, and it is not
/// arbitrary — three things decide it:
///
/// *Perishability.* This is an emergency reporter: someone standing in front of
/// an animal. [location] and [photo] are the only two answers that exist *only
/// right now* — text and taxonomy can be reconstructed later, a photo of an
/// animal that has moved cannot. They come first so an abandoned draft still
/// holds what matters most.
///
/// *Dependency.* Answers flow downhill. The photo primes the description, and
/// the description primes every classification below it, because [animal],
/// [signalType], [urgency] and [helpTags] are all judgements *about the
/// situation the reporter just narrated*. In particular [helpTags] must follow
/// [urgency] and not precede it: "what does this case need" is not answerable
/// before "how bad is this" is settled, since a Red hit-by-car and a healthy
/// stray produce different tag sets.
///
/// *Consequence calibration.* [urgency] is the field with teeth — Red pushes
/// every subscriber and carries a confirmation dialog. Asked early and cold it
/// invites a reflexive "Red, obviously"; asked after the reporter has had to
/// write concretely, it is calibrated. So it sits as late as it can while still
/// preceding the tags it informs.
///
/// Two things fall out of this order and should survive any future edit: all
/// keyboard input lands in a single step, so the keyboard appears once rather
/// than twice; and [animal]/[signalType]/[urgency] are consecutive, which is
/// what makes [autoAdvances] feel good rather than jumpy.
enum NewSignalStep {
  /// Answered on the map itself, not inside the wizard — see [isOnMap].
  location,
  photo,
  details,
  animal,
  signalType,
  urgency,
  helpTags,
  review;

  /// How many steps the progress indicator counts to.
  static int get count => values.length;

  /// 1-based position, for "Step 3 of 8".
  int get displayNumber => index + 1;

  /// The location is picked on the live map rather than on a wizard page, so
  /// the wizard route never renders it — it is a step only so that the progress
  /// indicator and the review screen can count and address it.
  bool get isOnMap => this == NewSignalStep.location;

  /// Whether choosing an answer here should move the reporter on by itself.
  ///
  /// True only for the single-choice steps that arrive *blank*, where the one
  /// tap is unambiguously the whole answer. Three kinds of step are excluded:
  ///
  /// - The multi-select [helpTags] and the typing steps, where there is no way
  ///   to tell a first choice from a half-finished one.
  /// - **[signalType], even though it is single-choice**, because it arrives
  ///   pre-selected on Emergency. The wizard suppresses auto-advance on any
  ///   step that already had an answer when the reporter got there — otherwise
  ///   returning to revise something throws them forward again — so listing it
  ///   here would be a flag that could never fire. It is confirmed with Next.
  ///
  /// The wizard applies that already-answered rule on top of this flag; this
  /// only says a step is *eligible*.
  bool get autoAdvances =>
      this == NewSignalStep.animal || this == NewSignalStep.urgency;

  NewSignalStep? get next =>
      index + 1 < values.length ? values[index + 1] : null;

  NewSignalStep? get previous => index > 0 ? values[index - 1] : null;

  /// Short label for the app bar.
  String title(AppLocalizations l10n) => switch (this) {
        NewSignalStep.location => l10n.newSignalStepLocation,
        NewSignalStep.photo => l10n.newSignalStepPhoto,
        NewSignalStep.details => l10n.newSignalStepDetails,
        NewSignalStep.animal => l10n.newSignalStepAnimal,
        NewSignalStep.signalType => l10n.newSignalStepType,
        NewSignalStep.urgency => l10n.newSignalStepUrgency,
        NewSignalStep.helpTags => l10n.newSignalStepHelp,
        NewSignalStep.review => l10n.newSignalStepReview,
      };

  /// The one question this step asks, shown as the page headline. Phrased as a
  /// question on purpose: the whole point of the wizard is that a reporter can
  /// answer each screen without working out what it wants from them.
  String question(AppLocalizations l10n) => switch (this) {
        NewSignalStep.location => l10n.newSignalQuestionLocation,
        NewSignalStep.photo => l10n.newSignalQuestionPhoto,
        NewSignalStep.details => l10n.newSignalQuestionDetails,
        NewSignalStep.animal => l10n.newSignalQuestionAnimal,
        NewSignalStep.signalType => l10n.newSignalQuestionType,
        NewSignalStep.urgency => l10n.newSignalQuestionUrgency,
        NewSignalStep.helpTags => l10n.newSignalQuestionHelp,
        NewSignalStep.review => l10n.newSignalQuestionReview,
      };

  /// Supporting line under [question], or null where the question stands alone.
  String? hint(AppLocalizations l10n) => switch (this) {
        NewSignalStep.location => l10n.newSignalHintLocation,
        NewSignalStep.photo => l10n.newSignalHintPhoto,
        NewSignalStep.details => l10n.newSignalHintDetails,
        NewSignalStep.urgency => l10n.newSignalHintUrgency,
        NewSignalStep.review => l10n.newSignalHintReview,
        NewSignalStep.animal || NewSignalStep.signalType => null,
        // helpTags carries the "up to N" cap instead, which the step view
        // renders itself because it needs the count.
        NewSignalStep.helpTags => null,
      };
}
