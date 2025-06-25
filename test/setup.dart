import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/app.dart';
import 'package:helm/helm.dart';

export 'package:helm/app.dart';

// --- Test App Setup ---
const routes = Routes.values;
final guards = <NavigationGuard>[
  (pages) => pages.isEmpty ? [Routes.notFound.page()] : pages,
  (pages) {
    if (pages.isNotEmpty && pages.first.name != Routes.home.path) {
      return [Routes.home.page(), ...pages];
    }
    return pages;
  },
];

Future<void> pumpTestApp(WidgetTester tester, {String initialRoute = '/', bool includeGuards = true}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  final router = HelmRouter(routes: routes, guards: includeGuards ? guards : []);
  final initialUri = Uri.parse(initialRoute);
  await tester.pumpWidget(MaterialApp.router(
    routerDelegate: router.routerDelegate,
    routeInformationParser: router.routeInformationParser,
    routeInformationProvider: PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: initialUri),
    ),
  ));
  await tester.pumpAndSettle();
}
