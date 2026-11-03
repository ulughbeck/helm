import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'pages.dart';
import 'parser.dart';
import 'state.dart';

/// Transforms the navigation state on every change. Guards run in order.
typedef NavigationGuard = NavigationState Function(NavigationState pages);

/// Holds the navigation state and builds the root [Navigator].
class HelmRouterDelegate extends RouterDelegate<NavigationState> with ChangeNotifier {
  HelmRouterDelegate({
    required this.routeParser,
    this.guards = const [],
    this.observers = const [],
    Listenable? refresh,
    TransitionDelegate<Object?> defaultTransitionDelegate = const DefaultTransitionDelegate<Object?>(),
  })  : transitionDelegate = _PerRouteTransitionDelegate(defaultTransitionDelegate),
        _refresh = refresh {
    _refresh?.addListener(_revalidate);
  }

  final HelmRouteParser routeParser;
  final List<NavigationGuard> guards;
  final List<NavigatorObserver> observers;

  /// Uses the transition delegate of the top route, or the default one.
  final TransitionDelegate<Object?> transitionDelegate;

  final Listenable? _refresh;
  final navigatorKey = GlobalKey<NavigatorState>();

  NavigationState _pages = const [];
  Uri? _currentUri;

  /// The URL of the current state.
  Uri? get currentUri => _currentUri;

  @override
  NavigationState get currentConfiguration => _pages;

  /// Query params of all pages. A later page wins for a repeated key.
  Map<String, String> get currentQueryParams {
    final result = <String, String>{};
    _pages.mapPages((page) {
      result.addAll(page.queryParams);
      return page;
    });
    return result;
  }

  /// Path params of all pages. Keys get the occurrence index, for example `id-0` and `id-1`.
  Map<String, String> get currentPathParams {
    final result = <String, String>{};
    final counts = <String, int>{};
    void collect(NavigationState pages) {
      for (final page in pages) {
        page.pathParams.forEach((key, value) {
          result['$key-${counts.update(key, (n) => n + 1, ifAbsent: () => 0)}'] = value;
        });
        if (page.children != null) collect(page.children!);
      }
    }

    collect(_pages);
    return result;
  }

  @override
  Future<void> setNewRoutePath(NavigationState configuration) {
    _update(configuration);
    return SynchronousFuture(null);
  }

  /// Replaces the state with the result of [fn], then runs the guards.
  void change(NavigationGuard fn) {
    if (_update(fn(List.of(_pages)))) notifyListeners();
  }

  bool _update(NavigationState pages) {
    final next = guards.fold(pages, (current, guard) => guard(current));
    if (listEquals(next, _pages)) return false;
    _pages = List.unmodifiable(next);
    _currentUri = routeParser.restoreUri(_pages);
    routeParser.logger
      ..msg('current path: $_currentUri')
      ..stack(_pages);
    return true;
  }

  void _revalidate() => change((pages) => pages);

  /// Pops the deepest active navigator. A navigator with one page passes the pop to its parent.
  ///
  /// It uses [NavigatorState.maybePop], so [PopScope] and pageless routes such as dialogs work.
  @override
  Future<bool> popRoute() async {
    for (final navigator in _activeNavigators().reversed) {
      if (await navigator.maybePop()) return true;
    }
    return false;
  }

  /// The root navigator and the nested navigators on the active path, root first.
  List<NavigatorState> _activeNavigators() {
    final root = navigatorKey.currentState;
    if (root == null) return const [];
    final result = [root];
    final hosts = nestedHosts(this);
    final path = <int>[];
    NavigationState stack = _pages;
    while (stack.isNotEmpty && stack.last.children != null) {
      path.add(stack.length - 1);
      final host = hosts.where((h) => listEquals(h.stackPath, path)).firstOrNull;
      final navigator = host?.navigator;
      if (host == null || navigator == null || !(ModalRoute.isCurrentOf(host.context) ?? false)) break;
      result.add(navigator);
      stack = stack.last.children!;
    }
    return result;
  }

  @override
  void dispose() {
    _refresh?.removeListener(_revalidate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) return const SizedBox.shrink();
    return Navigator(
      key: navigatorKey,
      pages: buildPages(_pages, const []),
      transitionDelegate: transitionDelegate,
      observers: observers,
      onDidRemovePage: (page) => removePage(this, const [], page),
    );
  }
}

class _PerRouteTransitionDelegate extends TransitionDelegate<Object?> {
  const _PerRouteTransitionDelegate(this.fallback);

  final TransitionDelegate<Object?> fallback;

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord> locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>> pageRouteToPagelessRoutes,
  }) {
    final page = newPageRouteHistory.lastOrNull?.route.settings.arguments;
    final delegate = (page is HelmPage ? page.route.transitionDelegate : null) ?? fallback;
    return delegate.resolve(
      newPageRouteHistory: newPageRouteHistory,
      locationToExitingPageRoute: locationToExitingPageRoute,
      pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
    );
  }
}
