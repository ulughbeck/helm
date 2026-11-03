import 'package:flutter/foundation.dart';

import 'route.dart';

/// The navigation state: the root stack of pages. Pages with [HelmPage.children] hold nested stacks.
typedef NavigationState = List<HelmPage>;

/// One entry of the navigation state. It is an immutable value: two pages with equal
/// route, params, and children are equal.
@immutable
class HelmPage {
  HelmPage({
    required this.route,
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
    NavigationState? children,
  })  : pathParams = Map.unmodifiable(pathParams),
        queryParams = Map.unmodifiable(queryParams),
        children = children == null ? null : List.unmodifiable(children),
        name = route.restorePath(pathParams);

  final Routable route;
  final Map<String, String> pathParams;
  final Map<String, String> queryParams;

  /// Nested stack shown by a [NestedNavigator] or [NestedTabsNavigator] on this page.
  /// Null means the page has no nested stack yet.
  final NavigationState? children;

  /// The route path with path params filled in, for example `/products/123`.
  final String name;

  HelmPage copyWith({Map<String, String>? pathParams, Map<String, String>? queryParams}) => HelmPage(
        route: route,
        pathParams: pathParams ?? this.pathParams,
        queryParams: queryParams ?? this.queryParams,
        children: children,
      );

  HelmPage withChildren(NavigationState? children) =>
      HelmPage(route: route, pathParams: pathParams, queryParams: queryParams, children: children);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HelmPage &&
          other.route == route &&
          mapEquals(other.pathParams, pathParams) &&
          mapEquals(other.queryParams, queryParams) &&
          listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(
        route,
        _mapHash(pathParams),
        _mapHash(queryParams),
        children == null ? null : Object.hashAll(children!),
      );

  @override
  String toString() => 'HelmPage($name)';
}

int _mapHash(Map<String, String> map) => Object.hashAllUnordered(map.entries.map((e) => Object.hash(e.key, e.value)));

extension HelmNavigationState on NavigationState {
  /// Searches from the deepest, last-active page upwards and returns the first page of [route].
  HelmPage? findByRoute(Routable route) {
    for (var i = length - 1; i >= 0; i--) {
      final page = this[i];
      final found = page.children?.findByRoute(route);
      if (found != null) return found;
      if (page.route == route) return page;
    }
    return null;
  }

  /// Searches from the deepest, last-active page upwards and removes the first page of [route].
  NavigationState removeByRoute(Routable route) => _removeFirst(this, route) ?? this;

  /// Removes all pages of [route].
  ///
  /// - `recursive: false` removes them from the deepest active stack only.
  /// - `recursive: true` removes them from every stack.
  NavigationState removeAllByRoute(Routable route, {bool recursive = false}) => recursive
      ? mapPages((page) => page.route == route ? null : page)
      : updateDeepest((stack) => stack.where((page) => page.route != route).toList());

  /// Applies [transform] to every page, children first. Return null to remove a page.
  ///
  /// Unchanged lists and pages keep their identity.
  NavigationState mapPages(HelmPage? Function(HelmPage page) transform) {
    var changed = false;
    final result = <HelmPage>[];
    for (final page in this) {
      var current = page;
      final children = page.children;
      if (children != null) {
        final mapped = children.mapPages(transform);
        if (!identical(mapped, children)) current = page.withChildren(mapped);
      }
      final next = transform(current);
      if (!identical(next, page)) changed = true;
      if (next != null) result.add(next);
    }
    return changed ? result : this;
  }

  /// Indices of the host pages that lead to the deepest active stack.
  ///
  /// The path follows the last page of each stack while that page has children.
  List<int> get deepestPath {
    final path = <int>[];
    NavigationState stack = this;
    while (stack.isNotEmpty && stack.last.children != null) {
      path.add(stack.length - 1);
      stack = stack.last.children!;
    }
    return path;
  }

  /// Replaces the stack at [path] with the result of [update].
  ///
  /// [path] holds the indices of the host pages from the root stack. An empty path is the root stack.
  NavigationState updateAt(List<int> path, NavigationState Function(NavigationState stack) update) {
    if (path.isEmpty) return update(this);
    final index = path.first;
    if (index < 0 || index >= length) return this;
    final host = this[index];
    final children = host.children ?? const <HelmPage>[];
    final updated = children.updateAt(path.sublist(1), update);
    if (identical(updated, children)) return this;
    return [...this]..[index] = host.withChildren(updated);
  }

  /// Replaces the deepest active stack with the result of [update].
  NavigationState updateDeepest(NavigationState Function(NavigationState stack) update) =>
      updateAt(deepestPath, update);

  String get toPrettyString {
    if (isEmpty) return 'navigation stack: (empty)\n';
    final buffer = StringBuffer('navigation stack:\n');
    _writePages(buffer, this, '');
    return buffer.toString();
  }
}

NavigationState? _removeFirst(NavigationState pages, Routable route) {
  for (var i = pages.length - 1; i >= 0; i--) {
    final page = pages[i];
    final children = page.children;
    if (children != null) {
      final updated = _removeFirst(children, route);
      if (updated != null) return [...pages]..[i] = page.withChildren(updated);
    }
    if (page.route == route) return [...pages]..removeAt(i);
  }
  return null;
}

void _writePages(StringBuffer buffer, NavigationState pages, String parentPrefix) {
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final isFirst = i == 0;
    final isLast = i == pages.length - 1;
    final prefix = switch ((isFirst, isLast)) {
      (true, true) => '─',
      (true, false) => '┌─',
      (false, true) => '└─',
      _ => '├─',
    };
    final children = page.children;
    final hasChildren = children != null && children.isNotEmpty;
    final params = {...page.pathParams, ...page.queryParams};
    final paramsString = params.isEmpty ? '' : ' {${params.entries.map((e) => '${e.key}: ${e.value}').join(', ')}}';
    final markers = (hasChildren ? ' (nested navigator)' : '') + (isFirst ? ' (root)' : '');
    buffer.writeln('$parentPrefix$prefix${page.name}$paramsString$markers');
    if (hasChildren) _writePages(buffer, children, parentPrefix + (isLast ? '  ' : '│ '));
  }
}
