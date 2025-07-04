import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Logger for router-related messages, enabled by default in debug mode.
abstract class HelmLogger {
  static bool _isEnabled = kDebugMode;

  static void on() => _isEnabled = true;
  static void off() => _isEnabled = false;

  static void msg(String message) {
    if (_isEnabled) log(message, name: 'HelmRouter');
  }

  static void error(String message) => log(message, name: 'HelmRouter');
}
