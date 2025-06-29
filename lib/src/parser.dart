import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'route.dart';
import 'state.dart';

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

class HelmRouteParser {
  HelmRouteParser(this.routes) {
    _buildTrie();
  }

  final List<Routable> routes;
  final _TrieNode _trieRoot = _TrieNode();

  // ---------------------------------------------------------------------------
  // TOKENIZATION: Convert String -> Stream of Tokens
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // PARSING: Convert Tokens -> NavigationState
  // ---------------------------------------------------------------------------

  /// The main public parsing method.
  NavigationState parseUri(Uri uri) {
    if (uri.query.contains('?')) return [];

    final path = uri.path;
    final tokens = _tokenize(path);

    final isRootPath = path.isNotEmpty && path.replaceAll('/', '').isEmpty;
    if (tokens.isEmpty && isRootPath) {
      final rootRoute = _trieRoot.route;
      if (rootRoute == null) return [];
      final page = rootRoute.page(queryParams: uri.queryParameters);
      return [page];
    }

    final contextStack = <NavigationState>[<Page>[]];
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
          // Terminators are handled within _matchPathToPages,
          // seeing one here means it's likely misplaced.
          log('Warning: Encountered unexpected terminator token. Ignoring.', name: 'HelmRouter');
          tokenIndex++;
          break;
      }
    }

    if (uri.queryParameters.isNotEmpty) _applyQueryParamsToAll(contextStack.first, uri.queryParameters);
    return contextStack.first;
  }

  void _handleDive(List<NavigationState> contextStack) {
    if (contextStack.last.isEmpty) {
      // If the path starts with `/!`, we assume it's nested under the root.
      final rootRoute = _trieRoot.route;
      if (rootRoute == null) {
        throw Exception('Cannot dive: no parent page to nest under and no root ("/") route defined.');
      }
      contextStack.last.add(rootRoute.page());
    }

    final parentPage = contextStack.last.last;
    final parentMeta = parentPage.meta;
    if (parentMeta == null) throw Exception('Cannot dive: parent page is missing route metadata.');

    final newChildren = <Page<Object?>>[];
    final newMeta = parentMeta.copyWith(children: () => newChildren);

    // Replace the parent page with a new one containing the children reference.
    contextStack.last[contextStack.last.length - 1] = parentMeta.route.build(
      parentPage.key,
      parentPage.name!,
      newMeta,
    );

    // The new context for parsing is the children list.
    contextStack.add(newChildren);
  }

  void _handleRise(List<NavigationState> contextStack) {
    if (contextStack.length <= 1) throw Exception('Cannot rise: already at the root of the navigation stack.');
    contextStack.removeLast();
  }
// In class HelmRouteParser

  ({NavigationState pages, int nextTokenIndex}) _matchPathToPages(List<_Token> tokens, int startIndex) {
    final pages = <Page>[];
    int currentIndex = startIndex;

    while (currentIndex < tokens.length && tokens[currentIndex].type == _TokenType.pathSegment) {
      // 1. Get the list of remaining path segments to match against without advancing the main index.
      final remainingSegments =
          tokens.sublist(currentIndex).takeWhile((t) => t.type == _TokenType.pathSegment).map((t) => t.value).toList();

      // Should not happen due to the while loop condition, but safe to have.
      if (remainingSegments.isEmpty) break;

      // 2. Find the best match for the start of the remaining path segments.
      final bestMatch = _findBestMatch(remainingSegments, 0, _trieRoot);

      if (bestMatch == null || bestMatch.segmentsConsumed == 0) {
        int endOfBlockIndex = currentIndex;
        while (endOfBlockIndex < tokens.length && tokens[endOfBlockIndex].type == _TokenType.pathSegment) {
          endOfBlockIndex++;
        }
        currentIndex = endOfBlockIndex;

        // Break the loop to return whatever pages we have found so far.
        break;
      }

      final matchedRoute = bestMatch.route;
      final params = bestMatch.pathParams;
      final consumedCount = bestMatch.segmentsConsumed;
      final matchedSegments = remainingSegments.sublist(0, consumedCount);

      // 3. Handle Implicit Parent Routes by looking at the segments we consumed.
      pages.addAll(findParentPages(matchedSegments, params));

      // 4. Add the matched page itself.
      pages.add(matchedRoute.page(pathParams: params));

      // 5. Advance the main `currentIndex` by the number of segments the match consumed.
      //    Since we now guard against consumedCount == 0, this is always safe.
      currentIndex += consumedCount;

      // 6. Handle Arbitrary (+) Routes
      if (matchedRoute.path.endsWith('+')) {
        final paramName = RegExp(r':(\w+)\+').firstMatch(matchedRoute.path)!.group(1)!;
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

    // Iterate through all pages at the current navigation level.
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final meta = page.meta;

      if (meta != null) {
        // Create new metadata for the page, merging the existing query params with the new ones.
        final newMeta = meta.copyWith(queryParams: {...meta.queryParams, ...queryParams});

        // Rebuild the page with the updated metadata.
        pages[i] = meta.route.build(page.key, page.name!, newMeta);

        // If this page contains a nested navigator, recurse into its children.
        if (meta.children != null) _applyQueryParamsToAll(meta.children!, queryParams);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // URL RESTORATION: Convert NavigationState -> String
  // ---------------------------------------------------------------------------

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

    if (kDebugMode) log('Inner Path: $internalPath', name: 'HelmRouter');
    if (kDebugMode) log('Final Path: $cleanPath', name: 'HelmRouter');
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
      final isArbitrary = currentRoute.path.endsWith('+');

      // Check for end of an arbitrary sequence
      if (inArbitrarySequence && currentRoute != lastRoute) {
        buffer.write('~');
        inArbitrarySequence = false;
      }

      // Handle continuation of an arbitrary sequence
      if (inArbitrarySequence && currentRoute == lastRoute) {
        final paramName = RegExp(r':(\w+)\+').firstMatch(currentRoute.path)!.group(1)!;
        final paramValue = meta.pathParams[paramName];
        if (paramValue != null) buffer.write('/$paramValue');
      } else {
        // Handle a regular page or the first page in a sequence
        final restoredPath = currentRoute.restorePathForRoute(meta.pathParams);
        final isRootPageWithChildren = restoredPath == '/' && meta.children != null && meta.children!.isNotEmpty;

        if (!isRootPageWithChildren) {
          // This is the corrected logic block
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
          // Update the last path to the full path of the route we just processed.
          lastRestoredPath = restoredPath;
        }
      }

      lastRoute = currentRoute;
      inArbitrarySequence = isArbitrary;

      // Handle children recursively
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

  // ---------------------------------------------------------------------------
  // TRIE & MATCHING HELPERS
  // ---------------------------------------------------------------------------

  void _buildTrie() {
    for (final route in routes) {
      if (route.path == '/') {
        _trieRoot.route = route;
        continue;
      }

      var current = _trieRoot;
      final segments = route.path.replaceAll(RegExp(r'^/+|/+$'), '').split('/');

      for (final segment in segments) {
        if (segment.startsWith(':')) {
          var paramName = segment.substring(1);
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

  NavigationState findParentPages(List<String> segments, Map<String, String> params) {
    final pages = <Page>[];
    _TrieNode currentNode = _trieRoot;

    for (int i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      if (currentNode.children.containsKey(segment)) {
        currentNode = currentNode.children[segment]!;
      } else if (currentNode.parameterChild != null) {
        currentNode = currentNode.parameterChild!;
      } else {
        break; // Should not happen for a valid match
      }

      if (currentNode.route != null) {
        final parentParams = <String, String>{};
        final paramName = currentNode.parameterName;
        if (paramName != null && params.containsKey(paramName)) {
          // This logic assumes parent route params are a subset of child params
          parentParams[paramName] = params[paramName]!;
        }
        pages.add(currentNode.route!.page(pathParams: parentParams));
      }
    }
    return pages;
  }

  NavigationState getParentStackFor(Routable route, Map<String, String> pathParams) {
    String path = route.path;
    if (path == '/') return [];

    // Normalize path and get its definition segments (e.g., ['users', ':userId'])
    path = path.replaceAll(RegExp(r'^/+|/+$'), '');
    if (path.endsWith('+')) path = path.substring(0, path.length - 1);

    final segments = path.split('/');

    final pages = <Page>[];
    _TrieNode currentNode = _trieRoot;

    // Traverse the Trie using the route's *definition* segments
    for (int i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];

      if (segment.startsWith(':')) {
        if (currentNode.parameterChild == null) break;
        currentNode = currentNode.parameterChild!;
      } else {
        if (!currentNode.children.containsKey(segment)) break;
        currentNode = currentNode.children[segment]!;
      }

      // If the node we landed on represents a complete route, it's a parent.
      if (currentNode.route != null) {
        // Create the parent page, extracting only the params it needs
        // from the full set of params provided for the child route.
        final parentParams = <String, String>{};
        final parentRoutePath = currentNode.route!.path;
        final parentParamNames = RegExp(r':(\w+)').allMatches(parentRoutePath).map((m) => m.group(1)!).toSet();

        for (final paramName in parentParamNames) {
          if (pathParams.containsKey(paramName)) parentParams[paramName] = pathParams[paramName]!;
        }
        pages.add(currentNode.route!.page(pathParams: parentParams));
      }
    }
    return pages;
  }
}

class HelmRouteInformationParser extends RouteInformationParser<NavigationState> {
  const HelmRouteInformationParser({required this.routeParser});
  final HelmRouteParser routeParser;

  @override
  Future<NavigationState> parseRouteInformation(RouteInformation routeInformation) {
    final pages = routeParser.parseUri(routeInformation.uri);
    if (kDebugMode) pages.logNavigationState(routeInformation.uri);
    return SynchronousFuture(pages);
  }

  @override
  RouteInformation? restoreRouteInformation(NavigationState configuration) {
    final uri = routeParser.restoreUri(configuration);
    return uri != null ? RouteInformation(uri: uri) : null;
  }
}
