import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';

import 'parser.dart';
import 'route.dart';

/// A type alias for a navigation guard, a function that can transform the page stack.
typedef NavigationGuard = NavigationState Function(NavigationState pages);

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

  NavigationState _pages = [];

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  NavigationState get currentConfiguration => UnmodifiableListView(_pages);

  NavigationState _applyGuards(NavigationState pages) => guards.fold(pages, (current, guard) => guard(current));

  void change(NavigationState Function(NavigationState) fn) {
    final newPages = fn(UnmodifiableListView(_pages));
    final guardedPages = _applyGuards(newPages);
    if (listEquals(_pages, guardedPages)) return;
    _pages = UnmodifiableListView(guardedPages);
    notifyListeners();
  }

  void _revalidateState() {
    // routeParser.clearCaches();
    change((state) => state);
  }

  Page<Object?> rebuildPage({
    required Page<Object?> old,
    required $RouteMeta newArgs,
  }) =>
      MaterialPage<Object?>(
        key: old.key,
        name: old.name,
        arguments: newArgs,
        child: newArgs.route.builder(
          newArgs.pathParams,
          newArgs.queryParams,
        ),
      );

  void prepareNestedNavigator(String parentRouteName) {
    change((current) {
      List<Page<Object?>> recur(List<Page<Object?>> pages) => pages.map((page) {
            final args = page.meta;
            if (args == null) return page;

            // case 1: this is the parent that needs an empty child stack
            if (page.name == parentRouteName && args.children == null) {
              final newArgs = args.copyWith(children: () => []);
              return rebuildPage(old: page, newArgs: newArgs);
            }

            // case 2: recurse into children
            if (args.children?.isNotEmpty ?? false) {
              final updated = recur(args.children!);
              if (!listEquals(updated, args.children)) {
                final newArgs = args.copyWith(children: () => updated);
                return rebuildPage(old: page, newArgs: newArgs);
              }
            }
            return page;
          }).toList();

      return recur(current);
    });
  }

  void setInitialNestedRoute(String parentRouteName, NavigationState initialState) {
    change((current) {
      List<Page<Object?>> recur(List<Page<Object?>> pages) => pages.map((page) {
            final args = page.meta;
            if (args == null) return page;
            // case 1: we found the target parent page.
            if (page.name == parentRouteName && (args.children == null || args.children!.isEmpty)) {
              final newArgs = args.copyWith(children: () => initialState);
              return rebuildPage(old: page, newArgs: newArgs);
            }
            // case 2: not the target, but this page might contain the target in its children.
            if (args.children?.isNotEmpty ?? false) {
              final updated = recur(args.children!);
              if (!listEquals(updated, args.children)) {
                final newArgs = args.copyWith(children: () => updated);
                return rebuildPage(old: page, newArgs: newArgs);
              }
            }
            // case 3: no changes needed for this page.
            return page;
          }).toList();

      return recur(current);
    });
  }

  void replaceNestedStack(String parentRouteName, NavigationState nestedPages) =>
      change((current) => _updateNestedStack(current, parentRouteName, nestedPages));

  NavigationState _updateNestedStack(NavigationState pages, String parentRouteName, NavigationState nestedPages) {
    final result = List<Page<Object?>>.from(pages);
    var changed = false;

    for (var i = 0; i < result.length; i++) {
      final page = result[i];
      final args = page.meta;

      if (page.name == parentRouteName) {
        final newArgs = args!.copyWith(children: () => nestedPages);
        result[i] = rebuildPage(old: page, newArgs: newArgs);
        changed = true;
        break;
      }

      if (args?.children?.isNotEmpty ?? false) {
        final updatedChildren = _updateNestedStack(args!.children!, parentRouteName, nestedPages);
        if (!listEquals(updatedChildren, args.children)) {
          final newArgs = args.copyWith(children: () => updatedChildren);
          result[i] = rebuildPage(old: page, newArgs: newArgs);
          changed = true;
          break;
        }
      }
    }

    return changed ? result : pages;
  }

  @override
  Future<void> setNewRoutePath(NavigationState pages) {
    final newPages = _applyGuards(pages);
    if (listEquals(_pages, newPages)) return SynchronousFuture(null);
    _pages = UnmodifiableListView(newPages);
    return SynchronousFuture(null);
  }

  @override
  Future<bool> popRoute() {
    if (currentConfiguration.isEmpty) return Future.value(false);
    final lastPage = _pages.last;
    final lastArgs = lastPage.meta;
    if (lastArgs?.children?.isNotEmpty ?? false) {
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

    if (args?.children?.isNotEmpty ?? false) {
      final updatedChildren = _popDeepestPage(args!.children!);

      if (!listEquals(updatedChildren, args.children)) {
        final newArgs = args.copyWith(children: () => updatedChildren);
        final newLastPage = rebuildPage(old: lastPage, newArgs: newArgs);
        return [...pages.sublist(0, pages.length - 1), newLastPage];
      }
    }
    return pages.sublist(0, pages.length - 1);
  }

  NavigationState? _removePage(NavigationState pages, Page<Object?> targetPage) {
    final topLevelIndex = pages.indexWhere((p) => p == targetPage);
    if (topLevelIndex != -1) return pages.where((p) => p != targetPage).toList();

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final args = page.meta;

      if (args?.children?.isNotEmpty ?? false) {
        final newChildren = _removePage(args!.children!, targetPage);
        if (newChildren != null && !listEquals(newChildren, args.children)) {
          final newArgs = args.copyWith(children: () => newChildren);
          final newPage = rebuildPage(old: page, newArgs: newArgs);
          final result = List<Page<Object?>>.from(pages);
          result[i] = newPage;
          return result;
        }
      }
    }

    return null;
  }

  void _onDidRemovePage(Page<Object?> page) {
    change((current) => _removePage(current, page) ?? current);
  }

  @override
  void dispose() {
    revalidate?.removeListener(_revalidateState);
    _transitionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) return const SizedBox.shrink();
    return Navigator(
      key: navigatorKey,
      pages: _pages,
      transitionDelegate: _transitionDelegate,
      observers: observers,
      onDidRemovePage: _onDidRemovePage,
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

  void dispose() {
    _delegateCache.clear();
  }
}
