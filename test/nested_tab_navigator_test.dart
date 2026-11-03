import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

import 'setup.dart';

void main() {
  group('NestedTabsNavigator in ShopScreen', () {
    testWidgets('switches tab on tap', (tester) async {
      final router = await pumpTestApp(tester, initialRoute: '/shop');
      expect(find.byIcon(Icons.category), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Categories'), findsNothing);
      expect(router.delegate.currentUri.toString(), '/shop/!settings');
    });

    testWidgets('selects the tab from a deep link', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop/!products');
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
      expect(find.text('Products'), findsOneWidget);
    });

    testWidgets('preserves nested stack state when switching tabs', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');

      await tester.tap(find.text('Push Laptops'));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.shopping_basket));
      await tester.pumpAndSettle();
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Category: laptops'), findsNothing);

      await tester.tap(find.byIcon(Icons.category));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('double tap resets the tab to its first page', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      await tester.tap(find.text('Push Laptops'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.category));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsNothing);
      expect(find.text('Categories'), findsOneWidget);
    });
  });

  group('NestedTabsNavigator widget state', () {
    testWidgets('keeps widget state of an inactive tab', (tester) async {
      await pumpTestApp(tester, initialRoute: '/', routes: _TabRoutes.values, guards: const []);

      await tester.tap(find.text('Count: 0'));
      await tester.pump();
      await tester.tap(find.text('Count: 1'));
      await tester.pump();
      expect(find.text('Count: 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('Other page'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(find.text('Count: 2'), findsOneWidget);
    });

    testWidgets('drops widget state when cacheTabState is false', (tester) async {
      _cacheTabs = false;
      addTearDown(() => _cacheTabs = true);
      await pumpTestApp(tester, initialRoute: '/', routes: _TabRoutes.values, guards: const []);

      await tester.tap(find.text('Count: 0'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(find.text('Count: 0'), findsOneWidget);
    });
  });
}

var _cacheTabs = true;

enum _TabRoutes with Routable {
  root,
  counter,
  other;

  @override
  String get path => switch (this) {
        _TabRoutes.root => '/',
        _TabRoutes.counter => '/counter',
        _TabRoutes.other => '/other',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        _TabRoutes.root => NestedTabsNavigator(
            tabs: const [_TabRoutes.counter, _TabRoutes.other],
            cacheTabState: _cacheTabs,
            builder: (context, child, index, onTap) => Scaffold(
              body: child,
              bottomNavigationBar: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: onTap,
                destinations: const [
                  NavigationDestination(label: 'Counter', icon: Icon(Icons.home)),
                  NavigationDestination(label: 'Other', icon: Icon(Icons.settings)),
                ],
              ),
            ),
          ),
        _TabRoutes.counter => const _Counter(),
        _TabRoutes.other => const Text('Other page'),
      };
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () => setState(() => _count++), child: Text('Count: $_count'));
}
