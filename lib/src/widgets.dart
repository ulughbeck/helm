import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'delegate.dart';
import 'pages.dart';
import 'route.dart';
import 'router.dart';
import 'state.dart';

/// Shows the nested stack of the enclosing page in its own [Navigator].
///
/// Use it for master-detail layouts or screens with their own navigation flow. When the nested
/// stack is empty, the widget sets it to [initialState] or to a page of [initialRoute]. Without
/// both, the stack stays empty until a push. A URL that dives into the page sets the stack instead. The [builder] gets the nested `Navigator` as `child`.
class NestedNavigator extends StatefulWidget {
  const NestedNavigator({
    required this.builder,
    this.initialRoute,
    this.initialState,
    this.observers = const <NavigatorObserver>[],
    this.transitionDelegate,
    super.key,
  })  : assert(
          initialRoute == null || initialState == null,
          'Provide only one of initialRoute or initialState.',
        ),
        assert(initialState == null || initialState.length > 0, 'initialState cannot be empty.');

  final Routable? initialRoute;
  final NavigationState? initialState;
  final Widget Function(BuildContext context, Widget child) builder;
  final List<NavigatorObserver> observers;
  final TransitionDelegate<Object?>? transitionDelegate;

  @override
  State<NestedNavigator> createState() => _NestedNavigatorState();
}

class _NestedNavigatorState extends State<NestedNavigator> with _NestedHostMixin {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  NavigatorState? get navigator => _navigatorKey.currentState;

  @override
  Widget build(BuildContext context) {
    final scope = _scopeOf(context, 'NestedNavigator', _normalize);
    final children = scope.page.children;
    if (children == null || children.isEmpty) return widget.builder(context, const SizedBox.shrink());

    return widget.builder(
      context,
      Navigator(
        key: _navigatorKey,
        pages: buildPages(children, stackPath),
        transitionDelegate: widget.transitionDelegate ?? delegate.transitionDelegate,
        observers: widget.observers,
        onDidRemovePage: (page) => removePage(delegate, scope.childrenPath, page),
      ),
    );
  }

  NavigationState _normalize(NavigationState stack) {
    if (stack.isNotEmpty) return stack;
    final initial = widget.initialState ?? [if (widget.initialRoute case final route?) route.page()];
    return initial.isEmpty ? stack : _withQuery(initial);
  }
}

typedef NestedTabsBuilder = Widget Function(
  BuildContext context,
  Widget child,
  int selectedIndex,
  ValueChanged<int> onTabPressed,
);

/// Shows the nested stack of the enclosing page as tabs, one [Navigator] per tab.
///
/// The first page of the nested stack selects the tab. When the nested stack is empty, the widget
/// sets it to [initialState] or to a page of [initialTab], or of the first tab. When the first page
/// is not a tab, the widget adds that same tab page below it.
///
/// Visited tabs stay mounted in an [IndexedStack], so their pages keep widget state such as
/// scroll positions and form input.
class NestedTabsNavigator extends StatefulWidget {
  const NestedTabsNavigator({
    required this.tabs,
    required this.builder,
    this.initialTab,
    this.initialState,
    this.cacheTabState = true,
    this.clearStackOnDoubleTap = true,
    this.observersBuilder,
    this.transitionDelegate,
    super.key,
  })  : assert(tabs.length > 0, 'Tabs should contain at least 1 route'),
        assert(initialTab == null || initialState == null, 'Provide only one of initialTab or initialState.'),
        assert(initialState == null || initialState.length > 0, 'initialState cannot be empty.');

  final List<Routable> tabs;
  final NestedTabsBuilder builder;
  final Routable? initialTab;
  final NavigationState? initialState;

  /// Keeps the stack and widget state of a tab when another tab is selected.
  final bool cacheTabState;

  /// Resets the selected tab to its first page when it is selected again.
  final bool clearStackOnDoubleTap;

  /// Observers for the navigator of each tab. An observer can belong to one navigator only,
  /// so return a new list for each tab index.
  final List<NavigatorObserver> Function(int tabIndex)? observersBuilder;

  final TransitionDelegate<Object?>? transitionDelegate;

  @override
  State<NestedTabsNavigator> createState() => _NestedTabsNavigatorState();
}

class _NestedTabsNavigatorState extends State<NestedTabsNavigator> with _NestedHostMixin {
  final _navigatorKeys = <int, GlobalKey<NavigatorState>>{};
  final _observers = <int, List<NavigatorObserver>>{};

  /// Last known stack of each visited tab.
  final _stacks = <int, NavigationState>{};
  late int _activeIndex;

  @override
  NavigatorState? get navigator => _navigatorKeys[_activeIndex]?.currentState;

  /// Index of the tab of [NestedTabsNavigator.initialState] or [NestedTabsNavigator.initialTab], or 0.
  int get _initialIndex {
    final tab = widget.initialState?.first.route ?? widget.initialTab;
    final index = tab == null ? -1 : widget.tabs.indexOf(tab);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _activeIndex = _initialIndex;
  }

  void _onTabPressed(int index) {
    final path = stackPath;
    if (index < 0 || index >= widget.tabs.length || path == null) return;

    final NavigationState next;
    if (index == _activeIndex) {
      if (!widget.clearStackOnDoubleTap) return;
      next = _withQuery([widget.tabs[index].page()]);
    } else {
      if (!widget.cacheTabState) _stacks.remove(_activeIndex);
      final cached = _stacks[index];
      next = cached == null ? _withQuery([widget.tabs[index].page()]) : _withQuery(cached, replace: true);
    }
    delegate.change((pages) => pages.updateAt(path, (_) => next));
  }

  /// An empty stack gets the initial stack. A stack that does not start with a tab gets the
  /// initial tab below it, so that a tab is always selected.
  NavigationState _normalize(NavigationState stack) {
    if (stack.isEmpty) return _withQuery(widget.initialState ?? [widget.tabs[_initialIndex].page()]);
    if (widget.tabs.contains(stack.first.route)) return stack;
    return [
      ..._withQuery([widget.tabs[_initialIndex].page()]),
      ...stack
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scopeOf(context, 'NestedTabsNavigator', _normalize);
    final children = scope.page.children ?? const <HelmPage>[];
    final index = children.isEmpty ? -1 : widget.tabs.indexOf(children.first.route);
    if (index >= 0) {
      _activeIndex = index;
      _stacks[index] = children;
    }

    final transitionDelegate = widget.transitionDelegate ?? delegate.transitionDelegate;
    final body = IndexedStack(
      index: _activeIndex,
      children: [
        for (var i = 0; i < widget.tabs.length; i++)
          if (_stacks[i] case final stack? when stack.isNotEmpty)
            TickerMode(
              enabled: i == _activeIndex,
              child: Navigator(
                key: _navigatorKeys.putIfAbsent(i, GlobalKey<NavigatorState>.new),
                pages: buildPages(stack, i == _activeIndex ? stackPath : null),
                transitionDelegate: transitionDelegate,
                observers: _observers.putIfAbsent(i, () => widget.observersBuilder?.call(i) ?? const []),
                onDidRemovePage: (page) => removePage(delegate, i == _activeIndex ? stackPath : null, page),
              ),
            )
          else
            const SizedBox.shrink(),
      ],
    );
    return widget.builder(context, body, _activeIndex, _onTabPressed);
  }
}

/// Registers a nested navigator with the delegate, so that system back can pop it, and fills an
/// empty nested stack.
mixin _NestedHostMixin<T extends StatefulWidget> on State<T> implements NestedHost {
  HelmRouterDelegate? _delegate;
  bool _normalizeScheduled = false;

  HelmRouterDelegate get delegate => _delegate!;

  @override
  StackPath? stackPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = HelmRouter.delegateOf(context);
    if (identical(next, _delegate)) return;
    if (_delegate != null) nestedHosts(_delegate!).remove(this);
    _delegate = next;
    nestedHosts(next).add(this);
  }

  @override
  void dispose() {
    if (_delegate != null) nestedHosts(_delegate!).remove(this);
    super.dispose();
  }

  /// Reads the enclosing page. When its nested stack is null, or [normalize] changes it, for example
  /// to fill an empty stack, sets the result after this frame. [normalize] returns the same list
  /// when the stack is valid. [Router.neglect] makes the URL update replace the current history entry.
  HelmPageScope _scopeOf(
    BuildContext context,
    String widgetName,
    NavigationState Function(NavigationState stack) normalize,
  ) {
    final scope = HelmPageScope.maybeOf(context);
    if (scope == null) throw FlutterError('$widgetName must be inside a page built by Helm.');
    stackPath = scope.childrenPath;

    // A null stack becomes a list too: it marks the page as a host, so a push goes into it.
    final stack = scope.page.children;
    if (stackPath != null && !_normalizeScheduled && (stack == null || !identical(normalize(stack), stack))) {
      _normalizeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _normalizeScheduled = false;
        final path = stackPath;
        if (!mounted || path == null) return;
        Router.neglect(
            context, () => delegate.change((pages) => pages.updateAt(path, (stack) => [...normalize(stack)])));
      });
    }
    return scope;
  }

  /// Sets the current query params on the pages of [stack]. Query params are URL state that all
  /// pages share, so a page that the widget creates or takes from its cache gets them too.
  ///
  /// New pages keep their own query params. With [replace], the pages get only the current query
  /// params, so a cached page drops a key that was removed while it was not shown.
  NavigationState _withQuery(NavigationState stack, {bool replace = false}) {
    final query = delegate.currentQueryParams;
    if (query.isEmpty && !replace) return stack;
    return stack.mapPages((page) {
      final next = replace ? query : {...page.queryParams, ...query};
      return mapEquals(next, page.queryParams) ? page : page.copyWith(queryParams: next);
    });
  }
}
