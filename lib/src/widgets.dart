import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'route.dart';
import 'router.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final delegate = HelmRouter.delegateOf(context);
        final parentArgs = ModalRoute.of(context)!.settings.arguments as $RouteMeta?;
        if (parentArgs?.children == null) {
          final parentRoute = ModalRoute.of(context);
          if (parentRoute == null) return;
          final parentRouteName = parentRoute.settings.name;
          if (parentRouteName == null) {
            if (kDebugMode) log('Warning: Parent route name is null in NestedNavigator');
            return;
          }

          if (widget.initialRoute != null) {
            delegate.setInitialNestedRoute(parentRouteName, [widget.initialRoute!.page()]);
          } else if (widget.initialState != null) {
            delegate.setInitialNestedRoute(parentRouteName, widget.initialState!);
          } else {
            delegate.prepareNestedNavigator(parentRouteName);
          }
        }
      } catch (e) {
        if (kDebugMode) log('Error initializing NestedNavigator: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: HelmRouter.delegateOf(context),
        builder: (context, child) {
          try {
            final parentArgs = ModalRoute.of(context)!.settings.arguments as $RouteMeta?;
            if (parentArgs == null) {
              if (kDebugMode) log('Warning: Parent args is null in NestedNavigator');
              return widget.builder(context, const SizedBox.shrink());
            }
            final nestedPages = parentArgs.children ?? [];

            if (nestedPages.isEmpty) return widget.builder(context, const SizedBox.shrink());
            return widget.builder(
              context,
              Navigator(
                key: ValueKey(nestedPages.map((p) => p.name).join(',')),
                pages: nestedPages,
                onDidRemovePage: (page) => HelmRouter.pop(context),
              ),
            );
          } catch (e) {
            if (kDebugMode) log('Error building NestedNavigator: $e');
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
  final Map<Routable, NavigationState> _tabStacks = {};
  late int _activeIndex;
  bool _isInitializing = false;

  @override
  void initState() {
    assert(
      widget.initialTab == null || widget.tabs.contains(widget.initialTab),
      'The initialTab must be one of the routes provided in the tabs list',
    );
    super.initState();

    for (final tab in widget.tabs) {
      _tabStacks[tab] = [tab.page()];
    }
    _activeIndex = widget.initialTab != null ? widget.tabs.indexOf(widget.initialTab!) : 0;
    if (_activeIndex == -1) _activeIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isInitializing) return;
      _isInitializing = true;

      try {
        final delegate = HelmRouter.delegateOf(context);
        final parentArgs = ModalRoute.of(context)?.settings.arguments as $RouteMeta?;
        if (parentArgs == null || parentArgs.children == null || parentArgs.children!.isEmpty) {
          final parentName = ModalRoute.of(context)?.settings.name;
          if (parentName != null) {
            final initialTab = widget.tabs[_activeIndex];
            delegate.replaceNestedStack(parentName, [initialTab.page()]);
          }
        }
      } catch (e) {
        if (kDebugMode) log('Error initializing NestedTabsNavigator: $e');
      } finally {
        _isInitializing = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final delegate = HelmRouter.delegateOf(context);
    return AnimatedBuilder(
      animation: delegate,
      builder: (context, child) {
        try {
          final parentRoute = ModalRoute.of(context);
          final parentArgs = ModalRoute.of(context)!.settings.arguments as $RouteMeta?;

          if (parentArgs == null) {
            if (kDebugMode) log('Warning: Parent args is null in NestedTabsNavigator');
            return const SizedBox.shrink();
          }

          final nestedPages = parentArgs.children ?? [];

          if (nestedPages.isEmpty) {
            if (!_isInitializing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isInitializing) {
                  _isInitializing = true;
                  final currentArgs = parentRoute?.settings.arguments as $RouteMeta?;
                  if (currentArgs?.children?.isEmpty ?? true) {
                    final parentName = parentRoute?.settings.name;
                    if (parentName != null && _activeIndex < widget.tabs.length) {
                      final tabToReset = widget.tabs[_activeIndex];
                      delegate.replaceNestedStack(parentName, [tabToReset.page()]);
                    }
                  }
                  _isInitializing = false;
                }
              });
            }
            return const SizedBox.shrink();
          }

          int calculateActiveIndex() {
            if (nestedPages.isEmpty) return 0;
            final firstPageName = nestedPages.first.name;
            final index = widget.tabs.indexWhere((tab) => tab.path == firstPageName);
            return index != -1 ? index : 0;
          }

          _activeIndex = calculateActiveIndex();

          void onPressed(int newIndex) {
            if (newIndex < 0 || newIndex >= widget.tabs.length) return;
            final parentName = parentRoute?.settings.name;
            if (parentName == null) return;

            final newTabRoute = widget.tabs[newIndex];

            if (_activeIndex == newIndex) {
              if (widget.cacheTabState) {
                final existingStack = _tabStacks[newTabRoute];
                if (widget.clearStackOnDoubleTap) {
                  final freshStack = [newTabRoute.page()];
                  _tabStacks[newTabRoute] = freshStack;
                  delegate.replaceNestedStack(parentName, freshStack);
                } else if (existingStack != null) {
                  delegate.replaceNestedStack(parentName, existingStack);
                }
              }
              return;
            }

            if (widget.cacheTabState && _activeIndex < widget.tabs.length) {
              final currentTabRoute = widget.tabs[_activeIndex];
              _tabStacks[currentTabRoute] = nestedPages;
            }

            final restoredStack = _tabStacks[newTabRoute] ?? [newTabRoute.page()];
            delegate.replaceNestedStack(parentName, restoredStack);
          }

          return widget.builder(
            context,
            Navigator(
              key: ValueKey(nestedPages.map((p) => p.name).join(',')),
              pages: nestedPages,
              onDidRemovePage: (page) => HelmRouter.pop(context),
            ),
            _activeIndex,
            onPressed,
          );
        } catch (e) {
          if (kDebugMode) log('Error building NestedTabsNavigator: $e');
          return const SizedBox.shrink();
        }
      },
    );
  }
}
