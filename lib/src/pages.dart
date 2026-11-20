// Internal: converts the navigation state into Flutter pages. Not exported.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'delegate.dart';
import 'route.dart';
import 'state.dart';

/// Location of a stack in the navigation tree: the indices of its host pages from the root stack.
///
/// Null marks a detached stack, for example the cached stack of an inactive tab.
typedef StackPath = List<int>;

/// Gives a page's content access to its [HelmPage] and to the location of the page's nested stack.
class HelmPageScope extends InheritedWidget {
  const HelmPageScope({required this.page, required this.childrenPath, required super.child, super.key});

  final HelmPage page;

  /// Location of [HelmPage.children]. Null when the page is detached.
  final StackPath? childrenPath;

  static HelmPageScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HelmPageScope>();

  @override
  bool updateShouldNotify(HelmPageScope oldWidget) =>
      page != oldWidget.page || !listEquals(childrenPath, oldWidget.childrenPath);
}

/// A nested navigator widget that system back can pop.
abstract interface class NestedHost {
  BuildContext get context;

  /// Location of the stack that this host shows. Null when detached.
  StackPath? get stackPath;

  NavigatorState? get navigator;
}

final _hosts = Expando<Set<NestedHost>>();

/// Nested navigators that are mounted under [delegate].
Set<NestedHost> nestedHosts(HelmRouterDelegate delegate) => _hosts[delegate] ??= <NestedHost>{};

/// Keys for the pages of one stack: route, name, and occurrence of that name in the stack.
///
/// Keys depend only on the state, so a page keeps its route and widget state when the state is
/// parsed again from a URL.
List<LocalKey> pageKeys(NavigationState stack) {
  final counts = <(Routable, String), int>{};
  return [
    for (final page in stack)
      ValueKey((page.route, page.name, counts.update((page.route, page.name), (n) => n + 1, ifAbsent: () => 0))),
  ];
}

typedef _CachedPage = ({LocalKey key, StackPath? path, Page<Object?> page});
final _pageCache = Expando<_CachedPage>();

/// Converts [stack] into Flutter pages. [path] is the location of [stack].
///
/// A page that did not change is reused, so its content does not rebuild.
List<Page<Object?>> buildPages(NavigationState stack, StackPath? path) {
  final keys = pageKeys(stack);
  return [
    for (var i = 0; i < stack.length; i++) _flutterPage(stack[i], keys[i], path == null ? null : [...path, i]),
  ];
}

Page<Object?> _flutterPage(HelmPage page, LocalKey key, StackPath? childrenPath) {
  final cached = _pageCache[page];
  if (cached != null && cached.key == key && listEquals(cached.path, childrenPath)) return cached.page;

  final child = HelmPageScope(
    page: page,
    childrenPath: childrenPath,
    child: page.route.builder(page.pathParams, page.queryParams),
  );
  final result = switch (page.route.pageType) {
    PageType.material => MaterialPage<Object?>(key: key, name: page.name, arguments: page, child: child),
    PageType.cupertino => CupertinoPage<Object?>(key: key, name: page.name, arguments: page, child: child),
    PageType.dialog => _DialogPage(key: key, name: page.name, arguments: page, child: child),
    PageType.bottomSheet => _BottomSheetPage(key: key, name: page.name, arguments: page, child: child),
  };
  _pageCache[page] = (key: key, path: childrenPath, page: result);
  return result;
}

/// Removes [page] from the stack at [path] after its route was popped.
void removePage(HelmRouterDelegate delegate, StackPath? path, Page<Object?> page) {
  if (path == null) return;
  delegate.change((pages) => pages.updateAt(path, (stack) {
        final index = pageKeys(stack).indexOf(page.key!);
        return index < 0 ? stack : ([...stack]..removeAt(index));
      }));
}

class _DialogPage extends Page<Object?> {
  const _DialogPage({required this.child, super.key, super.name, super.arguments});

  final Widget child;

  // The builder reads the current settings, so an updated page shows its new child.
  @override
  Route<Object?> createRoute(BuildContext context) {
    late final DialogRoute<Object?> route;
    route = DialogRoute<Object?>(
      context: context,
      settings: this,
      builder: (_) => (route.settings as _DialogPage).child,
    );
    return route;
  }
}

class _BottomSheetPage extends Page<Object?> {
  const _BottomSheetPage({required this.child, super.key, super.name, super.arguments});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) {
    late final ModalBottomSheetRoute<Object?> route;
    route = ModalBottomSheetRoute<Object?>(
      settings: this,
      isScrollControlled: true,
      builder: (_) => (route.settings as _BottomSheetPage).child,
    );
    return route;
  }
}
