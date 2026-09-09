import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../services/app_preferences_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

enum _OnboardingStep { notifications, location, region }

class NotificationOnboardingSheet extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onDismiss;

  const NotificationOnboardingSheet({
    super.key,
    required this.onComplete,
    required this.onDismiss,
  });

  @override
  State<NotificationOnboardingSheet> createState() => _NotificationOnboardingSheetState();
}

class _NotificationOnboardingSheetState extends State<NotificationOnboardingSheet> {
  bool _isLoading = true;
  List<_OnboardingStep> _stepsToShow = [];
  int _currentStepIndex = 0;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _determineSteps();
  }

  Future<void> _determineSteps() async {
    final steps = <_OnboardingStep>[];

    // Check notification permission
    if (!await NotificationService().hasNotificationPermission()) {
      steps.add(_OnboardingStep.notifications);
    }

    // Check location permission
    final locationPermission = await Geolocator.checkPermission();
    if (!locationPermission.grantsLocation) steps.add(_OnboardingStep.location);

    // Check region selection — use timeout to prevent hang while waiting for App Check token
    final user = FirebaseAuth.instance.currentUser;
    bool regionSet = false;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 10));
        regionSet = doc.data()?['notificationPreferences']?['regionOfInterest'] != null;
      } catch (e) {
        // Timeout or Firestore error — treat as region not set
      }
    }
    if (!regionSet) steps.add(_OnboardingStep.region);

    if (!mounted) return;

    if (steps.isEmpty) {
      // All steps already complete - silently finish onboarding
      await AppPreferencesService().setOnboardingCompleted(true);
      if (!mounted) return;
      widget.onComplete();
      return;
    }

    setState(() {
      _stepsToShow = steps;
      _isLoading = false;
    });
  }

  Future<void> _completeOnboarding() async {
    await AppPreferencesService().setOnboardingCompleted(true);
    widget.onComplete();
  }

  void _advanceStep() {
    final nextIndex = _currentStepIndex + 1;
    if (nextIndex >= _stepsToShow.length) {
      _completeOnboarding();
    } else {
      setState(() {
        _currentStepIndex = nextIndex;
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleEnableNotifications() async {
    setState(() => _isProcessing = true);

    try {
      final notificationGranted = await NotificationService().requestNotificationPermission();

      if (!mounted) return;

      if (notificationGranted) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
              {'notificationPreferences': {'enabled': true}},
              SetOptions(merge: true),
            ).timeout(const Duration(seconds: 10));
          } catch (e) {
            // Timeout or Firestore error — continue onboarding
          }
        }
      }

      _advanceStep();
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleEnableLocation() async {
    setState(() => _isProcessing = true);

    try {
      final permission = await LocationService().requestAlwaysPermission();

      if (!mounted) return;

      // What actually started, not what the permission enum implies. Asking
      // the enum counted "location is off device-wide" and a background
      // monitor that refused to arm as success, so this stored
      // `locationTrackingEnabled: true` for someone whose position would never
      // be written — and the fan-out then drops that account for having no
      // usable location, with the preference still reading on.
      final result = await LocationService()
          .startLocationTracking(knownPermission: permission);

      if (!mounted) return;

      if (result == LocationTrackingResult.full ||
          result == LocationTrackingResult.foregroundOnly) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
              {
                'notificationPreferences': {
                  'locationTrackingEnabled': true,
                  'locationRadiusKm': 10.0,
                },
              },
              SetOptions(merge: true),
            ).timeout(const Duration(seconds: 10));
          } catch (e) {
            // Timeout or Firestore error — continue onboarding
          }
        }
      }

      _advanceStep();
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  void _handleSkipLocation() => _advanceStep();

  Future<void> _handleSelectRegion() async {
    if (!mounted) return;

    final result = await context.push<Map<String, dynamic>>(Routes.selectRegion);

    if (!mounted) return;

    if (result != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'notificationPreferences': {'regionOfInterest': result}},
            SetOptions(merge: true),
          ).timeout(const Duration(seconds: 10));
        } catch (e) {
          // Timeout or Firestore error — continue onboarding
        }
      }
    }

    _completeOnboarding();
  }

  void _handleSkipRegion() => _completeOnboarding();

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final currentStep = _stepsToShow[_currentStepIndex];

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Close button
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              tooltip: AppLocalizations.of(context).close,
              icon: const Icon(Icons.close),
              onPressed: widget.onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),

          const SizedBox(height: 8),

          // Progress indicator - only shows dots for steps that are actually shown
          if (_stepsToShow.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _stepsToShow.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _buildProgressDot(i),
                ],
              ],
            ),

          const SizedBox(height: 24),

          // Step content
          if (currentStep == _OnboardingStep.notifications) _buildNotificationStep(context),
          if (currentStep == _OnboardingStep.location) _buildLocationStep(context),
          if (currentStep == _OnboardingStep.region) _buildRegionStep(context),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildNotificationStep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.notifications_active,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          l10n.stayInformedTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.stayInformedSubtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _handleEnableNotifications,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2
                    ),
                  )
                : Text(
                    l10n.enableNotifications,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isProcessing ? null : widget.onDismiss,
          child: Text(
            l10n.maybeLater,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationStep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          l10n.enableLocationTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.enableLocationSubtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _handleEnableLocation,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2
                    ),
                  )
                : Text(
                    l10n.enableLocation,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isProcessing ? null : _handleSkipLocation,
          child: Text(
            l10n.skipForNow,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildRegionStep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.map,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          l10n.chooseRegionTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.chooseRegionSubtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _handleSelectRegion,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              l10n.selectRegion,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _handleSkipRegion,
          child: Text(
            l10n.skipForNow,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressDot(int index) {
    final isActive = _currentStepIndex >= index;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
