import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';

/// A type alias for the navigation state, which is a stack of pages representing the current navigation history.
typedef NavigationState = List<Page<Object?>>;

/// A data class holding all arguments for a given page.
class $RouteMeta {
  const $RouteMeta({
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
    return args is $RouteMeta ? args : null;
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

  @pragma('vm:prefer-inline')
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

  static final Map<String, RegExp> _paramRegexCache = <String, RegExp>{};
  static final Map<String, List<String>> _pathParamCache = <String, List<String>>{};

  String restorePathForRoute(Map<String, String> pathParams) {
    // Early exit if no parameters to replace
    if (pathParams.isEmpty) {
      if (kDebugMode && path.contains(':')) _logMissingParams(path);
      return path.contains(':') ? path.replaceAll(_getParamRegex(path), '-') : path;
    }

    var result = path;

    // Use cached parameter list for this path if available
    final cachedParams = _pathParamCache[path];
    if (cachedParams != null) {
      for (final param in cachedParams) {
        final value = pathParams[param];
        if (value != null) result = result.replaceFirst(':$param', value);
      }
    } else {
      final paramNames = <String>[];
      pathParams.forEach((key, value) {
        final paramPattern = ':$key';
        if (result.contains(paramPattern)) {
          result = result.replaceFirst(paramPattern, value);
          paramNames.add(key);
        }
      });
      _pathParamCache[path] = paramNames;
    }

    // Handle any remaining unreplaced parameters
    if (result.contains(':')) {
      if (kDebugMode) _logMissingParams(result);
      result = result.replaceAll(_getParamRegex(path), '-');
    }

    return result;
  }

  RegExp _getParamRegex(String path) => _paramRegexCache.putIfAbsent(path, () => RegExp(r':\w+'));

  void _logMissingParams(String pathWithParams) {
    final matches = _getParamRegex(pathWithParams).allMatches(pathWithParams);
    if (matches.isNotEmpty) {
      final missingParams = matches.map((m) => m.group(0)).join(', ');
      log('Warning: Route for path "$path" is missing required parameter(s): "$missingParams"');
    }
  }

  // String restorePathForRoute(Map<String, String> pathParams) {
  //   var result = path;
  //   pathParams.forEach((key, value) {
  //     result = result.replaceFirst(':$key', value);
  //   });

  //   if (result.contains(':')) {
  //     if (kDebugMode) {
  //       final missingParams = RegExp(r':(\w+)').allMatches(result).map((m) => m.group(0)).join(', ');
  //       log('Warning: Route for path "$path" is missing required parameter(s): "$missingParams"');
  //     }
  //     result = result.replaceAll(RegExp(r':\w+'), '-');
  //   }

  //   return result;
  // }
}
