import 'dart:developer';

import 'package:flutter/widgets.dart';

import 'route.dart';

/// A type alias for the navigation state, which is a stack of pages representing the current navigation history.
typedef NavigationState = List<Page<Object?>>;

extension $NavigationStateUtils on NavigationState {
  /// returns last page that is equal to route provided
  Page<Object?>? findByName(Routable route) {
    try {
      return lastWhere((p) => p.meta!.route == route);
    } catch (_) {
      return null;
    }
  }

  void logNavigationState([Uri? initialPath]) {
    final buffer = StringBuffer();
    if (initialPath != null) buffer.writeln('Initial Path: "$initialPath"');
    if (isEmpty) {
      buffer.writeln('Navigation Stack: [EMPTY]');
    } else {
      buffer.writeln('Navigation Stack:');
      _writePages(buffer, this);
    }
    log(buffer.toString(), name: 'HelmRouter');
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
