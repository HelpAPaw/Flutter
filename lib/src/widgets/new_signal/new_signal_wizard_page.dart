import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/new_signal_step.dart';
import '../../utils/nav_extensions.dart';
import '../../viewmodels/map_view_model.dart';
import 'new_signal_step_views.dart';

/// The create-a-signal wizard: one question per screen.
///
/// The reporter reaches this route having already confirmed the pin on the map
/// ([NewSignalStep.location]), so the route only ever renders steps 2–8. The
/// draft lives in `mapViewModelProvider`, not here, which is what lets the
/// review step send the reporter back to the map to revise the pin and return
/// to exactly where they were.
class NewSignalWizardPage extends ConsumerStatefulWidget {
  const NewSignalWizardPage({super.key});

  @override
  ConsumerState<NewSignalWizardPage> createState() =>
      _NewSignalWizardPageState();
}

class _NewSignalWizardPageState extends ConsumerState<NewSignalWizardPage> {
  /// How long a chosen chip stays visible before the wizard moves on. Long
  /// enough that the reporter sees their answer register, short enough that it
  /// doesn't feel like a stall.
  static const _autoAdvanceDelay = Duration(milliseconds: 250);

  /// The step [_arrivedUnanswered] was computed for.
  NewSignalStep? _arrivedOn;

  /// Whether the current step was still unanswered when the reporter arrived
  /// on it. Auto-advance is gated on this so that coming *back* to change an
  /// answer doesn't immediately fling them forward again.
  bool _arrivedUnanswered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formState = ref.watch(
      mapViewModelProvider.select((s) => s.formState),
    );
    final step = formState.step;

    if (_arrivedOn != step) {
      _arrivedOn = step;
      _arrivedUnanswered = !formState.isStepComplete(step);
    }

    final isLast = step == NewSignalStep.review;
    final canAdvance = formState.isStepComplete(step);

    return PopScope(
      // The back gesture is a step back, not an exit — except on the first
      // wizard step, where there is nowhere left to go and _leave() takes over.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(step.title(l10n)),
          leading: Semantics(
            identifier: 'newSignal.close',
            button: true,
            // Disabled mid-submit for the same reason as Back and Next below:
            // `cancelAddingNewSignal` clears the draft the in-flight submit is
            // still reading from. `submitSignal` now captures what it needs up
            // front, so this is the second lock on the same door rather than
            // the only one — but leaving the reporter able to abandon a signal
            // that is already being written is confusing whichever way the race
            // lands.
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: formState.isSubmitting ? null : _leave,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: step.displayNumber / NewSignalStep.count,
              backgroundColor: Colors.orange.shade200,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 4,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                // Required, not cosmetic. AnimatedSwitcher stacks its children
                // and hands them *loose* constraints, so the scroll view
                // shrink-wraps its content — and the default layout builder
                // centres it, parking every short step half way down the
                // screen under a large empty gap. Only the alignment differs
                // from `AnimatedSwitcher.defaultLayoutBuilder`.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                // Only the visible step is mounted — no PageView — so the
                // details step can own plain controllers seeded from state
                // instead of fighting keep-alive, and a swipe can never
                // compete with the chip rows for the gesture.
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: _buildStep(step),
                ),
              ),
            ),
            _buildFooter(
              context,
              step: step,
              canAdvance: canAdvance,
              isLast: isLast,
              isSubmitting: formState.isSubmitting,
              hasPhoto: formState.selectedImage != null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(NewSignalStep step) => switch (step) {
        NewSignalStep.photo => const NewSignalPhotoStep(),
        NewSignalStep.details => const NewSignalDetailsStep(),
        NewSignalStep.animal => NewSignalAnimalStep(onAnswered: _onAnswered),
        NewSignalStep.urgency => NewSignalUrgencyStep(onAnswered: _onAnswered),
        NewSignalStep.helpTags => const NewSignalHelpTagsStep(),
        NewSignalStep.review =>
          NewSignalReviewStep(onChangeLocation: _returnToMapForLocation),
        // The pin is picked on the map, so this route never renders it. Guard
        // rather than assert: landing here would mean an empty screen with no
        // way forward, and sending the reporter back to the map is both
        // recoverable and correct.
        NewSignalStep.location => const SizedBox.shrink(),
      };

  Widget _buildFooter(
    BuildContext context, {
    required NewSignalStep step,
    required bool canAdvance,
    required bool isLast,
    required bool isSubmitting,
    required bool hasPhoto,
  }) {
    final l10n = AppLocalizations.of(context);

    // The photo step is optional, so its button says what it will actually do.
    final label = isLast
        ? l10n.submitSignal
        : (step == NewSignalStep.photo && !hasPhoto ? l10n.skip : l10n.next);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Row(
          children: [
            Semantics(
              identifier: 'newSignal.back',
              button: true,
              child: TextButton(
                onPressed: isSubmitting ? null : _handleBack,
                child: Text(l10n.back),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                identifier: isLast ? 'newSignal.submit' : 'newSignal.next',
                button: true,
                enabled: canAdvance && !isSubmitting,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: (!canAdvance || isSubmitting)
                      ? null
                      : (isLast ? _submit : _advance),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _advance() => ref.read(mapViewModelProvider.notifier).nextStep();

  /// Called by the single-choice steps once an answer is registered.
  void _onAnswered() {
    final step = _arrivedOn;
    if (step == null || !step.autoAdvances || !_arrivedUnanswered) return;

    Future.delayed(_autoAdvanceDelay, () {
      // The reporter can tap Back, tap Close, or trigger the Red Alert dialog
      // in the gap, so re-check that this is still the step we scheduled for.
      if (!mounted) return;
      if (ref.read(mapViewModelProvider).formState.step != step) return;
      _advance();
    });
  }

  /// Back one step.
  ///
  /// Stepping back off the *first* in-route question lands on the pin, which is
  /// asked on the map — so that case leaves the route rather than moving the
  /// step. Without it the wizard would sit on [NewSignalStep.location], which
  /// it does not render, and show the reporter a blank screen. Nothing is
  /// discarded: going back to move the pin is a normal part of the flow, and
  /// the × is the way out.
  void _handleBack() {
    final previous = ref.read(mapViewModelProvider).formState.step.previous;
    if (previous == null || previous.isOnMap) {
      _returnToMapForLocation();
      return;
    }
    ref.read(mapViewModelProvider.notifier).previousStep();
  }

  /// Return to the map to revise the pin.
  ///
  /// The step is deliberately **left where it is**. The map decides what to
  /// show from `isAddingNewSignal`, not from the step, and
  /// [MapViewModel.confirmLocation] only advances a step that is still on the
  /// location question — so leaving it alone is exactly what makes the confirm
  /// bar hand the reporter back to where they were rather than restarting them.
  void _returnToMapForLocation() => context.popOrHome();

  /// Abandon the draft, confirming first if there is anything to lose.
  Future<void> _leave() async {
    final notifier = ref.read(mapViewModelProvider.notifier);
    if (ref.read(mapViewModelProvider).formState.isDirty) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) return;
    }
    notifier.cancelAddingNewSignal();
    if (mounted) context.popOrHome();
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newSignalDiscardTitle),
        content: Text(l10n.newSignalDiscardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.newSignalDiscardKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.newSignalDiscardConfirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final (success, errorMessage) =
        await ref.read(mapViewModelProvider.notifier).submitSignal();

    if (!mounted) return;

    if (success) {
      // The signal exists either way; 'photo_upload_failed' is the one case
      // where it landed without its picture, and the reporter has to be told
      // or the photo is silently dropped.
      if (errorMessage == 'photo_upload_failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.signalCreatedPhotoFailed),
            backgroundColor: Colors.orange,
          ),
        );
      }
      context.popOrHome();
      return;
    }

    FocusScope.of(context).unfocus();
    _showError(errorMessage);
  }

  void _showError(String? errorKey) {
    final l10n = AppLocalizations.of(context);

    // Per-step gating means the validation keys should be unreachable from
    // here — Next stays disabled until the step is answered. They are kept
    // because `submitSignal` is the only thing that decides what a valid
    // signal is, and a gap between it and `isStepComplete` must surface as a
    // readable message rather than a generic failure.
    final message = switch (errorKey) {
      'location_unset' => l10n.pleaseSelectLocation,
      'title_empty' => l10n.pleaseEnterTitle,
      'description_empty' => l10n.pleaseEnterDescription,
      'urgency_unset' => l10n.pleaseSelectUrgency,
      'help_tags_empty' => l10n.pleaseSelectHelpTag,
      'animal_type_unset' => l10n.pleaseSelectAnimalType,
      'not_authenticated' || 'unauthenticated' => l10n.authenticationError,
      'permission-denied' => l10n.permissionDenied,
      'unavailable' => l10n.serviceUnavailable,
      'network-request-failed' => l10n.networkError,
      _ => l10n.failedToCreateSignal,
    };

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
