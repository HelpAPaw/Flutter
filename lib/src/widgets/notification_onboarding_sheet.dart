import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/app_preferences_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

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
  int _currentStep = 0; // 0: notifications, 1: location, 2: region
  bool _isProcessing = false;

  Future<void> _handleEnableNotifications() async {
    setState(() => _isProcessing = true);

    try {
      // Request notification permission
      final notificationGranted = await NotificationService().requestNotificationPermission();

      if (!mounted) return;

      if (notificationGranted) {
        // Save notification preference to Firestore
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {
              'notificationPreferences': {
                'enabled': true,
              },
            },
            SetOptions(merge: true),
          );
        }
      }

      // Move to location step (wait for user to click button)
      setState(() {
        _currentStep = 1;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleEnableLocation() async {
    setState(() => _isProcessing = true);

    try {
      final locationGranted = await LocationService().requestAlwaysPermission();

      if (!mounted) return;

      final granted = locationGranted != null &&
          locationGranted.toString() != 'LocationPermission.denied' &&
          locationGranted.toString() != 'LocationPermission.deniedForever';

      if (granted) {
        // Enable location tracking
        await LocationService().startLocationTracking();

        // Save location preference to Firestore
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {
              'notificationPreferences': {
                'locationTrackingEnabled': true,
                'locationRadiusKm': 10.0,
              },
            },
            SetOptions(merge: true),
          );
        }
      }

      // Move to region selection step
      setState(() {
        _currentStep = 2;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleSkipLocation() async {
    // Skip location, move to region selection
    setState(() => _currentStep = 2);
  }

  Future<void> _handleSelectRegion() async {
    if (!mounted) return;

    // Navigate to region selection
    final result = await context.push<Map<String, dynamic>>('/select-region');

    if (!mounted) return;

    if (result != null) {
      // Save region to Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'notificationPreferences': {
              'regionOfInterest': result,
            },
          },
          SetOptions(merge: true),
        );
      }
    }

    // Mark onboarding as complete
    await AppPreferencesService().setOnboardingCompleted(true);
    widget.onComplete();
  }

  Future<void> _handleSkipRegion() async {
    // Mark onboarding as complete without region
    await AppPreferencesService().setOnboardingCompleted(true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
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
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Close button
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),

          const SizedBox(height: 8),

          // Progress indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildProgressDot(0),
              const SizedBox(width: 8),
              _buildProgressDot(1),
              const SizedBox(width: 8),
              _buildProgressDot(2),
            ],
          ),

          const SizedBox(height: 24),

          // Step-specific content
          if (_currentStep == 0) _buildNotificationStep(context),
          if (_currentStep == 1) _buildLocationStep(context),
          if (_currentStep == 2) _buildRegionStep(context),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildNotificationStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.notifications_active,
          size: 64,
          color: Colors.orange[600],
        ),
        const SizedBox(height: 24),
        Text(
          'Stay Informed About Animals in Need',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Get notified when signals appear near you or in your area of interest.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _handleEnableNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
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
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Enable Notifications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isProcessing ? null : widget.onDismiss,
          child: Text(
            'Maybe Later',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on,
          size: 64,
          color: Colors.orange[600],
        ),
        const SizedBox(height: 24),
        Text(
          'Enable Location Tracking',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Get alerts for animals in need within 10km of your location.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _handleEnableLocation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
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
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Enable Location',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isProcessing ? null : _handleSkipLocation,
          child: Text(
            'Skip for Now',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegionStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.map,
          size: 64,
          color: Colors.orange[600],
        ),
        const SizedBox(height: 24),
        Text(
          'Choose Your Region of Interest',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Select a specific area you care about and get notified of signals there.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _handleSelectRegion,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Select Region',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _handleSkipRegion,
          child: Text(
            'Skip for Now',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressDot(int step) {
    final isActive = _currentStep >= step;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.orange : Colors.grey[300],
      ),
    );
  }
}
