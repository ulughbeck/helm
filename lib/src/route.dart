import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'logger.dart';
import 'state.dart';

/// A mixin that defines the contract for a route.
mixin Routable {
  String get path;

  PageType get pageType => PageType.material;

  TransitionDelegate<Object?>? get transitionDelegate => null;

  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams);

  @pragma('vm:prefer-inline')
  Page<Object?> build(LocalKey? key, String name, $RouteMeta args) {
    switch (pageType) {
      case PageType.material:
        return MaterialPage<Object?>(
          key: key,
          name: name,
          arguments: args,
          child: args.route.builder(args.pathParams, args.queryParams),
        );
      case PageType.cupertino:
        return CupertinoPage<Object?>(
          key: key,
          name: name,
          arguments: args,
          child: args.route.builder(args.pathParams, args.queryParams),
        );
      case PageType.dialog:
        return $DialogPage<Object?>(
          key: key,
          name: name,
          arguments: args,
          child: args.route.builder(args.pathParams, args.queryParams),
        );
      case PageType.bottomSheet:
        return $BottomSheetPage<Object?>(
          key: key,
          name: name,
          arguments: args,
          child: args.route.builder(args.pathParams, args.queryParams),
        );
    }
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

  bool get isArbitrary => path.contains('+}') && path.contains('{');

  static final RegExp _paramRegex = RegExp(r'\{[^}]+\}');

  String restorePathForRoute(Map<String, String> pathParams) {
    var templatePath = path;

    if (pathParams.isEmpty) {
      if (templatePath.contains('{')) _logMissingParams(templatePath);
      return templatePath.contains('{') ? templatePath.replaceAll(_paramRegex, '-') : templatePath;
    }

    var result = templatePath;
    pathParams.forEach((key, value) {
      result = result.replaceAll(RegExp(r'\{' + key + r'\+?\}'), value);
    });

    if (result.contains('{')) {
      _logMissingParams(result);
      result = result.replaceAll(_paramRegex, '-');
    }

    return result;
  }

  void _logMissingParams(String pathWithParams) {
    final matches = _paramRegex.allMatches(pathWithParams);
    if (matches.isNotEmpty) {
      final missingParams = matches.map((m) => m.group(0)).join(', ');
      HelmLogger.error('Route for path "$path" is missing required parameter(s): "$missingParams"');
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

/// Defines how a [Routable] should be displayed.
enum PageType {
  /// A standard, full-screen page using [MaterialPage].
  material,

  /// A standard, full-screen page using [CupertinoPage].
  cupertino,

  /// A modal dialog using [DialogRoute].
  dialog,

  /// A modal bottom sheet using [ModalBottomSheetRoute].
  bottomSheet,
}

/// A page that displays its [child] as a modal dialog.
class $DialogPage<T> extends Page<T> {
  const $DialogPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return DialogRoute<T>(
      context: context,
      settings: this,
      builder: (BuildContext context) => child,
    );
  }
}

/// A page that displays its [child] as a modal bottom sheet.
class $BottomSheetPage<T> extends Page<T> {
  const $BottomSheetPage({
    required this.child,
    this.isScrollControlled = true,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final Widget child;
  final bool isScrollControlled;

  @override
  Route<T> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<T>(
      settings: this,
      isScrollControlled: isScrollControlled,
      builder: (BuildContext context) => child,
    );
  }
}
