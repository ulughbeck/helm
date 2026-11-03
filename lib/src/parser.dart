import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'logger.dart';
import 'route.dart';
import 'state.dart';

/// Converts URLs to navigation state and back.
///
/// URL grammar:
/// - `/!` dives into the nested stack of the previous page.
/// - `!/` rises back to the parent stack.
/// - A `~` segment ends a `{name+}` sequence when another route follows in the same stack.
class HelmRouteParser {
  HelmRouteParser(this.routes, {this.logger = const HelmLogger()}) {
    for (final route in routes) {
      _insert(route);
    }
  }

  final List<Routable> routes;
  final HelmLogger logger;
  final _root = _TrieNode();
  final _templates = <Routable, List<_Segment>>{};

  // PARSING

  NavigationState parseUri(Uri uri) {
    final tokens = _tokenize(uri.path);
    final pages = tokens.isEmpty ? _rootStack() : _parseTokens(tokens);
    if (pages.isEmpty) logger.warn('Route "${uri.path}" not found');

    final query = uri.queryParameters;
    if (query.isEmpty) return pages;
    return pages.mapPages((page) => page.copyWith(queryParams: {...page.queryParams, ...query}));
  }

  NavigationState _rootStack() {
    final root = _root.route;
    return root == null ? <HelmPage>[] : [root.page()];
  }

  NavigationState _parseTokens(List<_Token> tokens) {
    final levels = <List<_Draft>>[[]];
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      switch (token.type) {
        case _TokenType.dive:
          final level = levels.last;
          if (level.isEmpty) {
            final root = _root.route;
            if (root == null) {
              logger.warn('Cannot dive into a nested stack: no root route is defined. Ignoring.');
              i++;
              continue;
            }
            level.add(_Draft(root.page()));
          }
          // A dive replaces the initial children of the host page.
          levels.add(level.last.children ??= []);
          i++;
        case _TokenType.rise:
          if (levels.length > 1) {
            levels.removeLast();
          } else {
            logger.warn('Cannot rise from the root stack. Ignoring.');
          }
          i++;
        case _TokenType.terminator:
          logger.warn('Unexpected "~" segment. Ignoring.');
          i++;
        case _TokenType.segment:
          i = _parseBlock(tokens, i, levels.last);
      }
    }
    return [for (final draft in levels.first) draft.build()];
  }

  /// Parses consecutive path segments that start at [start] into [out]. Returns the next token index.
  int _parseBlock(List<_Token> tokens, int start, List<_Draft> out) {
    var end = start;
    while (end < tokens.length && tokens[end].type == _TokenType.segment) {
      end++;
    }
    // Raw, still percent-encoded segments. Pattern segments must match before decoding.
    final segments = [for (var k = start; k < end; k++) tokens[k].value];

    var i = 0;
    while (i < segments.length) {
      final match = _match(segments, i, _root);
      if (match == null || match.end == i) {
        logger.warn('No route matches "/${segments.skip(i).join('/')}". Ignoring.');
        return end;
      }

      final route = match.route;
      final template = _templates[route]!;
      final values = [for (var k = i; k < match.end; k++) template[k - i].valuesOf(segments[k])];
      final params = _paramsFromValues(route, values);
      out
        ..addAll(parentPagesFor(route, pathParams: params).map(_Draft.new))
        ..add(_Draft(route.page(pathParams: params)));
      i = match.end;

      final arbitraryParam = route.arbitraryParam;
      if (arbitraryParam != null) {
        for (; i < segments.length; i++) {
          out.add(_Draft(route.page(pathParams: {arbitraryParam: _decode(segments[i])})));
        }
        if (end < tokens.length && tokens[end].type == _TokenType.terminator) return end + 1;
      }
    }
    return end;
  }

  List<_Token> _tokenize(String path) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < path.length) {
      if (path.startsWith('/!', i)) {
        tokens.add(const _Token(_TokenType.dive));
        i += 2;
      } else if (path.startsWith('!/', i)) {
        tokens.add(const _Token(_TokenType.rise));
        i += 2;
      } else if (path[i] == '/') {
        i++;
      } else {
        final start = i;
        while (i < path.length && path[i] != '/' && !path.startsWith('!/', i)) {
          i++;
        }
        final raw = path.substring(start, i);
        tokens.add(raw == '~' ? const _Token(_TokenType.terminator) : _Token(_TokenType.segment, raw));
      }
    }
    return tokens;
  }

  // RESTORATION

  Uri? restoreUri(NavigationState pages) {
    if (pages.isEmpty) return null;

    var path = _writeStack(pages);
    while (path.endsWith('!/')) {
      path = path.substring(0, path.length - 2);
    }
    if (path.isEmpty) path = '/';

    final query = <String, String>{};
    pages.mapPages((page) {
      query.addAll(page.queryParams);
      return page;
    });
    return Uri(path: path, queryParameters: query.isEmpty ? null : query);
  }

  /// Writes one stack. Every part starts with `/`, so the `!` that closes a nested stack and the
  /// next part form the rise operator `!/`.
  String _writeStack(NavigationState pages) {
    final out = StringBuffer();
    String? prefix;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final previous = i == 0 ? null : pages[i - 1];
      final openSequence = previous != null && previous.route.isArbitrary && !_hasChildren(previous);
      final arbitraryParam = page.route.arbitraryParam;
      if (page.pathParams.containsValue('~')) {
        logger.warn('Path param value "~" of "${page.name}" is reserved by the URL grammar');
      }

      if (openSequence && previous.route == page.route) {
        out.write('/${encodePathSegment(page.pathParams[arbitraryParam]!)}');
      } else {
        if (openSequence) out.write('/~');
        final path = page.route.restorePath(page.pathParams, encode: true);
        if (prefix != null && prefix != '/' && path.startsWith('$prefix/')) {
          // The parser adds the parent page again, so write only the extra segments.
          out.write(path.substring(prefix.length));
        } else if (path != '/') {
          out.write(path);
        }
        prefix = arbitraryParam == null ? path : null;
      }

      if (_hasChildren(page)) {
        final nested = _writeStack(page.children!);
        out
          ..write('/!')
          ..write(nested.startsWith('/') ? nested.substring(1) : nested)
          ..write('!');
        if (i == pages.length - 1) out.write('/');
        prefix = null;
      }
    }
    return out.toString();
  }

  bool _hasChildren(HelmPage page) => page.children?.isNotEmpty ?? false;

  // TRIE

  void _insert(Routable route) {
    final template = _templates[route] = _parseTemplate(route.path);
    var node = _root;
    for (final segment in template) {
      node = switch (segment) {
        _Static(:final text) => node.children.putIfAbsent(text, _TrieNode.new),
        _Param() => node.param ??= _TrieNode(),
        _Pattern(:final shape) => node.patterns.putIfAbsent(shape, () => (pattern: segment, node: _TrieNode())).node,
      };
    }
    node.route = route;
  }

  /// Finds the route that matches the most segments from [index]. On equal length, static
  /// segments win over pattern segments, and pattern segments win over params.
  _Match? _match(List<String> segments, int index, _TrieNode node) {
    if (index == segments.length) return node.route == null ? null : (route: node.route!, end: index);

    final raw = segments[index];
    _Match? best;
    void consider(_TrieNode child) {
      final match = _match(segments, index + 1, child);
      if (match != null && (best == null || match.end > best!.end)) best = match;
    }

    final staticChild = node.children[_decode(raw)];
    if (staticChild != null) consider(staticChild);
    for (final (:pattern, node: child) in node.patterns.values) {
      if (pattern.regex.hasMatch(raw)) consider(child);
    }
    final paramChild = node.param;
    if (paramChild != null) consider(paramChild);

    if (best == null && node.route != null) return (route: node.route!, end: index);
    return best;
  }

  /// Pages of the routes whose paths are prefixes of the path of [route], for example
  /// `/products` for `/products/{pid}`. Parent params take the values at the same positions.
  NavigationState parentPagesFor(
    Routable route, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
  }) {
    final template = _templates[route] ?? _parseTemplate(route.path);
    final values = [
      for (final segment in template) [for (final name in segment.names) pathParams[name]],
    ];
    final pages = <HelmPage>[];
    var node = _root;
    for (var i = 0; i < template.length - 1; i++) {
      final next = switch (template[i]) {
        _Static(:final text) => node.children[text],
        _Param() => node.param,
        _Pattern(:final shape) => node.patterns[shape]?.node,
      };
      if (next == null) break;
      node = next;
      final parent = node.route;
      if (parent != null) {
        pages.add(parent.page(pathParams: _paramsFromValues(parent, values), queryParams: queryParams));
      }
    }
    return pages;
  }

  /// Maps the params of the path of [route] to [values] at the same positions.
  /// [values] holds the param values of each segment, or null when the segment does not match.
  Map<String, String> _paramsFromValues(Routable route, List<List<String?>?> values) {
    final template = _templates[route] ?? _parseTemplate(route.path);
    final params = <String, String>{};
    for (var i = 0; i < template.length && i < values.length; i++) {
      final names = template[i].names;
      final segmentValues = values[i];
      if (segmentValues == null || segmentValues.length != names.length) continue;
      for (var k = 0; k < names.length; k++) {
        if (segmentValues[k] case final value?) params[names[k]] = value;
      }
    }
    return params;
  }
}

/// Connects Flutter's [Router] to [HelmRouteParser].
class HelmRouteInformationParser extends RouteInformationParser<NavigationState> {
  const HelmRouteInformationParser({required this.routeParser});

  final HelmRouteParser routeParser;

  @override
  Future<NavigationState> parseRouteInformation(RouteInformation routeInformation) {
    final pages = routeParser.parseUri(routeInformation.uri);
    routeParser.logger
      ..msg('parsed path: ${routeInformation.uri}')
      ..stack(pages);
    return SynchronousFuture(pages);
  }

  @override
  RouteInformation? restoreRouteInformation(NavigationState configuration) {
    final uri = routeParser.restoreUri(configuration);
    return uri == null ? null : RouteInformation(uri: uri);
  }
}

String _decode(String segment) {
  try {
    return Uri.decodeComponent(segment);
  } on ArgumentError {
    return segment;
  }
}

/// Characters of a percent-encoded param value. Every other character in a pattern segment,
/// such as `@` or `,`, is a literal that a value cannot contain.
const _encodedValueChars = r"A-Za-z0-9\-_.~*'()%";

/// Characters a literal in a pattern segment can use without percent-encoding.
final _literal = RegExp(r"^[A-Za-z0-9\-._~$&'()*+,;=:@]*$");
final _separator = RegExp('[^$_encodedValueChars]');

final _paramToken = RegExp(r'\{(\w+)\+?\}');

List<_Segment> _parseTemplate(String path) => [
      for (final segment in path.split('/'))
        if (segment.isNotEmpty) _Segment.parse(segment),
    ];

/// One segment of a route path template.
sealed class _Segment {
  const _Segment();

  factory _Segment.parse(String segment) {
    final params = _paramToken.allMatches(segment).toList();
    if (params.isEmpty) return _Static(segment);
    if (params.length == 1 && params.single.group(0) == segment) return _Param(params.single.group(1)!);
    return _Pattern.parse(segment, params);
  }

  /// Param names in the order they appear.
  List<String> get names;

  /// Decoded param values of the raw URL [segment], or null when it does not match.
  List<String>? valuesOf(String segment);
}

/// A segment without params, for example `products`.
class _Static extends _Segment {
  const _Static(this.text);

  final String text;

  @override
  List<String> get names => const [];

  @override
  List<String>? valuesOf(String segment) => const [];
}

/// A segment that is one param, for example `{pid}` or `{pid+}`.
class _Param extends _Segment {
  const _Param(this.name);

  final String name;

  @override
  List<String> get names => [name];

  @override
  List<String>? valuesOf(String segment) => [_decode(segment)];
}

/// A segment with params and literal text, for example `@{lat},{lng},{zoom}z`.
class _Pattern extends _Segment {
  _Pattern._(this.names, this.shape, this.regex);

  /// Throws an [ArgumentError] when the values of the params could not be told apart in a URL.
  factory _Pattern.parse(String segment, List<RegExpMatch> params) {
    if (params.any((param) => param.group(0)!.endsWith('+}'))) {
      throw ArgumentError('A "{name+}" param must be a whole path segment: "$segment"');
    }
    final shape = segment.replaceAll(_paramToken, '{}');
    final literals = shape.split('{}');
    if (!literals.every(_literal.hasMatch)) {
      throw ArgumentError('Path segment "$segment" can use only letters, digits and "-._~\$&\'()*+,;=:@" as text');
    }
    for (var i = 1; i < literals.length - 1; i++) {
      if (!_separator.hasMatch(literals[i])) {
        throw ArgumentError(
            'Params in "$segment" need a separator with one of "\$&+,;=:@" between them, for example "{a},{b}"');
      }
    }
    final source = literals.map(RegExp.escape).join('([$_encodedValueChars]+)');
    return _Pattern._([for (final param in params) param.group(1)!], shape, RegExp('^$source\$'));
  }

  @override
  final List<String> names;

  /// The segment without param names, for example `@{},{},{}z`. Routes with the same shape share a trie node.
  final String shape;
  final RegExp regex;

  @override
  List<String>? valuesOf(String segment) {
    final match = regex.firstMatch(segment);
    if (match == null) return null;
    return [for (var i = 1; i <= match.groupCount; i++) _decode(match.group(i)!)];
  }
}

/// A page while the parser builds the tree. [children] is set when the URL dives into the page.
class _Draft {
  _Draft(this.page);

  final HelmPage page;
  List<_Draft>? children;

  HelmPage build() => children == null ? page : page.withChildren([for (final child in children!) child.build()]);
}

enum _TokenType { segment, dive, rise, terminator }

class _Token {
  const _Token(this.type, [this.value = '']);

  final _TokenType type;
  final String value;
}

typedef _Match = ({Routable route, int end});

class _TrieNode {
  final children = <String, _TrieNode>{};
  final patterns = <String, ({_Pattern pattern, _TrieNode node})>{};
  _TrieNode? param;
  Routable? route;
}
