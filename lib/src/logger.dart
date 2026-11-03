import 'dart:developer';

import 'state.dart';

/// Writes router messages to the developer log. Each [HelmRouter] has its own logger.
class HelmLogger {
  const HelmLogger({this.enabled = false, this.logStack = false});

  final bool enabled;

  /// Also logs the full navigation stack after each change.
  final bool logStack;

  void msg(String message) {
    if (enabled) log(message, name: 'helm-router', time: DateTime.now());
  }

  void warn(String message) => msg('Warning: $message');

  void stack(NavigationState pages) {
    if (logStack) msg(pages.toPrettyString);
  }
}
