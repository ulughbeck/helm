import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

import 'setup.dart';

void main() {
  group('Navigation Scenarios', () {
    testWidgets('push and pop sequence works correctly', (tester) async {
      await pumpTestApp(tester);
      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.text('Push Shop'));
      await tester.pumpAndSettle();
      expect(find.text('Shop Query: {}'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('popUntilRoot from a deep stack returns to Home', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      await tester.tap(find.text('Push Laptops'));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsOneWidget);

      final context = tester.element(find.text('Category: laptops'));
      HelmRouter.popUntillRoot(context);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Shop Query: {}'), findsNothing);
      expect(find.text('Category: laptops'), findsNothing);
    });

    testWidgets('replaceAll creates a completely new stack', (tester) async {
      await pumpTestApp(tester);
      final context = tester.element(find.byType(HomeScreen));

      HelmRouter.replaceAll(context, [
        Routes.shop.page(),
        Routes.categories.page(),
        Routes.category.page(pathParams: {'cid': 'replaced'})
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsNothing);
      expect(find.text('Category: replaced'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Shop Query: {}'), findsOneWidget);
    });
  });
}
