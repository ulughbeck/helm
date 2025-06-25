import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';

/// A type alias for the navigation state, which is a stack of pages representing the current navigation history.
typedef NavigationState = List<Page<Object?>>;

/// A data class holding all arguments for a given page.
class $RouteMeta {
  $RouteMeta({
    required this.route,
    this.pathParams = const {},
    this.queryParams = const {},
    this.children,
  });

  final Routable route;
  final Map<String, String> pathParams;
  final Map<String, String> queryParams;
  final NavigationState? children;

  $RouteMeta copyWith({
    Routable? route,
    Map<String, String>? pathParams,
    Map<String, String>? queryParams,
    ValueGetter<NavigationState?>? children,
  }) =>
      $RouteMeta(
        route: route ?? this.route,
        pathParams: pathParams ?? this.pathParams,
        queryParams: queryParams ?? this.queryParams,
        children: children != null ? children() : this.children,
      );
}

extension $PageRouteMeta on Page<Object?> {
  $RouteMeta? get meta {
    final args = arguments;
    if (args is $RouteMeta) return args;
    return null;
  }
}

/// A mixin that defines the contract for a route.
mixin Routable {
  String get path;

  TransitionDelegate<Object?>? get transitionDelegate => null;

  Widget builder(
    Map<String, String> pathParams,
    Map<String, String> queryParams,
  );

  Page<Object?> build(LocalKey? key, String name, $RouteMeta args) {
    return MaterialPage<Object?>(
      key: key,
      name: name,
      arguments: args,
      child: builder(args.pathParams, args.queryParams),
    );
  }

  Page<Object?> page({
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
    NavigationState? children,
    LocalKey? key,
  }) {
    final args = $RouteMeta(
      route: this,
      pathParams: pathParams,
      queryParams: queryParams,
      children: children,
    );
    final name = restorePathForRoute(pathParams);
    return build(key, name, args);
  }

  String restorePathForRoute(Map<String, String> pathParams) {
    var result = path;
    pathParams.forEach((key, value) {
      result = result.replaceFirst(':$key', value);
    });

    if (result.contains(':')) {
      if (kDebugMode) {
        final missingParams = RegExp(r':(\w+)').allMatches(result).map((m) => m.group(0)).join(', ');
        log('Warning: Route for path "$path" is missing required parameter(s): "$missingParams"');
      }
      result = result.replaceAll(RegExp(r':\w+'), '-');
    }

    return result;
  }
}
