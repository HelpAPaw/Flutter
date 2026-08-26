import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

class NotificationOnboardingButton extends StatefulWidget {
  final VoidCallback onTap;

  const NotificationOnboardingButton({
    super.key,
    required this.onTap,
  });

  @override
  State<NotificationOnboardingButton> createState() => _NotificationOnboardingButtonState();
}

class _NotificationOnboardingButtonState extends State<NotificationOnboardingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  Timer? _shakeTimer;

  @override
  void initState() {
    super.initState();

    // Set up shake animation controller
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Start periodic shake timer
    _startShakeTimer();
  }

  void _startShakeTimer() {
    // Initial shake after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _shake();
      }
    });

    // Then shake every 10 seconds
    _shakeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _shake();
      }
    });
  }

  void _shake() {
    _shakeController.forward().then((_) {
      if (mounted) {
        _shakeController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Left, not right. At bottom:100/right:16 this sat exactly on top of the
    // map's native zoom controls, and put a second orange circle immediately
    // beside the FAB — two identical-looking primary actions, one of which
    // was blocking a control the user could no longer reach.
    return Positioned(
      bottom: 16,
      left: 16,
      child: Semantics(
        label: AppLocalizations.of(context).completeNotificationSetup,
        button: true,
        enabled: true,
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.rotate(
              angle: sin(_shakeAnimation.value * pi * 4) * 0.15,
              child: child,
            );
          },
          child: Material(
            elevation: 8,
            shape: const CircleBorder(),
            color: Theme.of(context).colorScheme.primary,
            child: InkWell(
              onTap: widget.onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.notifications_active,
                  size: 28,
                  color: Colors.white,  // theme-independent: on the brand orange circle
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
