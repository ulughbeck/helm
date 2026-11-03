import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'delegate.dart';
import 'logger.dart';
import 'parser.dart';
import 'route.dart';
import 'state.dart';

/// The router configuration. It connects the delegate, the parser, and the platform URL.
class HelmRouter extends RouterConfig<NavigationState> {
  factory HelmRouter({
    required List<Routable> routes,
    List<NavigationGuard> guards = const <NavigationGuard>[],
    List<NavigatorObserver> observers = const <NavigatorObserver>[],
    TransitionDelegate<Object?> defaultTransitionDelegate = const DefaultTransitionDelegate<Object?>(),
    Listenable? refresh,
    bool enableLogs = kDebugMode,
    bool logNavigationStack = false,
  }) {
    assert(_validateRoutes(routes));

    final routeParser = HelmRouteParser(
      routes,
      logger: HelmLogger(enabled: enableLogs, logStack: logNavigationStack),
    );
    return HelmRouter._(
      delegate: HelmRouterDelegate(
        routeParser: routeParser,
        guards: guards,
        observers: observers,
        refresh: refresh,
        defaultTransitionDelegate: defaultTransitionDelegate,
      ),
      routeInformationParser: HelmRouteInformationParser(routeParser: routeParser),
      backButtonDispatcher: RootBackButtonDispatcher(),
      routeInformationProvider: HelmRouteInformationProvider(
        initialRouteInformation: RouteInformation(uri: _initialUri()),
      ),
    );
  }

  const HelmRouter._({
    required this.delegate,
    required HelmRouteInformationParser super.routeInformationParser,
    required BackButtonDispatcher super.backButtonDispatcher,
    required RouteInformationProvider super.routeInformationProvider,
  }) : super(routerDelegate: delegate);

  final HelmRouterDelegate delegate;

  static HelmRouterDelegate delegateOf(BuildContext context) => switch (Router.of(context).routerDelegate) {
        final HelmRouterDelegate delegate => delegate,
        _ => throw FlutterError('HelmRouter.delegateOf() was called with a context that is not inside a HelmRouter.'),
      };

  // STATE

  /// The URL of the current state.
  static Uri? currentUri(BuildContext context) => delegateOf(context).currentUri;

  /// Query params of the current state.
  static Map<String, String> currentQueryParams(BuildContext context) => delegateOf(context).currentQueryParams;

  /// Path params of the current state. See [HelmRouterDelegate.currentPathParams].
  static Map<String, String> currentPathParams(BuildContext context) => delegateOf(context).currentPathParams;

  /// The current state.
  static NavigationState state(BuildContext context) => delegateOf(context).currentConfiguration;

  // CHANGES

  /// Replaces the state with the result of [fn].
  static void change(BuildContext context, NavigationGuard fn) => delegateOf(context).change(fn);

  /// Sets query params on all pages. An empty value removes the key.
  static void changeQueryParams(BuildContext context, {required Map<String, String> queryParams}) => change(
      context,
      (pages) => pages.mapPages((page) {
            final updated = {...page.queryParams};
            queryParams.forEach((key, value) => value.isEmpty ? updated.remove(key) : updated[key] = value);
            return mapEquals(updated, page.queryParams) ? page : page.copyWith(queryParams: updated);
          }));

  /// Pushes [route] on the deepest active stack, or on the root stack when [rootNavigator] is true.
  ///
  /// Parent routes that are not in the target stack are added first, for example `/products`
  /// before `/products/{pid}`. Current query params are merged into the new pages.
  static void push(
    BuildContext context,
    Routable route, {
    Map<String, String> pathParams = const <String, String>{},
    Map<String, String> queryParams = const <String, String>{},
    bool rootNavigator = false,
  }) {
    final delegate = delegateOf(context);
    delegate.change((pages) {
      final query = {...delegate.currentQueryParams, ...queryParams};
      final page = route.page(pathParams: pathParams, queryParams: query);
      return pages.updateAt(rootNavigator ? const [] : pages.deepestPath, (stack) {
        if (route.isArbitrary && stack.lastOrNull?.route == route) return [...stack, page];
        final names = {for (final p in stack) p.name};
        final parents = delegate.routeParser.parentPagesFor(route, pathParams: pathParams, queryParams: query);
        return [...stack, ...parents.where((p) => !names.contains(p.name)), page];
      });
    });
  }

  /// Pops like the system back button. Returns false when nothing was popped.
  static Future<bool> pop(BuildContext context) => delegateOf(context).popRoute();

  /// Replaces the state with the root route.
  static void popUntilRoot(BuildContext context) {
    final delegate = delegateOf(context);
    delegate.change((_) => delegate.routeParser.parseUri(Uri(path: '/')));
  }

  static void replaceAll(BuildContext context, NavigationState pages) => change(context, (_) => pages);

  static void replaceWithRoute(
    BuildContext context,
    Routable route, {
    Map<String, String> pathParams = const <String, String>{},
    Map<String, String> queryParams = const <String, String>{},
  }) =>
      change(context, (_) => [route.page(pathParams: pathParams, queryParams: queryParams)]);
}

/// Replaces the platform history entry when the router only normalizes a URL that the platform
/// just reported, for example when it adds the initial nested stack. Other changes push a new entry.
class HelmRouteInformationProvider extends PlatformRouteInformationProvider {
  HelmRouteInformationProvider({required super.initialRouteInformation});

  bool _platformReported = true;

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    _platformReported = true;
    return super.didPushRouteInformation(routeInformation);
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    final normalizes = _platformReported && type == RouteInformationReportingType.none;
    _platformReported = false;
    super.routerReportsNewRouteInformation(
      routeInformation,
      type: normalizes ? RouteInformationReportingType.neglect : type,
    );
  }
}

/// The URL the platform opened the app with. On the web, the URL strategy removes the
/// `<base href>` prefix, so an app served from a sub-path gets its own path.
Uri _initialUri() {
  final name = WidgetsFlutterBinding.ensureInitialized().platformDispatcher.defaultRouteName;
  // `//shop` would parse `shop` as a host, so keep exactly one leading slash.
  return Uri.tryParse(name.replaceFirst(RegExp('^/*'), '/')) ?? Uri(path: '/');
}

bool _validateRoutes(List<Routable> routes) {
  if (routes.isEmpty) throw ArgumentError('Routes list cannot be empty');
  final seenPaths = <String>{};
  for (final route in routes) {
    final path = route.path;
    if (path.isEmpty) throw ArgumentError('Route path cannot be empty.');
    if (!path.startsWith('/')) throw ArgumentError('Route path must start with "/". Offending route: "$path"');
    if (path.contains(RegExp(r'\s'))) throw ArgumentError('Route path cannot contain whitespace: "$path"');
    if (path.contains('//')) throw ArgumentError('Route path cannot contain empty segments ("//"): "$path"');
    if (path == '/-') throw ArgumentError('Route path cannot be "/-".');
    if (path.contains('!') || path.contains('~')) {
      throw ArgumentError('Route path cannot contain "!" or "~", the URL grammar uses them: "$path"');
    }
    // `/a/{x}` and `/a/{y}` match the same URLs, so compare paths without param names.
    final shape = path.replaceAllMapped(RegExp(r'\{\w+(\+?)\}'), (m) => '{${m.group(1)}}');
    if (!seenPaths.add(shape)) throw ArgumentError('Duplicate route path found: "$path"');
  }
  return true;
}
