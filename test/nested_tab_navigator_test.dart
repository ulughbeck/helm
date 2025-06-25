import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup.dart';

void main() {
  group('NestedTabsNavigator in ShopScreen', () {
    testWidgets('switches tab on tap', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      expect(find.byIcon(Icons.category), findsOneWidget);
      await tester.tap(find.byIcon(Icons.shopping_basket));
      await tester.pumpAndSettle();
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Categories'), findsNothing);
    });

    testWidgets('preserves nested stack state when switching tabs', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');

      // In 'Categories' tab, navigate to a category
      await tester.tap(find.text('Push Laptops'));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsOneWidget);

      // Switch to 'Products' tab
      await tester.tap(find.byIcon(Icons.shopping_basket));
      await tester.pumpAndSettle();
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Category: laptops'), findsNothing);

      // Switch back to 'Categories' tab
      await tester.tap(find.byIcon(Icons.category));
      await tester.pumpAndSettle();

      // The nested category screen should be restored
      expect(find.text('Category: laptops'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
    });
  });
}
