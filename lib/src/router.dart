import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'delegate.dart';
import 'initial_uri_provider.dart';
import 'parser.dart';
import 'route.dart';

/// The main router configuration for the application.
class HelmRouter extends RouterConfig<NavigationState> {
  factory HelmRouter({
    required List<Routable> routes,
    List<NavigationGuard> guards = const [],
    List<NavigatorObserver> observers = const [],
    TransitionDelegate<Object?> defaultTransitionDelegate = const DefaultTransitionDelegate(),
    Listenable? revalidate,
  }) {
    assert(() {
      if (routes.isEmpty) throw ArgumentError('Routes list cannot be empty');
      final Set<String> seenPaths = {};
      for (final route in routes) {
        final path = route.path;
        if (path.isEmpty) throw ArgumentError('Route path cannot be empty.');
        if (!path.startsWith('/')) throw ArgumentError('Route path must start with "/". Offending route: "$path"');
        if (path == '/-') throw ArgumentError('Route path cannot be "/-".');
        if (!seenPaths.add(path)) throw ArgumentError('Duplicate route path found: "$path"');
      }
      return true;
    }());

    final routeParser = HelmRouteParser(routes);
    final delegate = HelmRouterDelegate(
      guards: guards,
      revalidate: revalidate,
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

  HelmRouter._({
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

  static void change(BuildContext context, NavigationState Function(NavigationState) fn) =>
      delegateOf(context).change(fn);

  static void push(
    BuildContext context,
    Routable route, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
    bool rootNavigator = false,
  }) {
    final delegate = delegateOf(context);
    final parser = delegate.routeParser;

    change(context, (current) {
      Page<Object?>? findLastPage(List<Page<Object?>> pages) {
        if (pages.isEmpty) return null;
        final last = pages.last;
        final args = last.meta;
        if (args?.children?.isNotEmpty ?? false) {
          return findLastPage(args!.children!);
        }
        return last;
      }

      final pagesToAdd = <Page<Object?>>[];

      // 1. Check if a parent route should be pushed first.
      final parentRoute = parser.findParentForRoute(route);
      if (parentRoute != null) {
        final lastPageOnStack = findLastPage(current);
        if (lastPageOnStack == null || (lastPageOnStack.arguments as $RouteMeta?)?.route != parentRoute) {
          pagesToAdd.add(parentRoute.page());
        }
      }

      // 2. Add the actual page the user requested to push.
      pagesToAdd.add(route.page(pathParams: pathParams, queryParams: queryParams));

      // This helper adds a single page to the deepest stack.
      List<Page<Object?>> addToDeepest(List<Page<Object?>> stack, Page<Object?> newPage) {
        if (rootNavigator || stack.isEmpty) return [...stack, newPage];

        final last = stack.last;
        final lastArgs = last.meta;
        if (lastArgs == null) return [...stack, newPage];

        if (lastArgs.children != null) {
          final updatedChildren = addToDeepest(lastArgs.children!, newPage);
          if (listEquals(updatedChildren, lastArgs.children)) return stack;

          final newArgs = lastArgs.copyWith(children: () => updatedChildren);
          final newParent = delegate.rebuildPage(old: last, newArgs: newArgs);
          return [...stack.sublist(0, stack.length - 1), newParent];
        }
        return [...stack, newPage];
      }

      // 3. Sequentially add the pages that need to be pushed.
      var updatedStack = current;
      for (final page in pagesToAdd) {
        updatedStack = addToDeepest(updatedStack, page);
      }

      return updatedStack;
    });
  }

  static void pop(BuildContext context) => delegateOf(context).popRoute();

  static void popUntillRoot(BuildContext context) {
    final delegate = delegateOf(context);
    final rootState = delegate.routeParser.parseUri(Uri.parse('/'));
    delegate.change((_) => rootState);
  }

  static void replaceAll(BuildContext context, NavigationState pages) => delegateOf(context).change((_) => pages);

  static void replaceWithRoute(
    BuildContext context,
    Routable route, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
  }) =>
      delegateOf(context).change((_) => [route.page(pathParams: pathParams, queryParams: queryParams)]);
}
