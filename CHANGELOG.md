# Changelog

## 0.0.3

- **Added**: `Routable.buildPage` returns a custom `Page` for a route, for example for a custom transition. Return null to use `pageType`.
- **Breaking**: Helm uses `package:material_ui` and `package:cupertino_ui` instead of the deprecated `package:flutter/material.dart` and `package:flutter/cupertino.dart`. Its Material pages, dialogs, and bottom sheets now read the `material_ui` theme of the app. Requires Dart 3.13 and Flutter 3.47.

## 0.0.2

- **Breaking**: `NavigationState` is an immutable `List<HelmPage>` with value equality. `route.page()` returns `HelmPage` and has no `key`. `$RouteMeta`, `page.meta`, `$DialogPage`, and `$BottomSheetPage` are removed. `HelmRouter.pop` returns `Future<bool>` and acts like system back. `NestedTabsNavigator.observers` is now `observersBuilder`. A missing or empty path param throws instead of writing `-`. Nested navigators outside a Helm page throw. Route paths cannot contain `!` or `~`. Helm no longer sets the web URL strategy: call `usePathUrlStrategy()` yourself. `HelmRouteParser`, `HelmRouteInformationParser`, and `FadeTransitionDelegate` are no longer exported. The delegate methods `prepareNestedNavigator`, `setInitialNestedRoute`, and `replaceNestedStack` are removed: use `HelmRouter.change` with `updateAt` or `mapPages`. `currentUri` is read-only. `Routable.build` is removed and `restorePathForRoute` is now `restorePath`. A no-animation delegate is in the example app.
- **Changed**: param values are percent-encoded in URLs, and a `{name+}` sequence ends with a `~` segment. `push` adds only missing parents, with params by position. Log settings belong to each router. The unique param name rule is removed.
- **Added**: several params in one segment (`/map/@{lat},{lng},{zoom}z`). `mapPages`, `updateAt`, `updateDeepest`, `deepestPath`, and `HelmRouter.delegate`. Visited tabs keep their state. Normalized URLs (initial link, guard redirect, nested fill) replace the history entry. State restoration with `restorationScopeId`.
- **Fixed**: the initial route under a `<base href>` sub-path, a parser hang on malformed URLs, system back emptying a nested stack or sticking at a tab root, `PopScope` being ignored, stale dialog and bottom sheet content, and `refresh` guards running one frame late.
- **Dependencies**: removed `flutter_web_plugins` and `web`.
- **Tests**: 66 unit tests, plus a browser test for history, back and forward, and `<base href>`.

## 0.0.1

- Initial release.
