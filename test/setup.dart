import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

/// Pumps the test app. The initial route goes through the platform, like a deep link.
/// [guards] defaults to [defaultGuards].
Future<HelmRouter> pumpTestApp(
  WidgetTester tester, {
  String initialRoute = '/',
  List<Routable> routes = Routes.values,
  List<NavigationGuard>? guards,
  Listenable? refresh,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async => null);
  tester.platformDispatcher.defaultRouteNameTestValue = initialRoute;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

  final router = HelmRouter(routes: routes, guards: guards ?? defaultGuards, refresh: refresh);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

// --- Test App Setup ---
final defaultGuards = <NavigationGuard>[
  (pages) => pages.isEmpty ? [Routes.notFound.page()] : pages,
  (pages) => pages.isNotEmpty && pages.first.route != Routes.home ? [Routes.home.page(), ...pages] : pages,
];

enum Routes with Routable {
  home,
  shop,
  categories,
  category,
  products,
  product,
  settings,
  notFound;

  @override
  String get path => switch (this) {
        Routes.home => '/',
        Routes.shop => '/shop',
        Routes.categories => '/category',
        Routes.category => '/category/{cid}',
        Routes.products => '/products',
        Routes.product => '/products/{pid}',
        Routes.settings => '/settings',
        Routes.notFound => '/404',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        Routes.home => const HomeScreen(),
        Routes.shop => ShopScreen(queryParams: queryParams),
        Routes.categories => const CategoriesScreen(),
        Routes.category => CategoryScreen(categoryId: pathParams['cid'] ?? ''),
        Routes.products => const ProductsScreen(),
        Routes.product => ProductScreen(productId: pathParams['pid'] ?? ''),
        Routes.settings => const SettingsScreen(),
        Routes.notFound => const NotFoundScreen(),
      };
}

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('404 Not Found')));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Center(
          child: Column(children: [
            ElevatedButton(
              onPressed: () => HelmRouter.push(context, Routes.shop),
              child: const Text('Push Shop'),
            ),
            ElevatedButton(
              onPressed: () => HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'}),
              child: const Text('Push Product 123'),
            ),
          ]),
        ),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')));
}

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, this.queryParams = const {}});
  final Map<String, String> queryParams;
  @override
  Widget build(BuildContext context) => NestedTabsNavigator(
        tabs: const [Routes.categories, Routes.products, Routes.settings],
        builder: (context, child, selectedIndex, onTabPressed) => Scaffold(
          appBar: AppBar(title: Text('Shop Query: $queryParams')),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onTabPressed,
            destinations: const [
              NavigationDestination(label: 'Categories Tab', icon: Icon(Icons.category)),
              NavigationDestination(label: 'Products Tab', icon: Icon(Icons.shopping_basket)),
              NavigationDestination(label: 'Settings Tab', icon: Icon(Icons.settings)),
            ],
          ),
        ),
      );
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: Column(children: [
          ElevatedButton(
            onPressed: () => HelmRouter.push(context, Routes.category, pathParams: {'cid': 'laptops'}),
            child: const Text('Push Laptops'),
          ),
        ]),
      );
}

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({required this.categoryId, super.key});
  final String categoryId;
  @override
  Widget build(BuildContext context) => NestedNavigator(
        initialRoute: Routes.settings,
        builder: (context, child) => Scaffold(
          appBar: AppBar(title: Text('Category: $categoryId')),
          body: Column(children: [
            ElevatedButton(
              onPressed: () => HelmRouter.push(context, Routes.product, pathParams: {'pid': '999'}),
              child: const Text('Push nested Product 999'),
            ),
            ElevatedButton(
              onPressed: () => HelmRouter.push(context, Routes.settings, rootNavigator: true),
              child: const Text('Push Root Settings'),
            ),
            Expanded(child: child),
          ]),
        ),
      );
}

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Products')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'}),
            child: const Text('Push Product 123'),
          ),
        ),
      );
}

class ProductScreen extends StatelessWidget {
  const ProductScreen({required this.productId, super.key});
  final String productId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Product: $productId')));
}
