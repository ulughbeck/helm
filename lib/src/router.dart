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
    List<NavigationGuard> guards = const <NavigationGuard>[],
    List<NavigatorObserver> observers = const <NavigatorObserver>[],
    TransitionDelegate<Object?> defaultTransitionDelegate = const DefaultTransitionDelegate<Object?>(),
    Listenable? revalidate,
  }) {
    assert(() {
      if (routes.isEmpty) throw ArgumentError('Routes list cannot be empty');
      final seenPaths = <String>{};
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

  const HelmRouter._({
    required HelmRouterDelegate delegate,
    required HelmRouteInformationParser super.routeInformationParser,
    required BackButtonDispatcher super.backButtonDispatcher,
    required RouteInformationProvider super.routeInformationProvider,
  }) : super(routerDelegate: delegate);

  static final Uri _rootUri = Uri.parse('/');

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
    Map<String, String> pathParams = const <String, String>{},
    Map<String, String> queryParams = const <String, String>{},
    bool rootNavigator = false,
  }) {
    final delegate = delegateOf(context);
    final parser = delegate.routeParser;

    change(context, (current) {
      Page<Object?>? findLastPage(NavigationState pages) {
        if (pages.isEmpty) return null;
        final last = pages.last;
        final args = last.meta;
        final children = args?.children;
        if (children?.isNotEmpty == true) return findLastPage(children!);
        return last;
      }

      final pagesToAdd = <Page<Object?>>[];

      // 1. Check if a parent route should be pushed first.
      final parentRoute = parser.findParentForRoute(route);
      if (parentRoute != null) {
        final lastPageOnStack = findLastPage(current);
        if (lastPageOnStack == null || (lastPageOnStack.meta)?.route != parentRoute) {
          pagesToAdd.add(parentRoute.page());
        }
      }

      // 2. Add the actual page the user requested to push.
      pagesToAdd.add(route.page(pathParams: pathParams, queryParams: queryParams));

      // This helper adds a single page to the deepest stack.
      NavigationState addToDeepest(NavigationState stack, Page<Object?> newPage) {
        if (rootNavigator || stack.isEmpty) return <Page<Object?>>[...stack, newPage];

        final last = stack.last;
        final lastArgs = last.meta;
        if (lastArgs == null) return <Page<Object?>>[...stack, newPage];

        final children = lastArgs.children;
        if (children != null) {
          final updatedChildren = addToDeepest(children, newPage);
          if (listEquals(updatedChildren, children)) return stack;

          final newArgs = lastArgs.copyWith(children: () => updatedChildren);
          final newParent = delegate.rebuildPage(old: last, newArgs: newArgs);
          final newStack = <Page<Object?>>[];
          for (var i = 0; i < stack.length - 1; i++) {
            newStack.add(stack[i]);
          }
          newStack.add(newParent);
          return newStack;
        }
        return <Page<Object?>>[...stack, newPage];
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
    final rootState = delegate.routeParser.parseUri(_rootUri);
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
