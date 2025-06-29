import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

import 'setup.dart';

void main() {
  group('NestedNavigator in CategoryScreen', () {
    testWidgets('initializes with its own nested route', (tester) async {
      await pumpTestApp(tester, initialRoute: '/category/laptops');
      expect(find.text('Category: laptops'), findsOneWidget);
      // The nested navigator should have initialized its child route (SettingsScreen)
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('can push and pop within the nested navigator', (tester) async {
      await pumpTestApp(tester, initialRoute: '/category/laptops');
      await tester.tap(find.text('Push nested Product 999'));
      await tester.pumpAndSettle();

      expect(find.text('Product: 999'), findsOneWidget);
      expect(find.text('Products'), findsNothing);

      final context = tester.element(find.text('Product: 999'));
      HelmRouter.pop(context);
      await tester.pumpAndSettle();

      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Product: 999'), findsNothing);
    });

    testWidgets('can push to root navigator from deeply nested context', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      await tester.tap(find.text('Push Laptops'));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsOneWidget);

      await tester.tap(find.text('Push Root Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Shop Query: {}'), findsNothing);
      expect(find.text('Category: laptops'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
