import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'logger.dart';
import 'parser.dart';
import 'route.dart';
import 'state.dart';

/// A type alias for a navigation guard, a function that can transform the page stack.
typedef NavigationGuard = NavigationState Function(NavigationState pages);

/// The core state manager for the router; it holds the page stack and builds the `Navigator`.
class HelmRouterDelegate extends RouterDelegate<NavigationState>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<NavigationState> {
  HelmRouterDelegate({
    required this.guards,
    required this.revalidate,
    required this.observers,
    required this.routeParser,
    required TransitionDelegate<Object?> defaultTransitionDelegate,
  }) : _transitionDelegate = _PerRouteTransitionDelegate(defaultDelegate: defaultTransitionDelegate) {
    revalidate?.addListener(_revalidateState);
  }

  final List<NavigationGuard> guards;
  final Listenable? revalidate;
  final List<NavigatorObserver> observers;
  final _PerRouteTransitionDelegate _transitionDelegate;
  final HelmRouteParser routeParser;

  NavigationState _pages = const <Page<Object?>>[];
  bool _revalidationNeeded = false;
  bool _mounted = true;

  // CORE

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Uri? currentUri;

  @override
  NavigationState get currentConfiguration => _pages;

  Map<String, String> get currentQueryParams {
    final allQueryParams = <String, String>{};
    void collect(NavigationState pages) {
      for (final page in pages) {
        final meta = page.meta;
        if (meta != null) {
          allQueryParams.addAll(meta.queryParams);
          if (meta.children != null) {
            collect(meta.children!);
          }
        }
      }
    }

    collect(_pages);
    return allQueryParams;
  }

  @override
  Future<void> setNewRoutePath(NavigationState pages) {
    final newPages = _applyGuards(pages);
    if (listEquals(_pages, newPages)) return SynchronousFuture(null);
    _pages = UnmodifiableListView(newPages);
    currentUri = routeParser.restoreUri(_pages);
    return SynchronousFuture(null);
  }

  void change(NavigationGuard fn) {
    final newPages = fn(NavigationState.from(_pages));
    final guardedPages = _applyGuards(newPages);
    if (listEquals(_pages, guardedPages)) return;
    _pages = UnmodifiableListView(guardedPages);
    currentUri = routeParser.restoreUri(_pages);
    notifyListeners();
    HelmLogger.msg(_pages.toPrettyString());
  }

  NavigationState _applyGuards(NavigationState pages) {
    if (guards.isEmpty) return pages;
    var current = pages;
    for (final guard in guards) {
      current = guard(current);
    }
    return current;
  }

  void _revalidateState() {
    _revalidationNeeded = true;
    notifyListeners();
  }

  // NESTED NAVIGATORS

  void prepareNestedNavigator(String parentRouteName) =>
      change((current) => _prepareNestedNavigatorRecursive(current, parentRouteName));

  NavigationState _prepareNestedNavigatorRecursive(NavigationState pages, String parentRouteName) {
    var hasChanges = false;
    final result = NavigationState.generate(pages.length, (i) {
      final page = pages[i];
      final args = page.meta;
      if (args == null) return page;

      // case 1: this is the parent that needs an empty child stack
      if (page.name == parentRouteName && args.children == null) {
        hasChanges = true;
        final newArgs = args.copyWith(children: () => const <Page<Object?>>[]);
        return page.meta!.route.build(page.key, page.name!, newArgs);
      }

      // case 2: recurse into children
      final children = args.children;
      if (children != null && children.isNotEmpty) {
        final updated = _prepareNestedNavigatorRecursive(children, parentRouteName);
        if (!listEquals(updated, children)) {
          hasChanges = true;
          final newArgs = args.copyWith(children: () => updated);
          return page.meta!.route.build(page.key, page.name!, newArgs);
        }
      }
      return page;
    });

    return hasChanges ? result : pages;
  }

  void setInitialNestedRoute(String parentRouteName, NavigationState initialState) =>
      change((current) => _setInitialNestedRouteRecursive(current, parentRouteName, initialState));

  NavigationState _setInitialNestedRouteRecursive(
      NavigationState pages, String parentRouteName, NavigationState initialState) {
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final args = page.meta;
      if (args == null) continue;

      // case 1: we found the target parent page.
      if (page.name == parentRouteName && (args.children == null || args.children!.isEmpty)) {
        final newArgs = args.copyWith(children: () => initialState);
        final result = NavigationState.from(pages);
        result[i] = page.meta!.route.build(page.key, page.name!, newArgs);
        return result;
      }

      // case 2: recurse into children
      final children = args.children;
      if (children != null && children.isNotEmpty) {
        final updated = _setInitialNestedRouteRecursive(children, parentRouteName, initialState);
        if (!listEquals(updated, children)) {
          final newArgs = args.copyWith(children: () => updated);
          final result = NavigationState.from(pages);
          result[i] = page.meta!.route.build(page.key, page.name!, newArgs);
          return result;
        }
      }
    }
    return pages;
  }

  void replaceNestedStack(String parentRouteName, NavigationState nestedPages) =>
      change((current) => _updateNestedStack(current, parentRouteName, nestedPages));

  NavigationState _updateNestedStack(NavigationState pages, String parentRouteName, NavigationState nestedPages) {
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final args = page.meta;

      if (page.name == parentRouteName) {
        final newArgs = args!.copyWith(children: () => nestedPages);
        final result = NavigationState.from(pages);
        result[i] = page.meta!.route.build(page.key, page.name!, newArgs);
        return result;
      }

      final children = args?.children;
      if (children != null && children.isNotEmpty) {
        final updatedChildren = _updateNestedStack(children, parentRouteName, nestedPages);
        if (!listEquals(updatedChildren, children)) {
          final newArgs = args!.copyWith(children: () => updatedChildren);
          final result = NavigationState.from(pages);
          result[i] = page.meta!.route.build(page.key, page.name!, newArgs);
          return result;
        }
      }
    }

    return pages;
  }

  // POP

  @override
  Future<bool> popRoute() {
    if (_pages.isEmpty) return Future.value(false);

    final lastPage = _pages.last;
    final lastArgs = lastPage.meta;
    final children = lastArgs?.children;

    if (children != null && children.isNotEmpty) {
      change(_popDeepestPage);
      return Future.value(true);
    }

    if (_pages.length > 1) {
      change((pages) => pages.sublist(0, pages.length - 1));
      return Future.value(true);
    }

    return Future.value(false);
  }

  NavigationState _popDeepestPage(NavigationState pages) {
    if (pages.isEmpty) return pages;

    final lastPage = pages.last;
    final args = lastPage.meta;
    final children = args?.children;

    if (children != null && children.isNotEmpty) {
      final updatedChildren = _popDeepestPage(children);

      if (!listEquals(updatedChildren, children)) {
        final newArgs = args!.copyWith(children: () => updatedChildren);
        final newLastPage = lastPage.meta!.route.build(lastPage.key, lastPage.name!, newArgs);
        return [...pages.sublist(0, pages.length - 1), newLastPage];
      }
    }
    return pages.sublist(0, pages.length - 1);
  }

  NavigationState? _removePage(NavigationState pages, Page<Object?> targetPage) {
    // Fast path: check top level first with indexOf for better performance
    final topLevelIndex = pages.indexOf(targetPage);
    if (topLevelIndex != -1) {
      final result = NavigationState.from(pages);
      result.removeAt(topLevelIndex);
      return result;
    }

    // Deep search in children
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final args = page.meta;
      final children = args?.children;

      if (children != null && children.isNotEmpty) {
        final newChildren = _removePage(children, targetPage);
        if (newChildren != null && !listEquals(newChildren, children)) {
          final newArgs = args!.copyWith(children: () => newChildren);
          final newPage = page.meta!.route.build(page.key, page.name!, newArgs);
          final result = NavigationState.from(pages);
          result[i] = newPage;
          return result;
        }
      }
    }

    return null;
  }

  void onDidRemovePage(Page<Object?> page) => change((current) => _removePage(current, page) ?? current);

  @override
  void dispose() {
    _mounted = false;
    revalidate?.removeListener(_revalidateState);
    _transitionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_revalidationNeeded) {
      _revalidationNeeded = false;
      scheduleMicrotask(() {
        if (_mounted) change((state) => state);
      });
    }
    if (_pages.isEmpty) return const SizedBox.shrink();
    return Navigator(
      key: navigatorKey,
      pages: _pages,
      transitionDelegate: _transitionDelegate,
      observers: observers,
      onDidRemovePage: onDidRemovePage,
    );
  }
}

class _PerRouteTransitionDelegate extends TransitionDelegate<Object?> {
  _PerRouteTransitionDelegate({required this.defaultDelegate});

  final TransitionDelegate<Object?> defaultDelegate;
  final Map<TransitionDelegate<Object?>, TransitionDelegate<Object?>> _delegateCache = {};

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord> locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>> pageRouteToPagelessRoutes,
  }) {
    final topMostRoute = newPageRouteHistory.lastOrNull;
    if (topMostRoute != null) {
      final args = topMostRoute.route.settings.arguments;
      if (args is $RouteMeta) {
        final routeDelegate = args.route.transitionDelegate;
        if (routeDelegate != null) {
          final cachedDelegate = _delegateCache.putIfAbsent(routeDelegate, () => routeDelegate);
          return cachedDelegate.resolve(
            newPageRouteHistory: newPageRouteHistory,
            locationToExitingPageRoute: locationToExitingPageRoute,
            pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
          );
        }
      }
    }
    return defaultDelegate.resolve(
      newPageRouteHistory: newPageRouteHistory,
      locationToExitingPageRoute: locationToExitingPageRoute,
      pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
    );
  }

  void dispose() => _delegateCache.clear();
}
