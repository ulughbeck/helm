import 'package:flutter/material.dart';
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

  group('NestedNavigator configuration', () {
    testWidgets('passes observers to nested navigator', (tester) async {
      final observer = _CountingNavigatorObserver();
      _nestedObserver = observer;

      final router = HelmRouter(routes: _ObserverRoutes.values);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(observer.pushCount, 1);

      await tester.tap(find.text('Push nested detail'));
      await tester.pumpAndSettle();

      expect(find.text('Nested detail'), findsOneWidget);
      expect(observer.pushCount, 2);
    });

    testWidgets('accepts custom transition delegate for nested navigator', (tester) async {
      final observer = _CountingNavigatorObserver();
      final transitionDelegate = _CountingTransitionDelegate();
      _nestedObserver = observer;
      _nestedTransitionDelegate = transitionDelegate;

      final router = HelmRouter(routes: _ObserverRoutes.values);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Push nested detail'));
      await tester.pumpAndSettle();

      expect(find.text('Nested detail'), findsOneWidget);
      expect(observer.pushCount, 2);
      expect(transitionDelegate.resolveCount, greaterThan(0));

      _nestedTransitionDelegate = null;
    });
  });
}

late _CountingNavigatorObserver _nestedObserver;
TransitionDelegate<Object?>? _nestedTransitionDelegate;

enum _ObserverRoutes with Routable {
  root,
  nestedHome,
  nestedDetail;

  @override
  String get path => switch (this) {
        _ObserverRoutes.root => '/',
        _ObserverRoutes.nestedHome => '/nested-home',
        _ObserverRoutes.nestedDetail => '/nested-detail',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        _ObserverRoutes.root => NestedNavigator(
            initialRoute: _ObserverRoutes.nestedHome,
            observers: [_nestedObserver],
            transitionDelegate: _nestedTransitionDelegate,
            builder: (context, child) => Scaffold(body: child),
          ),
        _ObserverRoutes.nestedHome => Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => HelmRouter.push(context, _ObserverRoutes.nestedDetail),
                  child: const Text('Push nested detail'),
                ),
              ),
            ),
          ),
        _ObserverRoutes.nestedDetail => const Scaffold(body: Center(child: Text('Nested detail'))),
      };
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class _CountingTransitionDelegate extends TransitionDelegate<Object?> {
  int resolveCount = 0;
  final TransitionDelegate<Object?> _delegate = const DefaultTransitionDelegate<Object?>();

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord> locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>> pageRouteToPagelessRoutes,
  }) {
    resolveCount++;
    return _delegate.resolve(
      newPageRouteHistory: newPageRouteHistory,
      locationToExitingPageRoute: locationToExitingPageRoute,
      pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
    );
  }
}
