import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';

import 'state.dart';

/// A mixin that defines the contract for a route.
mixin Routable {
  String get path;

  TransitionDelegate<Object?>? get transitionDelegate => null;

  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams);

  @pragma('vm:prefer-inline')
  Page<Object?> build(LocalKey? key, String name, $RouteMeta args) {
    return MaterialPage<Object?>(
      key: key,
      name: name,
      arguments: args,
      child: args.route.builder(args.pathParams, args.queryParams),
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

  bool get isArbitrary => path.contains('+');

  static final RegExp _paramRegex = RegExp(r':\w+');

  String restorePathForRoute(Map<String, String> pathParams) {
    var templatePath = path;
    if (templatePath.contains('+')) {
      templatePath = templatePath.substring(0, templatePath.length - 1);
    }

    if (pathParams.isEmpty) {
      if (kDebugMode && templatePath.contains(':')) _logMissingParams(templatePath);
      return templatePath.contains(':') ? templatePath.replaceAll(_paramRegex, '-') : templatePath;
    }

    var result = templatePath;
    pathParams.forEach((key, value) {
      result = result.replaceFirst(':$key', value);
    });

    if (result.contains(':')) {
      if (kDebugMode) _logMissingParams(result);
      result = result.replaceAll(_paramRegex, '-');
    }

    return result;
  }

  void _logMissingParams(String pathWithParams) {
    final matches = _paramRegex.allMatches(pathWithParams);
    if (matches.isNotEmpty) {
      final missingParams = matches.map((m) => m.group(0)).join(', ');
      log('Route for path "$path" is missing required parameter(s): "$missingParams"', name: 'HelmRouter');
    }
  }
}

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
