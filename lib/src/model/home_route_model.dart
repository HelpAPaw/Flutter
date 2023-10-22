import 'package:flutter/material.dart';

enum HomeRouteAspects {
  homeRouteTileAspect,
}

class HomeRouteModel extends InheritedModel<HomeRouteAspects> {
  final int? homeRouteTileAspect;

  const HomeRouteModel({
    super.key,
    this.homeRouteTileAspect,
    required super.child,
  });

  // Home Route Model Update Notifier
  @override
  bool updateShouldNotify(HomeRouteModel oldWidget) {
    return homeRouteTileAspect != oldWidget.homeRouteTileAspect;
  }

  // Home Route Model Dependent Update Notifier
  @override
  bool updateShouldNotifyDependent(
      HomeRouteModel oldWidget, Set<HomeRouteAspects> dependencies) {
    if (homeRouteTileAspect != oldWidget.homeRouteTileAspect &&
        dependencies.contains(HomeRouteAspects.homeRouteTileAspect)) {
      return true;
    }
    return false;
  }
}
