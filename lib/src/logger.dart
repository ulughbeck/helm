import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Logger for router-related messages, enabled by default in debug mode.
abstract class HelmLogger {
  static bool _isEnabled = kDebugMode;
  static void on() => _isEnabled = true;
  static void off() => _isEnabled = false;

  static bool logStack = false;
  static void onStack() => logStack = true;
  static void offStack() => logStack = false;

  static void msg(String message) {
    if (_isEnabled) log(message, name: 'helm-router', time: DateTime.now());
  }

  static void error(String message) => log(message, name: 'helm-router', time: DateTime.now());
}
