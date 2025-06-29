import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'route.dart';
import 'router.dart';
import 'state.dart';

class NestedNavigator extends StatefulWidget {
  const NestedNavigator({
    required this.builder,
    super.key,
    this.initialRoute,
    this.initialState,
  }) : assert(
          !(initialRoute != null && initialState != null),
          'Only one of initialRoute or initialState should be provided, not both.',
        );

  final Routable? initialRoute;
  final NavigationState? initialState;
  final Widget Function(BuildContext context, Widget child) builder;

  @override
  State<NestedNavigator> createState() => _NestedNavigatorState();
}

class _NestedNavigatorState extends State<NestedNavigator> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_initializeNavigator);
  }

  @pragma('vm:prefer-inline')
  void _initializeNavigator(Duration _) {
    if (!mounted || _initialized) return;
    _initialized = true;

    try {
      final delegate = HelmRouter.delegateOf(context);
      final parentRoute = ModalRoute.of(context);
      if (parentRoute == null) return;

      final parentArgs = parentRoute.settings.arguments;
      if (parentArgs is! $RouteMeta || parentArgs.children != null) return;

      final parentRouteName = parentRoute.settings.name;
      if (parentRouteName == null) {
        if (kDebugMode) log('Warning: Parent route name is null in NestedNavigator', name: 'HelmRouter');
        return;
      }

      final initialRoute = widget.initialRoute;
      final initialState = widget.initialState;

      if (initialRoute != null) {
        delegate.setInitialNestedRoute(parentRouteName, [initialRoute.page()]);
      } else if (initialState != null) {
        delegate.setInitialNestedRoute(parentRouteName, initialState);
      } else {
        delegate.prepareNestedNavigator(parentRouteName);
      }
    } catch (e) {
      if (kDebugMode) log('Error initializing NestedNavigator: $e', name: 'HelmRouter');
    }
  }

  @pragma('vm:prefer-inline')
  void _onDidRemovePage(Page<Object?> page) => HelmRouter.pop(context);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: HelmRouter.delegateOf(context),
        builder: (context, child) {
          try {
            final parentRoute = ModalRoute.of(context);
            if (parentRoute == null) {
              if (kDebugMode) log('Warning: Parent route is null in NestedNavigator');
              return widget.builder(context, const SizedBox.shrink());
            }

            final parentArgs = parentRoute.settings.arguments;
            if (parentArgs is! $RouteMeta) {
              if (kDebugMode) log('Warning: Parent args is null in NestedNavigator');
              return widget.builder(context, const SizedBox.shrink());
            }

            final nestedPages = parentArgs.children;
            if (nestedPages == null || nestedPages.isEmpty) {
              return widget.builder(context, const SizedBox.shrink());
            }

            final keyBuffer = StringBuffer();
            for (var i = 0; i < nestedPages.length; i++) {
              if (i > 0) keyBuffer.write(',');
              keyBuffer.write(nestedPages[i].name);
            }

            return widget.builder(
              context,
              Navigator(
                key: ValueKey(keyBuffer.toString()),
                pages: nestedPages,
                onDidRemovePage: _onDidRemovePage,
              ),
            );
          } catch (e) {
            if (kDebugMode) log('Error building NestedNavigator: $e', name: 'HelmRouter');
            return widget.builder(context, const SizedBox.shrink());
          }
        },
      );
}

typedef NestedTabsBuilder = Widget Function(
  BuildContext context,
  Widget child,
  int selectedIndex,
  ValueChanged<int> onTabPressed,
);

class NestedTabsNavigator extends StatefulWidget {
  const NestedTabsNavigator({
    required this.tabs,
    required this.builder,
    this.initialTab,
    this.initialState,
    this.cacheTabState = true,
    this.clearStackOnDoubleTap = true,
    super.key,
  })  : assert(tabs.length > 0, 'Tabs should contain at least 1 route'),
        assert(
          !(initialTab != null && initialState != null),
          'Only one of initialTab or initialState should be provided, not both.',
        );

  final NavigationState? initialState;
  final Routable? initialTab;
  final List<Routable> tabs;
  final NestedTabsBuilder builder;
  final bool cacheTabState;
  final bool clearStackOnDoubleTap;

  @override
  State<NestedTabsNavigator> createState() => _NestedTabsNavigatorState();
}

class _NestedTabsNavigatorState extends State<NestedTabsNavigator> {
  late final Map<Routable, NavigationState> _tabStacks;
  late final Map<String, int> _pathToIndexCache;
  late int _activeIndex;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();

    final initialTab = widget.initialTab;
    if (initialTab != null) {
      assert(
        widget.tabs.contains(initialTab),
        'The initialTab must be one of the routes provided in the tabs list',
      );
    }

    _tabStacks = <Routable, NavigationState>{};
    _pathToIndexCache = <String, int>{};

    final tabs = widget.tabs;
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      _tabStacks[tab] = [tab.page()];
      _pathToIndexCache[tab.path] = i;
    }

    _activeIndex = initialTab != null ? _pathToIndexCache[initialTab.path] ?? 0 : 0;

    WidgetsBinding.instance.addPostFrameCallback(_initializeTabNavigator);
  }

  @pragma('vm:prefer-inline')
  void _initializeTabNavigator(Duration _) {
    if (!mounted || _isInitializing) return;
    _isInitializing = true;

    try {
      final delegate = HelmRouter.delegateOf(context);
      final parentRoute = ModalRoute.of(context);
      final parentArgs = parentRoute?.settings.arguments;

      if (parentArgs is! $RouteMeta || (parentArgs.children != null && parentArgs.children!.isNotEmpty)) {
        return;
      }

      final parentName = parentRoute?.settings.name;
      if (parentName != null && _activeIndex < widget.tabs.length) {
        final initialState = widget.initialState;
        if (initialState != null && initialState.isNotEmpty) {
          _activeIndex = _calculateActiveIndex(initialState);
          delegate.replaceNestedStack(parentName, initialState);
          return;
        }

        final initialTab = widget.tabs[_activeIndex];
        delegate.replaceNestedStack(parentName, [initialTab.page()]);
      }
    } catch (e) {
      if (kDebugMode) log('Error initializing NestedTabsNavigator: $e', name: 'HelmRouter');
    } finally {
      _isInitializing = false;
    }
  }

  @pragma('vm:prefer-inline')
  int _calculateActiveIndex(NavigationState nestedPages) {
    if (nestedPages.isEmpty) return 0;
    final firstPageName = nestedPages.first.name;
    return firstPageName != null ? (_pathToIndexCache[firstPageName] ?? 0) : 0;
  }

  void _onTabPressed(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.tabs.length) return;

    final parentRoute = ModalRoute.of(context);
    final parentName = parentRoute?.settings.name;
    if (parentName == null) return;

    final newTabRoute = widget.tabs[newIndex];

    // Handle same tab selection
    if (_activeIndex == newIndex) {
      if (!widget.clearStackOnDoubleTap) return;
      final delegate = HelmRouter.delegateOf(context);
      delegate.replaceNestedStack(parentName, [newTabRoute.page()]);
      return;
    }

    final delegate = HelmRouter.delegateOf(context);
    final parentArgs = parentRoute?.settings.arguments;

    // Cache current tab state if enabled
    if (widget.cacheTabState && _activeIndex < widget.tabs.length && parentArgs is $RouteMeta) {
      final currentTabRoute = widget.tabs[_activeIndex];
      final nestedPages = parentArgs.children;
      if (nestedPages != null) _tabStacks[currentTabRoute] = nestedPages;
    }

    // Switch to new tab
    final restoredStack = _tabStacks[newTabRoute] ?? [newTabRoute.page()];
    delegate.replaceNestedStack(parentName, restoredStack);
  }

  @pragma('vm:prefer-inline')
  void _onDidRemoveTabPage(Page<Object?> page) => HelmRouter.pop(context);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: HelmRouter.delegateOf(context),
        builder: (context, child) {
          try {
            final parentRoute = ModalRoute.of(context);
            final parentArgs = parentRoute?.settings.arguments;

            if (parentArgs is! $RouteMeta) {
              if (kDebugMode) log('Warning: Parent args is null in NestedTabsNavigator', name: 'HelmRouter');
              return const SizedBox.shrink();
            }

            final nestedPages = parentArgs.children;

            if (nestedPages == null || nestedPages.isEmpty) {
              // Handle empty state with post-frame callback for initialization
              if (!_isInitializing) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _isInitializing) return;
                  _isInitializing = true;

                  try {
                    final currentArgs = parentRoute?.settings.arguments;
                    if (currentArgs is $RouteMeta && (currentArgs.children?.isEmpty ?? true)) {
                      final parentName = parentRoute?.settings.name;
                      if (parentName != null && _activeIndex < widget.tabs.length) {
                        final tabToReset = widget.tabs[_activeIndex];
                        final delegate = HelmRouter.delegateOf(context);
                        delegate.replaceNestedStack(parentName, [tabToReset.page()]);
                      }
                    }
                  } finally {
                    _isInitializing = false;
                  }
                });
              }
              return widget.builder(context, const SizedBox.shrink(), _activeIndex, _onTabPressed);
            }

            _activeIndex = _calculateActiveIndex(nestedPages);

            final keyBuffer = StringBuffer();
            for (var i = 0; i < nestedPages.length; i++) {
              if (i > 0) keyBuffer.write(',');
              keyBuffer.write(nestedPages[i].name);
            }

            return widget.builder(
              context,
              Navigator(
                key: ValueKey(keyBuffer.toString()),
                pages: nestedPages,
                onDidRemovePage: _onDidRemoveTabPage,
              ),
              _activeIndex,
              _onTabPressed,
            );
          } catch (e) {
            if (kDebugMode) log('Error building NestedTabsNavigator: $e', name: 'HelmRouter');
            return widget.builder(context, const SizedBox.shrink(), _activeIndex, _onTabPressed);
          }
        },
      );
}
