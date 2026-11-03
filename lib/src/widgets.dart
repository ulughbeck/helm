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
    final scope = _scopeOf(context, 'NestedNavigator',
        () => widget.initialState ?? [if (widget.initialRoute case final route?) route.page()]);
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
/// sets it to [initialState] or to a page of [initialTab], or of the first tab.
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

  @override
  void initState() {
    super.initState();
    final initialTab = widget.initialState?.first.route ?? widget.initialTab;
    _activeIndex = initialTab == null ? 0 : widget.tabs.indexOf(initialTab).clamp(0, widget.tabs.length - 1);
  }

  void _onTabPressed(int index) {
    final path = stackPath;
    if (index < 0 || index >= widget.tabs.length || path == null) return;

    final NavigationState next;
    if (index == _activeIndex) {
      if (!widget.clearStackOnDoubleTap) return;
      next = [widget.tabs[index].page()];
    } else {
      if (!widget.cacheTabState) _stacks.remove(_activeIndex);
      next = _stacks[index] ?? [widget.tabs[index].page()];
    }
    delegate.change((pages) => pages.updateAt(path, (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    final scope =
        _scopeOf(context, 'NestedTabsNavigator', () => widget.initialState ?? [widget.tabs[_activeIndex].page()]);
    final children = scope.page.children ?? const <HelmPage>[];
    if (children.isNotEmpty) {
      final index = widget.tabs.indexOf(children.first.route);
      if (index >= 0) _activeIndex = index;
      _stacks[_activeIndex] = children;
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
  bool _fillScheduled = false;

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

  /// Reads the enclosing page. When its nested stack is empty, sets it to [initialStack] after
  /// this frame. [Router.neglect] makes the URL update replace the current history entry.
  HelmPageScope _scopeOf(BuildContext context, String widgetName, NavigationState Function() initialStack) {
    final scope = HelmPageScope.maybeOf(context);
    if (scope == null) throw FlutterError('$widgetName must be inside a page built by Helm.');
    stackPath = scope.childrenPath;

    final isEmpty = scope.page.children?.isEmpty ?? true;
    if (isEmpty && stackPath != null && !_fillScheduled) {
      _fillScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fillScheduled = false;
        final path = stackPath;
        if (!mounted || path == null) return;
        Router.neglect(
          context,
          () => delegate.change((pages) => pages.updateAt(path, (stack) => stack.isEmpty ? initialStack() : stack)),
        );
      });
    }
    return scope;
  }
}
