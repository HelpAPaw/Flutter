import 'package:flutter/material.dart';

enum HomeRouteAspects {
  homeRouteNavigationAspect,
  homeRouteTileAspect,
}

class HomeRouteModel extends InheritedModel<HomeRouteAspects> {
  final int? homeRouteNavigationAspect;
  final int? homeRouteTileAspect;

  const HomeRouteModel({
    super.key,
    this.homeRouteNavigationAspect,
    this.homeRouteTileAspect,
    required super.child,
  });

  // Home Route Model Update Notifier
  @override
  bool updateShouldNotify(HomeRouteModel oldWidget) {
    return homeRouteNavigationAspect != oldWidget.homeRouteNavigationAspect ||
        homeRouteTileAspect != oldWidget.homeRouteTileAspect;
  }

  // Home Route Model Dependent Update Notifier
  @override
  bool updateShouldNotifyDependent(
      HomeRouteModel oldWidget, Set<HomeRouteAspects> dependencies) {
    if (homeRouteNavigationAspect != oldWidget.homeRouteNavigationAspect &&
        dependencies.contains(HomeRouteAspects.homeRouteNavigationAspect)) {
      return true;
    }
    if (homeRouteTileAspect != oldWidget.homeRouteTileAspect &&
        dependencies.contains(HomeRouteAspects.homeRouteTileAspect)) {
      return true;
    }
    return false;
  }
}
