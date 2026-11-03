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

    testWidgets('push adds missing parent routes', (tester) async {
      final router = await pumpTestApp(tester);
      await tester.tap(find.text('Push Product 123'));
      await tester.pumpAndSettle();

      final routes = router.delegate.currentConfiguration.map((page) => page.route);
      expect(routes, [Routes.home, Routes.products, Routes.product]);
    });

    testWidgets('push without a required path param throws and keeps the state', (tester) async {
      final router = await pumpTestApp(tester);
      final before = router.delegate.currentConfiguration;
      final context = tester.element(find.text('Push Shop'));

      expect(() => HelmRouter.push(context, Routes.product), throwsArgumentError);
      await tester.pumpAndSettle();
      expect(router.delegate.currentConfiguration, before);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('popUntilRoot from a deep stack returns to Home', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      await tester.tap(find.text('Push Laptops'));
      await tester.pumpAndSettle();
      expect(find.text('Category: laptops'), findsOneWidget);

      final context = tester.element(find.text('Category: laptops'));
      HelmRouter.popUntilRoot(context);
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

    testWidgets('changeQueryParams rebuilds pages with new query params', (tester) async {
      await pumpTestApp(tester, initialRoute: '/shop');
      final context = tester.element(find.text('Categories'));

      HelmRouter.changeQueryParams(context, queryParams: {'sort': 'price'});
      await tester.pumpAndSettle();
      expect(find.text('Shop Query: {sort: price}'), findsOneWidget);

      HelmRouter.changeQueryParams(context, queryParams: {'sort': ''});
      await tester.pumpAndSettle();
      expect(find.text('Shop Query: {}'), findsOneWidget);
    });
  });

  group('Refresh', () {
    testWidgets('runs the guards again when the refresh listenable fires', (tester) async {
      final loggedIn = ValueNotifier(true);
      addTearDown(loggedIn.dispose);
      NavigationState authGuard(NavigationState pages) =>
          loggedIn.value || pages.findByRoute(Routes.settings) == null ? pages : [Routes.home.page()];

      final router = await pumpTestApp(tester,
          initialRoute: '/settings', guards: [authGuard, ...defaultGuards], refresh: loggedIn);
      final delegate = router.delegate;
      expect(find.text('Settings'), findsOneWidget);

      var notifications = 0;
      delegate.addListener(() => notifications++);

      // The redirect is applied at once, without a frame that shows the old state.
      loggedIn.value = false;
      expect(delegate.currentConfiguration.map((page) => page.route), [Routes.home]);
      expect(notifications, 1);

      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Home'), findsOneWidget);

      // A refresh that does not change the state does not rebuild.
      loggedIn.value = true;
      expect(notifications, 1);
    });
  });

  group('System back', () {
    testWidgets('pops the nested stack first, then the host page', (tester) async {
      final router = await pumpTestApp(tester, initialRoute: '/category/laptops/!settings/products/1');
      expect(find.text('Product: 1'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Products'), findsOneWidget);
      expect(router.delegate.currentUri.toString(), '/category/laptops/!settings/products');

      // The nested stack has two pages left: settings and products.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/category/laptops/!settings');

      // One nested page left: back pops the category page from the root stack.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Category: laptops'), findsNothing);
    });

    testWidgets('at a tab root leaves the tab host, then lets the app exit', (tester) async {
      final router = await pumpTestApp(tester, initialRoute: '/shop');
      expect(find.text('Categories'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(router.delegate.currentUri.toString(), '/');

      final handled = await router.delegate.popRoute();
      expect(handled, isFalse);
    });

    testWidgets('respects PopScope', (tester) async {
      final router = await pumpTestApp(tester, routes: _PopRoutes.values, guards: const []);
      final context = tester.element(find.text('Root'));
      HelmRouter.push(context, _PopRoutes.locked);
      await tester.pumpAndSettle();
      expect(find.text('Locked'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Locked'), findsOneWidget);
      expect(router.delegate.currentConfiguration.last.route, _PopRoutes.locked);
    });
  });
}

enum _PopRoutes with Routable {
  root,
  locked;

  @override
  String get path => switch (this) {
        _PopRoutes.root => '/',
        _PopRoutes.locked => '/locked',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        _PopRoutes.root => const Scaffold(body: Text('Root')),
        _PopRoutes.locked => const PopScope(canPop: false, child: Scaffold(body: Text('Locked'))),
      };
}
