import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

import 'setup.dart';

void main() {
  group('Initial Link Scenarios', () {
    testWidgets('Initial route "/" is home screen', (tester) async {
      await pumpTestApp(tester);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('Initial route "/shop" shows shop screen', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      expect(find.text('Shop Query: {}'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
    });

    testWidgets('Initial route with params "/category/phones" shows correct screen', (tester) async {
      await pumpTestApp(tester, initialRoute: '/category/phones');
      expect(find.text('Category: phones'), findsOneWidget);
    });

    testWidgets('Initial route with query "/shop?utm=test" passes query params', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop?utm=test');
      expect(find.text('Shop Query: {utm: test}'), findsOneWidget);
    });

    testWidgets('Known route followed by unknown route => render only known route', (tester) async {
      await pumpTestApp(tester, initialRoute: '/settings/unknown');
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Known route followed by many unknown routes => render only known route', (tester) async {
      await pumpTestApp(tester, initialRoute: '/settings/many/unknown/routes');
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Initial route is non-existent => redirect to 404 by guard', (tester) async {
      await pumpTestApp(tester, initialRoute: '/this-route-does-not-exist');
      expect(find.text('404 Not Found'), findsOneWidget);
    });

    testWidgets('Compound initial route is non-existent => redirect to 404 by guard', (tester) async {
      await pumpTestApp(tester, initialRoute: '/some/unknown/route');
      expect(find.text('404 Not Found'), findsOneWidget);
    });

    testWidgets('Unknown route followed by known route => redirect to 404 by guard', (tester) async {
      await pumpTestApp(tester, initialRoute: '/unknown/settings');
      expect(find.text('404 Not Found'), findsOneWidget);
    });

    testWidgets('Unknown routes followed by known route => redirect to 404 by guard', (tester) async {
      await pumpTestApp(tester, initialRoute: '/many/unknown/routes/settings');
      expect(find.text('404 Not Found'), findsOneWidget);
    });

    testWidgets('Initial route is "//" => redirect to Home', (tester) async {
      await pumpTestApp(tester, initialRoute: '//');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('Initial route is "///" => redirect to Home', (tester) async {
      await pumpTestApp(tester, initialRoute: '///');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('Guard adds Home screen if not present', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final delegate = app.routerDelegate as HelmRouterDelegate;

      // Check that the stack is [Home, Shop]
      expect(delegate.currentConfiguration.length, 2);
      expect(delegate.currentConfiguration.first.meta?.route, Routes.home);
      expect(delegate.currentConfiguration.last.meta?.route, Routes.shop);

      // Visually, the shop screen should be on top
      expect(find.text('Shop Query: {}'), findsOneWidget);
    });
  });
}
