import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'delegate.dart';
import 'initial_uri_provider.dart';
import 'logger.dart';
import 'parser.dart';
import 'route.dart';
import 'state.dart';

/// The main router configuration for the application that brings together the delegate, parser, and navigation guards.
class HelmRouter extends RouterConfig<NavigationState> {
  factory HelmRouter({
    required List<Routable> routes,
    List<NavigationGuard> guards = const <NavigationGuard>[],
    List<NavigatorObserver> observers = const <NavigatorObserver>[],
    TransitionDelegate<Object?> defaultTransitionDelegate = const DefaultTransitionDelegate<Object?>(),
    Listenable? refresh,
    bool enableLogs = kDebugMode,
  }) {
    assert(() {
      if (routes.isEmpty) throw ArgumentError('Routes list cannot be empty');
      final seenPaths = <String>{};
      final seenParams = <String>{};
      final paramRegex = RegExp(r'\{(\w+)\+?\}');

      for (final route in routes) {
        final path = route.path;
        if (path.isEmpty) throw ArgumentError('Route path cannot be empty.');
        if (!path.startsWith('/')) throw ArgumentError('Route path must start with "/". Offending route: "$path"');
        if (path == '/-') throw ArgumentError('Route path cannot be "/-".');
        if (!seenPaths.add(path)) throw ArgumentError('Duplicate route path found: "$path"');
        for (final match in paramRegex.allMatches(path)) {
          final paramName = match.group(1);
          if (paramName != null && !seenParams.add(paramName)) {
            throw ArgumentError(
                'Duplicate path parameter name found: "{$paramName}". Parameter names must be unique across all routes.');
          }
        }
      }
      return true;
    }());

    enableLogs ? HelmLogger.on() : HelmLogger.off();

    final routeParser = HelmRouteParser(routes);
    final delegate = HelmRouterDelegate(
      guards: guards,
      revalidate: refresh,
      observers: observers,
      defaultTransitionDelegate: defaultTransitionDelegate,
      routeParser: routeParser,
    );

    final initialUri = getInitialUri();
    final provider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: initialUri),
    );

    return HelmRouter._(
      delegate: delegate,
      routeInformationParser: HelmRouteInformationParser(routeParser: routeParser),
      backButtonDispatcher: RootBackButtonDispatcher(),
      routeInformationProvider: provider,
    );
  }

  const HelmRouter._({
    required HelmRouterDelegate delegate,
    required HelmRouteInformationParser super.routeInformationParser,
    required BackButtonDispatcher super.backButtonDispatcher,
    required RouteInformationProvider super.routeInformationProvider,
  }) : super(routerDelegate: delegate);

  static HelmRouterDelegate delegateOf(BuildContext context) {
    final delegate = Router.of(context).routerDelegate;
    assert(
      delegate is HelmRouterDelegate,
      'AppRouter.of() was called with a context that does not contain an AppRouter.',
    );
    return delegate as HelmRouterDelegate;
  }

  // CORE

  /// Returns the current [Uri] that represents the live navigation stack.
  static Uri? currentUri(BuildContext context) => delegateOf(context).currentUri;

  /// Returns the [Map<String, String>] of the live navigation state.
  static Map<String, String> currentQueryParams(BuildContext context) => delegateOf(context).currentQueryParams;

  /// Returns the current [NavigationState]
  static NavigationState state(BuildContext context) => delegateOf(context).currentConfiguration;

  static void change(BuildContext context, NavigationGuard fn) => delegateOf(context).change(fn);

  static void changeQueryParams(BuildContext context, {required Map<String, String> queryParams}) =>
      delegateOf(context).change((current) {
        NavigationState updateRecursive(NavigationState pages) {
          return pages.map((page) {
            final meta = page.meta;
            if (meta == null) return page;

            final updatedQueryParams = Map<String, String>.from(meta.queryParams);
            queryParams.forEach((key, value) {
              if (value.isEmpty) {
                updatedQueryParams.remove(key);
              } else {
                updatedQueryParams[key] = value;
              }
            });

            final updatedChildren = meta.children != null ? updateRecursive(meta.children!) : null;
            final queryChanged = !mapEquals(meta.queryParams, updatedQueryParams);
            final childrenChanged = updatedChildren != null && !listEquals(meta.children, updatedChildren);

            if (!queryChanged && !childrenChanged) return page;

            final newMeta = meta.copyWith(
              queryParams: updatedQueryParams,
              children: childrenChanged ? () => updatedChildren : null,
            );

            return meta.route.build(page.key, page.name!, newMeta);
          }).toList();
        }

        return updateRecursive(current);
      });

  // BASICS

  static void push(
    BuildContext context,
    Routable route, {
    Map<String, String> pathParams = const <String, String>{},
    Map<String, String> queryParams = const <String, String>{},
    bool rootNavigator = false,
  }) {
    final delegate = delegateOf(context);
    final parser = delegate.routeParser;

    delegate.change((current) {
      final currentQueryParams = delegate.currentQueryParams;
      final mergedQueryParams = {...currentQueryParams, ...queryParams};

      NavigationState findDeepestStack(NavigationState pages) {
        if (rootNavigator || pages.isEmpty) return pages;
        final last = pages.last;
        final children = last.meta?.children;
        if (children != null) return findDeepestStack(children);
        return pages;
      }

      final deepestStack = findDeepestStack(current);
      final lastPageOnStack = deepestStack.isNotEmpty ? deepestStack.last : null;
      final lastRouteOnStack = lastPageOnStack?.meta?.route;

      final pagesToAdd = <Page<Object?>>[];

      if (route.isArbitrary && route == lastRouteOnStack) {
        pagesToAdd.add(route.page(pathParams: pathParams, queryParams: mergedQueryParams));
      } else {
        final parentPages = parser.getParentStackFor(route, pathParams: pathParams, queryParams: mergedQueryParams);
        for (final parentPage in parentPages) {
          if (lastPageOnStack == null || parentPage.name != lastPageOnStack.name) {
            pagesToAdd.add(parentPage);
          }
        }
        pagesToAdd.add(route.page(pathParams: pathParams, queryParams: mergedQueryParams));
      }

      NavigationState addAllToDeepest(NavigationState stack, List<Page<Object?>> newPages) {
        if (rootNavigator || stack.isEmpty) return <Page<Object?>>[...stack, ...newPages];

        final last = stack.last;
        final lastArgs = last.meta;
        if (lastArgs == null) return <Page<Object?>>[...stack, ...newPages];

        final children = lastArgs.children;
        if (children != null) {
          final updatedChildren = addAllToDeepest(children, newPages);
          if (listEquals(updatedChildren, children)) return stack;

          final newArgs = lastArgs.copyWith(children: () => updatedChildren);
          final newParent = newArgs.route.build(last.key, last.name!, newArgs);
          return [...stack.sublist(0, stack.length - 1), newParent];
        }
        return <Page<Object?>>[...stack, ...newPages];
      }

      return addAllToDeepest(current, pagesToAdd);
    });
  }

  static void pop(BuildContext context) => delegateOf(context).popRoute();

  // HELPERS

  static void popUntillRoot(BuildContext context) {
    final delegate = delegateOf(context);
    final rootState = delegate.routeParser.parseUri(Uri.parse('/'));
    delegate.change((_) => rootState);
  }

  static void replaceAll(BuildContext context, NavigationState pages) => delegateOf(context).change((_) => pages);

  static void replaceWithRoute(
    BuildContext context,
    Routable route, {
    Map<String, String> pathParams = const <String, String>{},
    Map<String, String> queryParams = const <String, String>{},
  }) =>
      delegateOf(context).change((_) => <Page<Object?>>[route.page(pathParams: pathParams, queryParams: queryParams)]);
}
