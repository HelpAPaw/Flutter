import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';

extension NavContext on BuildContext {
  /// Pop if there's something to pop, otherwise navigate to /home.
  /// The router redirect sometimes replaces the entire stack, leaving
  /// a single entry with nothing to pop back to — this falls back to home.
  void popOrHome() {
    if (canPop()) {
      pop();
    } else {
      go(Routes.home);
    }
  }
}
