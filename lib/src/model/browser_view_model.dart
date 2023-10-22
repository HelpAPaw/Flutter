import 'package:flutter/material.dart';

enum BrowserViewAspects {
  browserLaunchedAspect,
}

class BrowserViewModel extends InheritedModel<BrowserViewAspects> {
  final Future<void>? browserLaunchedAspect;

  const BrowserViewModel({
    super.key,
    this.browserLaunchedAspect,
    required super.child,
  });

  // Browser View Model Update Notifier
  @override
  bool updateShouldNotify(BrowserViewModel oldWidget) {
    return browserLaunchedAspect != oldWidget.browserLaunchedAspect;
  }

  // Browser View Model Dependent Update Notifier
  @override
  bool updateShouldNotifyDependent(
      BrowserViewModel oldWidget, Set<BrowserViewAspects> dependencies) {
    if (browserLaunchedAspect != oldWidget.browserLaunchedAspect &&
        dependencies.contains(BrowserViewAspects.browserLaunchedAspect)) {
      return true;
    }
    return false;
  }
}
