import 'package:flutter/widgets.dart';

Uri getInitialUriImpl(String Function(String) normalize) {
  final initialPlatformRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  try {
    return Uri.parse(normalize(initialPlatformRoute));
  } catch (_) {
    return Uri(path: '/');
  }
}
