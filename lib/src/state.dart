import 'package:flutter/widgets.dart';

import 'route.dart';

/// A type alias for the navigation state, which is a stack of pages representing the current navigation history.
typedef NavigationState = List<Page<Object?>>;

extension $NavigationStateUtils on NavigationState {
  /// returns last page that is equal to route provided
  Page<Object?>? findByRoute(Routable route) {
    for (int i = length - 1; i >= 0; i--) {
      final page = this[i];
      final meta = page.meta;
      // 1. Before checking the current page, dive into its children first.
      final children = meta?.children;
      if (children != null && children.isNotEmpty) {
        final pageFromChildren = children.findByRoute(route);
        if (pageFromChildren != null) return pageFromChildren;
      }
      // 2. If not found in children, check the current page itself.
      if (meta?.route == route) return page;
    }
    return null;
  }

  /// Searches from the deepest, last-active page upwards and removes the
  /// **first** page that matches the provided [route].
  NavigationState removeByRoute(Routable route) {
    ({NavigationState newPages, bool didRemove}) removeFirstRecursive(NavigationState pages, Routable route) {
      for (int i = pages.length - 1; i >= 0; i--) {
        var page = pages[i];
        final meta = page.meta;

        // 1. First, try to remove from the children recursively.
        final children = meta?.children;
        if (children != null && children.isNotEmpty) {
          final result = removeFirstRecursive(children, route);
          if (result.didRemove) {
            // If a child was removed, rebuild the parent page and stop.
            final newMeta = meta!.copyWith(children: () => result.newPages);
            final newPage = meta.route.build(page.key, page.name!, newMeta);
            final newPages = List<Page<Object?>>.from(pages);
            newPages[i] = newPage;
            return (newPages: newPages, didRemove: true);
          }
        }

        // 2. If not in children, check if the current page is a match.
        if (meta?.route == route) {
          final newPages = List<Page<Object?>>.from(pages)..removeAt(i);
          return (newPages: newPages, didRemove: true);
        }
      }

      return (newPages: pages, didRemove: false);
    }

    return removeFirstRecursive(this, route).newPages;
  }

  /// Removes all pages matching the provided [route].
  ///
  /// - if `recursive` is `false` (default): Removes all matching pages from
  ///   the deepest, last-active child stack only.
  /// - if `recursive` is `true`: Removes all matching pages from all levels
  ///   of the entire navigation stack.
  NavigationState removeAllByRoute(Routable route, {bool recursive = false}) {
    NavigationState removeAllRecursive(NavigationState pages, Routable route) {
      final List<Page<Object?>> result = [];
      for (int i = pages.length - 1; i >= 0; i--) {
        var page = pages[i];
        final meta = page.meta;

        if (meta?.route == route) continue;

        final children = meta?.children;
        if (children != null && children.isNotEmpty) {
          final newChildren = removeAllRecursive(children, route);
          if (newChildren.length != children.length) {
            final newMeta = meta!.copyWith(children: () => newChildren);
            page = meta.route.build(page.key, page.name!, newMeta);
          }
        }
        result.insert(0, page);
      }
      return result;
    }

    NavigationState removeInDeepestLastStack(NavigationState pages, Routable route) {
      if (pages.isEmpty) return pages;

      var lastPage = pages.last;
      final meta = lastPage.meta;
      final children = meta?.children;

      if (children != null && children.isNotEmpty) {
        final newChildren = removeInDeepestLastStack(children, route);

        if (newChildren.length != children.length) {
          final newMeta = meta!.copyWith(children: () => newChildren);
          final newLastPage = meta.route.build(lastPage.key, lastPage.name!, newMeta);
          return [...pages.sublist(0, pages.length - 1), newLastPage];
        } else {
          return pages;
        }
      }

      return pages.where((p) => p.meta?.route != route).toList();
    }

    return recursive ? removeAllRecursive(this, route) : removeInDeepestLastStack(this, route);
  }

  String toPrettyString([Uri? initialPath]) {
    final buffer = StringBuffer();
    if (initialPath != null) buffer.writeln('Initial Path: "$initialPath"');
    if (isEmpty) {
      buffer.writeln('Navigation Stack: [EMPTY]');
    } else {
      buffer.writeln('Navigation Stack:');
      _writePages(buffer, this);
    }
    return buffer.toString();
  }

  void _writePages(StringBuffer buffer, NavigationState pages, [String parentPrefix = '']) {
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final meta = page.meta;

      final isFirst = i == 0;
      final isLast = i == pages.length - 1;

      final prefix = switch ((isFirst, isLast, pages.length)) {
        (true, true, _) => '─', // only one item
        (true, false, _) => '┌─', // first item in list
        (false, true, _) => '└─', // last item
        _ => '├─', // middle item
      };

      final childPrefix = parentPrefix + (isLast ? '  ' : '│ ');
      final currentPrefix = parentPrefix + prefix;

      if (meta == null) {
        buffer.writeln('$currentPrefix ${page.name ?? 'Unknown Page'} (No meta)');
        continue;
      }

      final hasChildren = meta.children != null && meta.children!.isNotEmpty;
      final navigatorIndicator = (hasChildren ? ' (Nested Navigator)' : '') + (isFirst ? ' (ROOT)' : '');

      final params = <String, String>{...meta.pathParams, ...meta.queryParams};
      final paramsString =
          params.isNotEmpty ? ' {${params.entries.map((e) => '${e.key}: ${e.value}').join(', ')}}' : '';

      buffer.writeln('$currentPrefix${page.name}$paramsString$navigatorIndicator');

      if (hasChildren) _writePages(buffer, meta.children!, childPrefix);
    }
  }
}
