# Helm ⎈

A simple lightweight declarative router for Flutter.

## Motivation

Helm’s core idea is state-driven navigation. Instead of calling push/pop and manually managing transitions, you change router state (or update the address bar) to describe the outcome you want, and Helm resolves that into a predictable navigation result.

This makes Helm a truly declarative router: you don’t “drive the navigator,” you declare the desired state, and the router derives the UI from it.

### Why Helm?

Many router solutions rely on a pre-described route template: you define all possible router states up front (manually or with code generation) and navigate by matching those templates. That approach works well when a server assembles a page from a known set of routes. On the client, it has limits:

- You can’t realistically predict every navigation state in advance.
- Deep, arbitrary paths become awkward (e.g. /shop/laptops/apple/macbook/1234).
- Nested routing behavior can be hard to reason about.
- Nested state is often lost visually because only the active leaf is rendered, even though deeper state still exists.

Other routers are state-driven too. Helm makes one choice: the whole navigation tree, with nested stacks, is one immutable value that maps to one URL.

### What Helm gives you

- Navigation by state change: build a new state, get navigation.
- Nested navigation: stacks and tabs are part of the state and are declared on the route.
- A router state machine driven by state changes: easy breadcrumbs, tabs/sidebars, and route arguments that stay consistent.
- Immutable state: pages compare by value, and the helpers return new lists.
- First-class guards: constrain what states are allowed, rewrite navigation on conditions (e.g. redirect unauthenticated users), and re-validate state when a `Listenable` notifies.
- Declarative dialogs and bottom sheets: they become part of navigation state, with no anonymous imperative dialogs mixed into declarative routing.
- Full navigation tree in URLs and deep links, not just the active route.
- Better debugging: readable state-as-string output makes it easier to inspect and troubleshoot.
<!-- - State history: build a “time machine,” restore where the user left off (e.g. after re-auth), or log for analytics. -->

With a declarative router, the only real limit is what you choose to model in state.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  helm: <version>
```

## Get started

Define your routes:

```dart
enum Routes with Routable {
  root,
  home,
  product,
  settings;

  @override
  String get path => switch (this) {
        Routes.root => '/',
        Routes.home => '/home',
        Routes.product => '/products/{pid}',
        Routes.settings => '/settings',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) {
    return switch (this) {
      Routes.root => const RootScreen(),
      Routes.home => const HomeScreen(),
      Routes.product => ProductScreen(id: pathParams['pid'] ?? ''),
      Routes.settings => const SettingsScreen(),
    };
  }
}
```

Set up the router:

```dart
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
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        restorationScopeId: 'app',
        routerConfig: router,
      );
}
```

On the web, Flutter uses hash URLs (`/#/shop`) by default. For path URLs (`/shop`), add `flutter_web_plugins` to your dependencies and call `usePathUrlStrategy()` before `runApp`:

```dart
import 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  usePathUrlStrategy();
  runApp(const App());
}
```

Helm reads the initial URL from Flutter, so it works with both strategies and with apps served from a sub-path (`<base href="/app/">`).

`restorationScopeId` turns on state restoration. Helm stores the full navigation tree in the URL, so when the OS kills and restores the app (for example on Android), every nested stack comes back.

Navigate:

```dart
// build the new state from the current one
HelmRouter.change(context, (pages) => [ ... ]);

// helper shortcuts for usual changes
HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'});
HelmRouter.pop(context);
```

## Defining routes

Routes are simple Dart enums or classes that mix in `Routable`. They describe what the route looks like and how to build it:

```dart
mixin Routable {
  String get path; // Must start with '/'
  PageType get pageType; // material, cupertino, dialog, bottomSheet
  TransitionDelegate<Object?>? get transitionDelegate; // optional per-route transition
  Page<Object?>? buildPage(LocalKey key, HelmPage page, Widget child); // optional custom page
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams);
}
```

Helm validates every route path as soon as you create the router (in debug mode):

- The route list cannot be empty.
- Paths must begin with `/`.
- Paths cannot be empty.
- Paths cannot be `/-`.
- Paths cannot have whitespace e.g. `/ some route`.
- Paths cannot have empty segments e.g. `//`.
- Paths cannot contain `!` or `~`. The URL grammar uses them.
- Paths must be unique i.e. no two routes can have the same path.

When you call `route.page(...)`, Helm creates a `HelmPage`. A `HelmPage` is an immutable value with these fields:

- `route`: the `Routable` of the page.
- `pathParams` and `queryParams`: unmodifiable maps.
- `children`: the nested stack of the page. `null` means the page has no nested stack yet.
- `name`: the route path with the path params filled in, e.g. `/products/123`.

Two pages with the same route, params, and children are equal. Use `copyWith(pathParams:, queryParams:)` and `withChildren(...)` to get changed copies.

```dart
final page = Routes.product.page(
  pathParams: {'pid': '123'},
  queryParams: {'tab': 'featured'},
);
```

`page(...)` also takes `children` to set the nested stack directly.

Helm builds the complete navigation tree for every state change. Helm adds the required parent routes automatically, and it writes the whole tree back into the URL, so nested tabs and sections stay in sync with deep links.

### Path parameters

Use `{param}` for a single segment:

```dart
Routes.product => '/products/{pid}'
```

Pass values with `pathParams`:

```dart
HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'});
```

Helm percent-encodes path param values in URLs and decodes them when it parses a URL. A value like `a b/c!` is safe. The value `~` is reserved by the URL grammar: do not use it.

Every param in the path needs a non-empty value. `Routes.product.page()` or `HelmRouter.push(context, Routes.product)` without `pid` throws an `ArgumentError`, because the page would have no valid URL. The state does not change. URLs from outside cannot cause this: a URL that does not match a route gives an empty state, and your guard can show a 404 page.

### Several parameters in one segment

A segment can hold several params with text around them:

```dart
Routes.location => '/map/@{lat},{lng},{zoom}z'
```

```dart
HelmRouter.push(context, Routes.location, pathParams: {'lat': '41.31', 'lng': '69.24', 'zoom': '12'});
// URL: /map/@41.31,69.24,12z
```

Rules:

- The text can use letters, digits and `-._~$&'()*+,;=:@`.
- Two params need a separator with at least one of `$&+,;=:@` between them, for example `{a},{b}`. `{a}-{b}` is not allowed, because a value can contain `-`. Helm encodes these separator characters inside values, so `,` in a value becomes `%2C`.
- `{param+}` must be a whole segment.
- On the same position, a static segment wins over a segment with params and text, and that segment wins over a plain `{param}`.

Helm throws an `ArgumentError` when it creates the router with a template that breaks these rules.

### Arbitrary (multi-segment) parameters

Use `{param+}` to accept multiple consecutive segments:

```dart
Routes.product => '/products/{pid+}'
```

This creates a page per segment and allows URLs like:

```shell
/products/123/456/789
```

When you push an arbitrary route that is already on top of the stack, Helm adds another instance of the same route so the extra segment is represented.

To put a different route in the same stack after an arbitrary sequence, Helm writes a `~` segment between them:

```shell
/products/1/2/~/settings
```

### Query parameters

Query params are merged with the current state when pushing:

```dart
HelmRouter.push(context, Routes.shop, queryParams: {'sort': 'price'});
```

Update query params across the whole stack with:

```dart
HelmRouter.changeQueryParams(context, queryParams: {'sort': 'rating', 'q': ''});
```

Passing an empty string removes the key.

Query params in Helm are global router state, not page-local state. Helm merges query params across the whole navigation tree and restores them as a single query string on the URL. If multiple pages set the same key, the later page in the restored navigation tree wins. Use query params for app-wide shareable state such as filters, search terms, campaign tags, and view mode. Use path params or page state for route-local state.

For example, if two pages contribute `tab`, only one `tab` value can exist in the final URL:

```dart
// final restored URL can only contain one `tab` query key
HelmRouter.push(context, Routes.shop, queryParams: {'tab': 'featured'});
HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'}, queryParams: {'tab': 'details'});
```

In that case the later page's `tab=details` wins in the restored URL.

### URL grammar

Helm writes the full navigation tree into the path with a small URL grammar:

- Normal path segments represent route paths.
- `/!` means "dive" into the nested stack of the previous page.
- `!/` means "rise" back to the parent stack.
- A `~` segment ends an arbitrary `{param+}` sequence when another route follows in the same stack.

Examples:

```text
/shop/!category
/category/laptops/!settings
/products/123/456/789
/products/1/2/~/settings
/shop/!products/123!/settings
/map/@41.31,69.24,12z
```

The last example reads: the `/shop` page has a nested stack with `/products` and `/products/123`. After the rise (`!/`), `/settings` is the next page in the root stack.

A URL without a dive gives a page without children. The nested navigator of that page then adds its first page, and the URL `/shop` becomes `/shop/!category`. A dive in a URL sets the children, so the nested navigator does not add its first page.

Path param values are percent-encoded, so a `/` or `!` inside a value never breaks the grammar. The exact value `~` is reserved. Helm parses malformed URLs with best-effort behavior (for example, it ignores a stray `~` or a rise from the root stack) and logs a warning. It does not throw and does not hang.

### Dialogs and bottom sheets

Set `pageType` to render routes as dialogs or bottom sheets:

```dart
@override
PageType get pageType => PageType.dialog; // or PageType.bottomSheet
```

Helm builds the right modal route for you. Dialogs and sheets stay part of the navigation stack, and they inherit the same state and query param handling as regular pages.

### Example

```dart
enum Routes with Routable {
  root,
  home,
  shop,
  categories,
  category,
  products,
  product,
  settings,
  someDialog,
  someSheet,
  notFound;

  @override
  String get path => switch (this) {
        Routes.root => '/',
        Routes.home => '/home',
        Routes.shop => '/shop',
        Routes.categories => '/category',
        Routes.category => '/category/{cid}',
        Routes.products => '/products',
        Routes.product => '/products/{pid+}',
        Routes.settings => '/settings',
        Routes.someDialog => '/dialog',
        Routes.someSheet => '/sheet',
        Routes.notFound => '/404',
      };

  @override
  PageType get pageType => switch (this) {
        Routes.someDialog => PageType.dialog,
        Routes.someSheet => PageType.bottomSheet,
        _ => PageType.material, // all other routes are material pages
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        Routes.root => const RootScreen(),
        Routes.home => const HomeScreen(),
        Routes.shop => ShopScreen(queryParams: queryParams),
        Routes.categories => const CategoriesScreen(),
        Routes.category => CategoryScreen(categoryId: pathParams['cid'] ?? ''),
        Routes.products => const ProductsScreen(),
        Routes.product => ProductScreen(productId: pathParams['pid'] ?? ''),
        Routes.settings => const SettingsScreen(),
        Routes.someDialog => const SomeDialog(),
        Routes.someSheet => const SomeSheet(),
        Routes.notFound => const NotFoundScreen(),
      };
}
```

## Navigation API

Changing state is all you need. All operations work on the current `NavigationState`, which is a `List<HelmPage>`.

`NavigationState` is a list of pages that represent the active router tree. A page with `children` hosts a nested stack, so the list is a tree. Each `HelmPage` stores its route, its `name` (the filled path), its path and query params, and its optional child stack. Helpers like `state.findByRoute(...)` or `state.removeByRoute(...)` use the route, so they work even if a route appears multiple times.

State is immutable. Return a new list from `change` and do not edit pages in place:

```dart
HelmRouter.change(context, (pages) => someNewPages);

HelmRouter.change(context, (pages) => pages.removeAllByRoute(Routes.product));

HelmRouter.change(context, (pages) => [
  Routes.shop.page(),
  Routes.product.page(pathParams: {'pid': '1'}),
  Routes.product.page(pathParams: {'pid': '2'}),
]);
```

There are shortcuts for common use cases. They all use `change` internally.

```dart
// Pushes a route (and its parents if needed).
HelmRouter.push(
  context,
  Routes.category,
  pathParams: {'cid': 'laptops'},
  queryParams: {'tab': 'featured'},
);

// Pops like the system back button.
final popped = await HelmRouter.pop(context);

// Replace the entire stack.
HelmRouter.replaceAll(context, [Routes.root.page(), Routes.settings.page()]);

// Replace with a single route.
HelmRouter.replaceWithRoute(context, Routes.home);

// Jump back to root.
HelmRouter.popUntilRoot(context);
```

`push` adds the new page to the deepest active stack. Set `rootNavigator: true` to add it to the root stack, for example to show a dialog above all tabs.

`push` adds parent routes only when the target stack does not already have them. For `/products/{pid}`, Helm adds `/products` first when it is missing. Parent pages get their param values by position in the path.

### Pop and system back

`HelmRouter.pop(context)` returns a `Future<bool>` and behaves like the system back button. It calls `maybePop` on the deepest active navigator. This means:

- `PopScope` can block or handle the pop.
- Dialogs and bottom sheets close first.
- A nested navigator with one page passes the pop to its parent. At the root of a tab, back leaves the tab host. At the root of the app, the app can exit.
- The result is `false` when nothing was popped.

### Accessors

```dart
final uri = HelmRouter.currentUri(context);
final query = HelmRouter.currentQueryParams(context);
final path = HelmRouter.currentPathParams(context);
final state = HelmRouter.state(context);
```

`currentPathParams` uses one key per occurrence: `name-index`, in stack order, nested pages included. For example `pid-0`, `pid-1`.

### Stack utilities

`NavigationState` has helpers for common tasks:

```dart
final page = state.findByRoute(Routes.product); // HelmPage?, deepest and last first
final withoutOne = state.removeByRoute(Routes.product);
final withoutAll = state.removeAllByRoute(Routes.product, recursive: true);
print(state.toPrettyString);
```

To change nested stacks, use these helpers. They return new lists and keep unchanged parts as they are:

```dart
// Change every page, nested pages first. Return null to remove a page.
final mapped = state.mapPages(
  (page) => page.route == Routes.product ? page.copyWith(queryParams: {'tab': 'info'}) : page,
);

// Change the deepest active stack.
final pushed = state.updateDeepest((stack) => [...stack, Routes.settings.page()]);

// Change the stack of the page at a given position.
// The path lists the host page indices from the root stack. [] is the root stack.
final updated = state.updateAt([0], (stack) => [...stack, Routes.products.page()]);

// Indices of the host pages that lead to the deepest active stack.
final path = state.deepestPath;
```

`removeAllByRoute` removes from the deepest active stack by default. With `recursive: true` it removes from every stack.

## Nested navigation

Helm represents a nested stack as the `children` of a page. The screen of the page shows it with `NestedNavigator` or `NestedTabsNavigator`. When the nested stack is empty, the widget adds its first page after the first frame. It replaces the current browser history entry, so this adds no extra entry.

### NestedNavigator

Use when a part of the UI needs its own stack (e.g. master-detail):

```dart
NestedNavigator(
  initialRoute: Routes.settings,
  builder: (context, child) => Scaffold(body: child),
)
```

- `initialRoute` or `initialState` sets the first nested stack. Give only one of them.
- Without both, the nested stack stays empty until you push into it.
- `observers` and `transitionDelegate` are optional.

### NestedTabsNavigator

Use for bottom navigation bars or tabbed layouts with independent stacks:

```dart
NestedTabsNavigator(
  tabs: const [Routes.home, Routes.settings],
  builder: (context, child, index, onTap) => Scaffold(
    body: child,
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: onTap,
      destinations: const [
        NavigationDestination(label: 'Home', icon: Icon(Icons.home)),
        NavigationDestination(label: 'Settings', icon: Icon(Icons.settings)),
      ],
    ),
  ),
)
```

Behavior:

- Each tab maintains its own stack. The first page of the nested stack selects the tab.
- `initialTab` or `initialState` sets the first stack. Without both, the first tab is used.
- Visited tabs stay mounted in an `IndexedStack`, so widget state such as scroll position and form input is preserved.
- `cacheTabState` (default `true`) keeps the stack and widget state of a tab when you select another tab. With `false`, Helm drops them.
- `clearStackOnDoubleTap` (default `true`) resets the selected tab to its root page when you select it again.
- `observersBuilder: (tabIndex) => [...]` gives the observers for the navigator of each tab. One observer can belong to only one `Navigator`, so return new observers for each call.

### Deep linking and nested URLs

Helm uses markers to encode nested stacks in URLs (`/!` to dive and `!/` to rise). You don't usually type these. Helm writes them when it restores the current navigation state. For example, if `/shop` is the root and you navigate into a nested products stack, the URL looks like `/shop/!products/123!/settings`. The nested stack is inside `!` markers, and the regular `/` boundaries stay compatible with browsers and deep links.

On the web, Helm replaces the browser history entry when it only normalizes a URL. This applies to a URL that the browser just reported (for example, after a guard redirect) and to the first page that a nested navigator adds. This adds no extra history entries.

## Guards

Guards take the stack and return a stack. They run on every navigation change:

```dart
HelmRouter(
  routes: Routes.values,
  guards: [
    (pages) => pages.isEmpty ? [Routes.notFound.page()] : pages,
    (pages) => pages.isNotEmpty && pages.first.name != Routes.root.path
        ? [Routes.root.page(), ...pages]
        : pages,
  ],
)
```

Guards run for initial parsing and for all `change` operations. Use `page.route` to compare routes and `page.name` to compare filled paths.

To run guards again on an event, pass a `Listenable`. Guards run each time it notifies:

```dart
HelmRouter(
  routes: Routes.values,
  refresh: authNotifier,
  guards: [...],
)
```

## Transitions

Set a global default transition delegate or override per route. Both take a Flutter `TransitionDelegate`:

```dart
HelmRouter(
  routes: Routes.values,
  defaultTransitionDelegate: const NoAnimationTransitionDelegate(),
)

enum Routes with Routable {
  details;

  @override
  TransitionDelegate<Object?>? get transitionDelegate => const NoAnimationTransitionDelegate();
}
```

The example app has `NoAnimationTransitionDelegate`. To change the animation of all pages, use `ThemeData.pageTransitionsTheme`.

A transition delegate decides only whether a page change animates. To change how one route animates, return your own `Page` from `buildPage`. Return null to use `pageType`:

```dart
enum Routes with Routable {
  home,
  settings;

  @override
  Page<Object?>? buildPage(LocalKey key, HelmPage page, Widget child) => switch (this) {
        Routes.settings => FadePage(key: key, name: page.name, arguments: page, child: child),
        _ => null,
      };
}

class FadePage extends Page<Object?> {
  const FadePage({required this.child, super.key, super.name, super.arguments});

  final Widget child;

  // The builder reads the current settings, so an updated page shows its new child.
  @override
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
        settings: this,
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: animation,
          child: (ModalRoute.of(context)!.settings as FadePage).child,
        ),
      );
}
```

## Logging

```dart
HelmRouter(
  routes: Routes.values,
  enableLogs: true,
  logNavigationStack: true,
)
```

`enableLogs` controls all Helm log output, warnings included. It is `true` in debug mode by default. Each router has its own log settings.

## Example app

See `example/lib/main.dart` for a complete sample covering:

- Guards for 404 and root
- Nested tab navigation
- Nested navigation inside a detail screen
- Dialog and bottom sheet routes
- Arbitrary route parameters

### Browser test

`example/integration_test/browser_test.dart` runs the example app in headless Chrome. It checks the address bar, history entries, back and forward, and an app served from a sub-path. It needs a `chromedriver` with the same major version as Chrome:

```sh
cd example
CHROMEDRIVER=/path/to/chromedriver tool/browser_test.sh
```
