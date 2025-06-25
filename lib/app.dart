import 'package:flutter/material.dart';
import 'package:helm/helm.dart';

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
        Routes.category => '/category/:id',
        Routes.products => '/products',
        Routes.product => '/products/:id',
        Routes.settings => '/settings',
        Routes.notFound => '/404',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        Routes.home => const HomeScreen(),
        Routes.shop => ShopScreen(queryParams: queryParams),
        Routes.categories => const CategoriesScreen(),
        Routes.category => CategoryScreen(categoryId: pathParams['id'] ?? ''),
        Routes.products => const ProductsScreen(),
        Routes.product => ProductScreen(productId: pathParams['id'] ?? ''),
        Routes.settings => const SettingsScreen(),
        Routes.notFound => const NotFoundScreen(),
      };
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final HelmRouter router;

  @override
  void initState() {
    super.initState();
    router = HelmRouter(
      routes: Routes.values,
      guards: [
        // show not found page if no route found
        // (pages) => pages.isEmpty ? [Routes.notFound.page()] : pages,
        // ensure home is always first route
        // (pages) {
        //   if (pages.isNotEmpty && pages.first.name != Routes.home.path) {
        //     return [Routes.home.page(), ...pages];
        //   }
        //   return pages;
        // },
      ],
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(routerConfig: router);
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
              onPressed: () => HelmRouter.push(context, Routes.product, pathParams: {'id': '123'}),
              child: const Text('Push Product 123'),
            ),
            ElevatedButton(
              onPressed: () => HelmRouter.push(context, Routes.product),
              child: const Text('Push Product no params'),
            ),
            ElevatedButton(
              onPressed: () => HelmRouter.replaceAll(context, [
                Routes.shop.page(),
                Routes.category.page(pathParams: {'id': 'replaced'})
              ]),
              child: const Text('Repl'),
            ),
          ]),
        ),
      );
}

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, this.queryParams = const {}});
  final Map<String, String> queryParams;
  @override
  Widget build(BuildContext context) => NestedTabsNavigator(
        tabs: const [Routes.categories, Routes.products, Routes.settings],
        initialTab: Routes.categories,
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
            onPressed: () => HelmRouter.push(context, Routes.category, pathParams: {'id': 'laptops'}),
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
        initialRoute: Routes.products,
        builder: (context, child) => Scaffold(
          appBar: AppBar(title: Text('Category: $categoryId')),
          body: Column(children: [
            ElevatedButton(
              onPressed: () => HelmRouter.push(context, Routes.product, pathParams: {'id': '999'}),
              child: const Text('Push nested Product 999'),
            ),
            ElevatedButton(
                onPressed: () => HelmRouter.push(context, Routes.settings, rootNavigator: true),
                child: const Text('Push Root Settings')),
            Expanded(child: child)
          ]),
        ),
      );
}

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Products')));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')));
}

class ProductScreen extends StatelessWidget {
  const ProductScreen({required this.productId, super.key});
  final String productId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Product: $productId')));
}

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('404 Not Found')));
}
