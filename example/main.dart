import 'dart:async';

import 'package:flutter/material.dart';

import 'example.dart';

void main() {
  runZonedGuarded<void>(
    () => runApp(const App()),
    (error, stackTrace) => print('Top level exception: $error'), // ignore: avoid_print
  );
}
