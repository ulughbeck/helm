import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'logger.dart';
import 'route.dart';
import 'state.dart';

/// Handles the bidirectional conversion between URL paths and the navigation page stack.
class HelmRouteParser {
  HelmRouteParser(this.routes) {
    _buildTrie();
  }

  final List<Routable> routes;
  final _trieRoot = _TrieNode();
  final _parentStackCache = <String, NavigationState>{};

  static final RegExp _paramNameRegex = RegExp(r'\{(\w+)\+\}');
  static final RegExp _paramNamesRegex = RegExp(r'\{(\w+)\+?\}');
  static final RegExp _pathRegex = RegExp(r'^/+|/+$');

  // TOKENIZATION: Convert String -> Stream of Tokens

  List<_Token> _tokenize(String path) {
    final tokens = <_Token>[];
    int i = 0;
    while (i < path.length) {
      if (path.startsWith('/!', i)) {
        tokens.add(const _Token(_TokenType.dive, '/!'));
        i += 2;
      } else if (path.startsWith('!/', i)) {
        tokens.add(const _Token(_TokenType.rise, '!/'));
        i += 2;
      } else if (path[i] == '~') {
        tokens.add(const _Token(_TokenType.terminator, '~'));
        i += 1;
      } else if (path[i] == '/') {
        i += 1;
      } else {
        // It's a path segment. Read until the next separator or operator.
        final start = i;
        while (i < path.length && !'/!~'.contains(path[i])) {
          i++;
        }
        tokens.add(_Token(_TokenType.pathSegment, path.substring(start, i)));
      }
    }
    return tokens;
  }

  // PARSING: Convert Tokens -> NavigationState

  /// The main public parsing method.
  NavigationState parseUri(Uri uri) {
    if (uri.query.contains('?')) return <Page<Object?>>[];

    final path = uri.path;
    final tokens = _tokenize(path);

    final isRootPath = path.isNotEmpty && path.replaceAll('/', '').isEmpty;
    if (tokens.isEmpty && isRootPath) {
      final rootRoute = _trieRoot.route;
      if (rootRoute == null) return <Page<Object?>>[];
      final page = rootRoute.page(queryParams: uri.queryParameters);
      return [page];
    }

    final contextStack = <NavigationState>[<Page<Object?>>[]];
    int tokenIndex = 0;

    while (tokenIndex < tokens.length) {
      final token = tokens[tokenIndex];
      switch (token.type) {
        case _TokenType.dive:
          _handleDive(contextStack);
          tokenIndex++;
          break;

        case _TokenType.rise:
          _handleRise(contextStack);
          tokenIndex++;
          break;

        case _TokenType.pathSegment:
          final result = _matchPathToPages(tokens, tokenIndex);
          contextStack.last.addAll(result.pages);
          tokenIndex = result.nextTokenIndex;
          break;

        case _TokenType.terminator:
          HelmLogger.error('Warning: Encountered unexpected terminator token. Ignoring.');
          tokenIndex++;
          break;
      }
    }

    if (uri.queryParameters.isNotEmpty) _applyQueryParamsToAll(contextStack.first, uri.queryParameters);
    if (contextStack.first.isEmpty) HelmLogger.error('Route "$path" not found');
    return contextStack.first;
  }

  void _handleDive(List<NavigationState> contextStack) {
    if (contextStack.last.isEmpty) {
      final rootRoute = _trieRoot.route;
      if (rootRoute == null) throw Exception('Cannot dive: no parent page to nest under.');
      contextStack.last.add(rootRoute.page());
    }

    final parentPage = contextStack.last.last;
    final parentMeta = parentPage.meta;
    if (parentMeta == null) throw Exception('Cannot dive: parent page is missing route metadata.');

    final newChildren = <Page<Object?>>[];
    final newMeta = parentMeta.copyWith(children: () => newChildren);

    contextStack.last[contextStack.last.length - 1] = parentMeta.route.build(parentPage.key, parentPage.name!, newMeta);
    contextStack.add(newChildren);
  }

  void _handleRise(List<NavigationState> contextStack) {
    if (contextStack.length <= 1) throw Exception('Cannot rise: already at the root of the navigation stack.');
    contextStack.removeLast();
  }

  ({NavigationState pages, int nextTokenIndex}) _matchPathToPages(List<_Token> tokens, int startIndex) {
    final pages = <Page<Object?>>[];
    int currentIndex = startIndex;

    while (currentIndex < tokens.length && tokens[currentIndex].type == _TokenType.pathSegment) {
      // 1. Get the list of remaining path segments to match against.
      final remainingSegments =
          tokens.sublist(currentIndex).takeWhile((t) => t.type == _TokenType.pathSegment).map((t) => t.value).toList();

      if (remainingSegments.isEmpty) break;

      // 2. Find the best match for the start of the remaining path segments.
      final bestMatch = _findBestMatch(remainingSegments, 0, _trieRoot);

      if (bestMatch == null || bestMatch.segmentsConsumed == 0) {
        int endOfBlockIndex = currentIndex;
        while (endOfBlockIndex < tokens.length && tokens[endOfBlockIndex].type == _TokenType.pathSegment) {
          endOfBlockIndex++;
        }
        currentIndex = endOfBlockIndex;
        break;
      }

      final matchedRoute = bestMatch.route;
      final params = bestMatch.pathParams;
      final consumedCount = bestMatch.segmentsConsumed;
      final matchedSegments = remainingSegments.sublist(0, consumedCount);

      // 3. Add any implicit parent routes for the first matched segment.
      pages.addAll(findParentPages(matchedSegments, params));

      // 4. Add the matched page itself.
      pages.add(matchedRoute.page(pathParams: params));

      // 5. Advance the main `currentIndex` by the number of segments the match consumed.
      currentIndex += consumedCount;

      // 6. Handle arbitrary routes.
      if (matchedRoute.isArbitrary) {
        final paramName = _paramNameRegex.firstMatch(matchedRoute.path)!.group(1)!;
        while (currentIndex < tokens.length && tokens[currentIndex].type == _TokenType.pathSegment) {
          final segmentValue = tokens[currentIndex].value;
          pages.add(matchedRoute.page(pathParams: {paramName: segmentValue}));
          currentIndex++;
        }

        if (currentIndex < tokens.length && tokens[currentIndex].type == _TokenType.terminator) {
          currentIndex++;
        }
      }
    }
    return (pages: pages, nextTokenIndex: currentIndex);
  }

  void _applyQueryParamsToAll(NavigationState pages, Map<String, String> queryParams) {
    if (queryParams.isEmpty) return;

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final meta = page.meta;

      if (meta != null) {
        final newMeta = meta.copyWith(queryParams: {...meta.queryParams, ...queryParams});
        pages[i] = meta.route.build(page.key, page.name!, newMeta);
        if (meta.children != null) _applyQueryParamsToAll(meta.children!, queryParams);
      }
    }
  }

  // URL RESTORATION: Convert NavigationState -> String

  /// The main public restoration method.
  Uri? restoreUri(NavigationState configuration) {
    if (configuration.isEmpty) return null;

    final internalPath = _restoreInternal(configuration);
    String cleanPath = internalPath;

    // 1. First, remove all "rise" operators from the path.
    while (cleanPath.endsWith('!/')) {
      cleanPath = cleanPath.substring(0, cleanPath.length - 2);
    }

    // 2. After the above replacements, a trailing slash might be left. Remove it.
    if (cleanPath.length > 1 && cleanPath.endsWith('/')) {
      cleanPath = cleanPath.substring(0, cleanPath.length - 1);
    }

    // 3. Finally, handle the terminator and the root path edge case.
    cleanPath = cleanPath.replaceAll('~', '');
    if (cleanPath.isEmpty) cleanPath = '/';

    final allQueryParams = <String, String>{};
    _collectAllQueryParams(configuration, allQueryParams);

    return Uri(path: cleanPath, queryParameters: allQueryParams.isEmpty ? null : allQueryParams);
  }

  String _restoreInternal(NavigationState pages) {
    final buffer = StringBuffer();
    String lastRestoredPath = '';
    Routable? lastRoute;
    bool inArbitrarySequence = false;

    for (final page in pages) {
      final meta = page.meta;
      if (meta == null) continue;

      final currentRoute = meta.route;
      final isArbitrary = currentRoute.isArbitrary;

      if (inArbitrarySequence && isArbitrary && currentRoute.path == lastRoute?.path) {
        final paramName = _paramNameRegex.firstMatch(currentRoute.path)!.group(1)!;
        final paramValue = meta.pathParams[paramName];
        if (paramValue != null) buffer.write('/$paramValue');
        lastRestoredPath = '';
      } else {
        if (inArbitrarySequence) buffer.write('~');

        final restoredPath = currentRoute.restorePathForRoute(meta.pathParams);
        final isRootPageWithChildren = restoredPath == '/' && meta.children != null && meta.children!.isNotEmpty;

        if (!isRootPageWithChildren) {
          if (lastRestoredPath.isNotEmpty &&
              restoredPath.startsWith(lastRestoredPath) &&
              restoredPath.length > lastRestoredPath.length) {
            final diff = restoredPath.substring(lastRestoredPath.length);
            buffer.write(diff);
          } else {
            var pathSegmentToWrite = restoredPath;
            if (buffer.isNotEmpty && buffer.toString().endsWith('/') && pathSegmentToWrite.startsWith('/')) {
              pathSegmentToWrite = pathSegmentToWrite.substring(1);
            }
            buffer.write(pathSegmentToWrite);
          }
          lastRestoredPath = restoredPath;
        }
      }

      lastRoute = currentRoute;
      inArbitrarySequence = isArbitrary;

      if (meta.children != null && meta.children!.isNotEmpty) {
        if (inArbitrarySequence) {
          buffer.write('~');
          inArbitrarySequence = false;
        }
        buffer.write('/!');
        var childPath = _restoreInternal(meta.children!);
        if (childPath.startsWith('/')) childPath = childPath.substring(1);
        buffer.write(childPath);
        buffer.write('!/');
        lastRestoredPath = '';
        lastRoute = null;
      }
    }
    return buffer.toString();
  }

  void _collectAllQueryParams(NavigationState pages, Map<String, String> accumulator) {
    for (final page in pages) {
      final meta = page.meta;
      if (meta != null) {
        accumulator.addAll(meta.queryParams);
        if (meta.children != null) {
          _collectAllQueryParams(meta.children!, accumulator);
        }
      }
    }
  }

  // TRIE

  void _buildTrie() {
    for (final route in routes) {
      if (route.path == '/') {
        _trieRoot.route = route;
        continue;
      }

      var current = _trieRoot;
      final segments = route.path.replaceAll(_pathRegex, '').split('/');

      for (final segment in segments) {
        if (segment.startsWith('{') && segment.endsWith('}')) {
          var paramName = segment.substring(1, segment.length - 1);
          var isArbitrary = false;
          if (paramName.endsWith('+')) {
            paramName = paramName.substring(0, paramName.length - 1);
            isArbitrary = true;
          }
          current.parameterChild ??= _TrieNode();
          current = current.parameterChild!;
          current.parameterName = paramName;
          current.isArbitrary = isArbitrary;
        } else {
          current = current.children.putIfAbsent(segment, () => _TrieNode());
        }
      }
      current.route = route;
    }
  }

  _TrieMatch? _findBestMatch(
    List<String> segments,
    int index,
    _TrieNode node, [
    Map<String, String> currentParams = const {},
  ]) {
    if (index >= segments.length) {
      return node.route != null ? (route: node.route!, pathParams: currentParams, segmentsConsumed: index) : null;
    }

    final segment = segments[index];
    _TrieMatch? staticMatch;
    _TrieMatch? paramMatch;

    // Rule 1: Static routes are more specific, check them first.
    if (node.children.containsKey(segment)) {
      staticMatch = _findBestMatch(segments, index + 1, node.children[segment]!, currentParams);
    }

    // Rule 2: Check for parameterized routes.
    if (node.parameterChild != null) {
      final paramName = node.parameterChild!.parameterName!;
      final newParams = {...currentParams, paramName: segment};
      paramMatch = _findBestMatch(segments, index + 1, node.parameterChild!, newParams);
    }

    // Prefer static over dynamic if both match.
    if (staticMatch != null && paramMatch != null) {
      return staticMatch.segmentsConsumed >= paramMatch.segmentsConsumed ? staticMatch : paramMatch;
    }

    final bestMatch = staticMatch ?? paramMatch;

    // Rule 3: If no deeper match, check if the current node is a valid endpoint.
    if (node.route != null && bestMatch == null) {
      return (route: node.route!, pathParams: currentParams, segmentsConsumed: index);
    }

    return bestMatch;
  }

  // HELPERS

  NavigationState findParentPages(List<String> segments, Map<String, String> params) {
    final pages = <Page<Object?>>[];
    _TrieNode currentNode = _trieRoot;

    for (int i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      if (currentNode.children.containsKey(segment)) {
        currentNode = currentNode.children[segment]!;
      } else if (currentNode.parameterChild != null) {
        currentNode = currentNode.parameterChild!;
      } else {
        break;
      }

      if (currentNode.route != null) {
        final parentParams = <String, String>{};
        final paramName = currentNode.parameterName;
        if (paramName != null && params.containsKey(paramName)) {
          parentParams[paramName] = params[paramName]!;
        }
        pages.add(currentNode.route!.page(pathParams: parentParams));
      }
    }
    return pages;
  }

  NavigationState _applyParamsToPages(
    NavigationState pages,
    Map<String, String> queryParams,
    Map<String, String> pathParams,
  ) {
    return pages.map((page) {
      final meta = page.meta;
      if (meta == null) return page;

      final newPathParams = <String, String>{};
      final requiredParamNames = _paramNamesRegex.allMatches(meta.route.path).map((m) => m.group(1)!);

      for (final paramName in requiredParamNames) {
        if (pathParams.containsKey(paramName)) {
          newPathParams[paramName] = pathParams[paramName]!;
        }
      }

      final pathParamsChanged = !mapEquals(meta.pathParams, newPathParams);
      final queryParamsChanged = !mapEquals(meta.queryParams, queryParams);

      if (!pathParamsChanged && !queryParamsChanged) return page;

      final newMeta = meta.copyWith(pathParams: newPathParams, queryParams: queryParams);
      return meta.route.build(page.key, page.name!, newMeta);
    }).toList();
  }

  NavigationState getParentStackFor(
    Routable route, {
    Map<String, String> pathParams = const {},
    Map<String, String> queryParams = const {},
  }) {
    String path = route.path;

    if (_parentStackCache.containsKey(path)) {
      final cachedPages = _parentStackCache[path]!;
      return _applyParamsToPages(cachedPages, queryParams, pathParams);
    }

    if (path == '/') return <Page<Object?>>[];

    // Normalize path and get its definition segments
    path = path.replaceAll(_pathRegex, '');
    if (path.endsWith('+')) path = path.substring(0, path.length - 1);

    final segments = path.split('/');

    final pages = <Page<Object?>>[];
    _TrieNode currentNode = _trieRoot;

    // Traverse the Trie using the route's *definition* segments
    for (int i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];

      if (segment.startsWith('{') && segment.endsWith('}')) {
        if (currentNode.parameterChild == null) break;
        currentNode = currentNode.parameterChild!;
      } else {
        if (!currentNode.children.containsKey(segment)) break;
        currentNode = currentNode.children[segment]!;
      }

      // If the node we landed on represents a complete route, it's a parent.
      if (currentNode.route != null) {
        final parentParams = <String, String>{};
        final parentRoutePath = currentNode.route!.path;
        final parentParamNames = _paramNamesRegex.allMatches(parentRoutePath).map((m) => m.group(1)!).toSet();

        for (final paramName in parentParamNames) {
          if (pathParams.containsKey(paramName)) parentParams[paramName] = pathParams[paramName]!;
        }
        pages.add(currentNode.route!.page(pathParams: parentParams, queryParams: queryParams));
      }
    }

    _parentStackCache[path] = pages;
    return pages;
  }
}

/// A `RouteInformationParser` that bridges Flutter's routing system with `HelmRouteParser`.
class HelmRouteInformationParser extends RouteInformationParser<NavigationState> {
  const HelmRouteInformationParser({required this.routeParser});
  final HelmRouteParser routeParser;

  @override
  Future<NavigationState> parseRouteInformation(RouteInformation routeInformation) {
    try {
      final pages = routeParser.parseUri(routeInformation.uri);
      HelmLogger.msg('initial path: ${routeInformation.uri}');
      if (HelmLogger.logStack) HelmLogger.msg(pages.toPrettyString);
      return SynchronousFuture(pages);
    } catch (e, s) {
      HelmLogger.error('Error parsing URI "${routeInformation.uri}": $e\n$s');
      return SynchronousFuture(<Page<Object?>>[]);
    }
  }

  @override
  RouteInformation? restoreRouteInformation(NavigationState configuration) {
    final uri = routeParser.restoreUri(configuration);
    return uri != null ? RouteInformation(uri: uri) : null;
  }
}

/// Represents the logical units of a URL path.
enum _TokenType {
  /// A normal path segment, like "products" or "123".
  pathSegment,

  /// The dive operator: `/!`.
  dive,

  /// The rise operator: `!/`.
  rise,

  /// The arbitrary sequence terminator: `~`.
  terminator,
}

/// A token represents a single logical unit of a URL path.
class _Token {
  const _Token(this.type, this.value);
  final _TokenType type;
  final String value;
  @override
  String toString() => 'Token(${type.name}, "$value")';
}

/// A matched route definition with its path and params.
typedef _TrieMatch = ({Routable route, Map<String, String> pathParams, int segmentsConsumed});

/// Trie node for efficient route matching.
class _TrieNode {
  final Map<String, _TrieNode> children = {};
  _TrieNode? parameterChild;
  Routable? route;
  String? parameterName;
  bool isArbitrary = false;
}
