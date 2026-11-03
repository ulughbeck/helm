import 'package:flutter/widgets.dart';

import 'state.dart';

/// Describes a route: its URL template, how it is shown, and how it is built.
mixin Routable {
  /// URL template. It must start with `/`.
  ///
  /// Use `{name}` for one segment and `{name+}` for one or more segments.
  String get path;

  PageType get pageType => PageType.material;

  TransitionDelegate<Object?>? get transitionDelegate => null;

  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams);

  /// Creates a page of this route.
  HelmPage page({
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
    NavigationState? children,
  }) =>
      HelmPage(
        route: this,
        pathParams: pathParams,
        queryParams: queryParams,
        children: children,
      );

  /// Whether the path has a `{name+}` parameter.
  bool get isArbitrary => arbitraryParam != null;

  /// Name of the `{name+}` parameter, or null.
  String? get arbitraryParam => _arbitraryParamRegex.firstMatch(path)?.group(1);

  /// Fills the path template with [pathParams].
  ///
  /// Throws an [ArgumentError] when a param is missing or empty, because the page would have
  /// no valid URL. With [encode], values are percent-encoded so that they stay one URL segment.
  String restorePath(Map<String, String> pathParams, {bool encode = false}) =>
      path.replaceAllMapped(_paramRegex, (match) {
        final name = match.group(1)!;
        final value = pathParams[name];
        if (value == null || value.isEmpty) {
          throw ArgumentError.value(pathParams, 'pathParams', 'Route "$path" needs a non-empty value for "$name"');
        }
        return encode ? encodePathSegment(value) : value;
      });
}

final _paramRegex = RegExp(r'\{(\w+)\+?\}');
final _arbitraryParamRegex = RegExp(r'\{(\w+)\+\}');

/// Percent-encodes a path param value. `!` is encoded too because Helm uses it in its URL grammar.
String encodePathSegment(String value) => Uri.encodeComponent(value).replaceAll('!', '%21');

/// Defines how a [Routable] is shown.
enum PageType {
  /// A full-screen page that uses [MaterialPage].
  material,

  /// A full-screen page that uses [CupertinoPage].
  cupertino,

  /// A modal dialog that uses [DialogRoute].
  dialog,

  /// A modal bottom sheet that uses [ModalBottomSheetRoute].
  bottomSheet,
}
