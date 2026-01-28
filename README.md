# Helm ⎈

A simple lightweight declarative router for Flutter.

## Motivation

Helm’s core idea is state-driven navigation. Instead of calling push/pop and manually managing transitions, you mutate router state (or update the address bar) to describe the outcome you want, and Helm resolves that into a predictable navigation result.

This makes Helm truly declarative router: you don’t “drive the navigator,” you declare the desired state, and the router derives the UI from it.

### Why Helm?

Many router solutions rely on a pre-described route template: you hardcode all possible router states (manually or with code generation) and navigate by matching those templates. That approach is great for traditional server-side rendering, where the server assembles a page from a known set of routes. On the client, it comes with real limitations:

- You can’t realistically predict every navigation state in advance.
- Deep, arbitrary paths become awkward (e.g. /shop/laptops/apple/macbook/1234).
- Nested routing behavior can be hard to reason about.
- Nested state is often lost visually because only the active leaf is rendered—even though deeper state still exists.

### What Helm gives you

- Navigation by state mutation — update state, get navigation.
- Nested navigation — use the built-in model or plug in your own.
- A router state machine driven by state changes — easy breadcrumbs, tabs/sidebars, and route arguments that stay consistent.
- A user-friendly API — mutable vs. immutable state is explicit, and the right mutation methods are easy to discover.
- First-class guards — constrain what states are allowed, rewrite navigation on conditions (e.g. redirect unauthenticated users), and re-validate state on events via subscriptions.
- Declarative dialogs and bottom sheets — dialogs and bottom sheets become part of navigation state (no mixing anonymous imperative dialogs with declarative routing).
- Full navigation tree in URLs and deep links — not just the active route.
- Better debugging — readable state-as-string output makes it easier to inspect and troubleshoot.
<!-- - State history — build a “time machine,” restore where the user left off (e.g. after re-auth), or log for analytics. -->

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
        routerConfig: router,
      );
}
```

Navigate:

```dart
// mutate state however you want
HelmRouter.change(context, (pages) => [ ... ]); 

// helper shortcuts for usual mutations
HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'});
HelmRouter.pop(context);
```

## Defining routes

Routes are simple Dart enums or classes that mix in `Routable` and describe what the route looks like and how to build it:

```dart
mixin Routable {
  String get path; // Must start with '/'
  PageType get pageType; // material, cupertino, dialog, bottomSheet
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams);
}
```

Helm validates every route path as soon as you create the router:

- Paths must begin with `/`.
- Paths cannot be empty.
- Paths cannot be `/-`.
- Paths cannot have whitespaces e.g. `/ some route`.
- Paths cannot have empty segments e.g. `//`.
- Paths must be unique i.e. no two routes can have the same path.
- Each path parameter name (like `{id}`) must be unique i.e. can appear only once across the entire router.

When you call `route.page(...)`, Helm produces a `Page<Object?>` that already carries the right path params, query params, nested children, and transition settings. That saves you from constructing `MaterialPage` or `CupertinoPage` manually and keeps every page consistent with the route definition:

```dart
final page = Routes.product.page(
  pathParams: {'pid': '123'},
  queryParams: {'tab': 'featured'},
  children: currentTabState,
);
```

Because Helm always builds the complete navigation tree for every state change, you can nest child stacks by passing a `NavigationState` via `route.page(...) children`. Helm inserts the required parent routes automatically, keeps their state in sync, and serializes the whole tree back into the URL, so nested tabs/sections stay in sync with deep links.

### Path parameters

Use `{param}` for a single segment:

```dart
Routes.product => '/products/{pid}'
```

Pass values with `pathParams`:

```dart
HelmRouter.push(context, Routes.product, pathParams: {'pid': '123'});
```

If a required param is missing, Helm logs a warning and substitutes `-` in the URL.

### Arbitrary (multi-segment) parameters

Use `{param+}` to accept multiple consecutive segments:

```dart
Routes.product => '/products/{pid+}'
```

This creates a page per segment and allows URLs like:

```shell
/products/123/456/789
```

When pushing an arbitrary route that's already on top of the stack, Helm adds another instance of the same route so the extra segment is represented.

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

### Dialogs and bottom sheets

Set `pageType` to render routes as dialogs or bottom sheets:

```dart
@override
PageType get pageType => PageType.dialog; // or PageType.bottomSheet
```

Helm will build the right modal route for you. That way dialogs and sheets stay part of the navigation stack, and they inherit the same state/query param handling as regular pages.

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

Use basic state mutation method is all you need. All operations work on the current `NavigationState` (i.e. `List<Page<Object?>>`).

`NavigationState` is a linear list of pages that represent the active router tree, including parent routes and any nested stacks produced when you pass `children` to `route.page(...)`. Each `Page` stores its route name (the path), path/query params, and a potential child state, so mutating the list directly describes the full navigation you want Helm to realize. Helpers like `state.findByRoute(...)` or `state.removeByRoute(...)` leverage the `Page.name` field to reference routes even if they have been instantiated multiple times.

```dart
HelmRouter.change(context, (pages) => someNewPages);

HelmRouter.change(context, (pages) => pages..removeWhere((p) => p.name == Routes.product.name)),

HelmRouter.change(context, (pages) => [
    Routes.shop.page(),
    Routes.product.page(pathParams: {'pid': '1'}),
    Routes.product.page(pathParams: {'pid': '2'}),
  ],
),
```

There are shortcuts for common usecases, however they all use `change` internally.

```dart
// Pushes a route (and its parents if needed).
HelmRouter.push(
  context,
  Routes.shop,
  pathParams: {'cid': 'laptops'},
  queryParams: {'tab': 'featured'},
);

// Pop deepest page (nested stacks included).
HelmRouter.pop(context);

// Replace the entire stack.
HelmRouter.replaceAll(context, [Routes.root.page(), Routes.settings.page()]);

// Replace with a single route.
HelmRouter.replaceWithRoute(context, Routes.home);

// Jump back to root.
HelmRouter.popUntilRoot(context);
```

You can truly do anything you want. Just change the state, children, and arguments as you please. Everything is in your hands and just works fine, that's a declarative approach as it should be.

### Accessors

```dart
final uri = HelmRouter.currentUri(context);
final query = HelmRouter.currentQueryParams(context);
final path = HelmRouter.currentPathParams(context);
final state = HelmRouter.state(context);
```

`currentPathParams` uses unique keys per occurrence (e.g. `id-0`, `id-1`) when the same param name appears multiple times in the active stack.

### Stack utilities

`NavigationState` has helpers for common tasks:

```dart
final page = state.findByRoute(Routes.product);
final withoutOne = state.removeByRoute(Routes.product);
final withoutAll = state.removeAllByRoute(Routes.product, recursive: true);
print(state.toPrettyString);
```

## Nested navigation

Helm represents nested stacks by attaching children to a page's route metadata.

### NestedNavigator

Use when a part of the UI needs its own stack (e.g. master-detail):

```dart
NestedNavigator(
  initialRoute: Routes.settings,
  builder: (context, child) => Scaffold(body: child),
)
```

- `initialRoute` or `initialState` sets the first nested stack
- If neither is provided, an empty nested stack is created and managed

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

- Each tab maintains its own stack
- `cacheTabState` (default `true`) preserves stacks when switching tabs
- `clearStackOnDoubleTap` (default `true`) resets the current tab to its root

### Deep linking and nested URLs

Helm uses internal markers to encode nested stacks in URLs (e.g. `/!` to dive and `!/` to rise). You don't usually type these manually; Helm writes them when restoring the current navigation state. For example, if `/shop` is the root and you navigate into a nested product stack, the serialized URL might look like `/shop/!products/123/reviews!/settings`, where each `!/` segment represents diving into a child navigator and the regular `/` boundaries stay compatible with browsers and deep links.

## Guards

Guards transform the stack on every navigation change:

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

Guards run for initial parsing and for all `change` operations.

## Transitions

Set a global default transition delegate or override per route:

```dart
HelmRouter(
  routes: Routes.values,
  defaultTransitionDelegate: const FadeTransitionDelegate(),
)

enum Routes with Routable {
  details;

  @override
  TransitionDelegate<Object?>? get transitionDelegate => const FadeTransitionDelegate();
}
```

`FadeTransitionDelegate` is provided in `lib/src/transitions.dart` as a simple example.

## Logging

```dart
HelmRouter(
  routes: Routes.values,
  enableLogs: true,
  logNavigationStack: true,
)
```

## Example app

See `example/lib/example.dart` for a complete sample covering:

- Guards for 404 and root
- Nested tab navigation
- Nested navigation inside a detail screen
- Dialog and bottom sheet routes
- Arbitrary route parameters
