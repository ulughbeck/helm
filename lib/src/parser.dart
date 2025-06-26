import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';

import 'route.dart';

/// A type alias for a matched route definition with its path and params.
typedef _MatchedRoute = ({Routable route, String matchedPath, Map<String, String> pathParams});

/// Trie node for efficient route matching
class _TrieNode {
  _TrieNode({this.isParameter = false, this.parameterName});

  final Map<String, _TrieNode> children = {};
  final bool isParameter;
  final String? parameterName;
  Routable? route;
  _TrieNode? parameterChild;

  bool get isLeaf => route != null;
}

/// Cached match result for performance
class _CachedMatch {
  const _CachedMatch(this.route, this.pathParams, this.matchedPath);

  final Routable route;
  final Map<String, String> pathParams;
  final String matchedPath;
}

class HelmRouteParser {
  HelmRouteParser(this.routes) {
    _buildTrie();
  }

  final List<Routable> routes;

  final _TrieNode _trieRoot = _TrieNode();
  final LinkedHashMap<String, _CachedMatch?> _matchCache = LinkedHashMap<String, _CachedMatch?>();
  final LinkedHashMap<String, List<String>> _segmentCache = LinkedHashMap<String, List<String>>();
  final LinkedHashMap<String, NavigationState> _parseCache = LinkedHashMap<String, NavigationState>();

  static const int _maxCacheSize = 256;
  static const int _maxParseResults = 100;

  static final RegExp _multipleSlashRegex = RegExp(r'/+');
  static final RegExp _doubleSlashRegex = RegExp(r'//');

  void clearCaches() {
    _matchCache.clear();
    _segmentCache.clear();
    _parseCache.clear();
  }

  void _buildTrie() {
    for (final route in routes) {
      if (route.path == '/') {
        _trieRoot.route = route;
        continue;
      }

      final segments = _getPathSegments(route.path);
      var current = _trieRoot;

      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];

        if (segment.startsWith(':')) {
          final paramName = segment.substring(1);

          current.parameterChild ??= _TrieNode(
            isParameter: true,
            parameterName: paramName,
          );
          current = current.parameterChild!;
        } else {
          current = current.children.putIfAbsent(
            segment,
            _TrieNode.new,
          );
        }
      }

      current.route = route;
    }
  }

  List<String> _getPathSegments(String path) => _segmentCache.putIfAbsent(path, () {
        _evictCacheIfNeeded(_segmentCache);
        final segments = <String>[];
        var start = 0;
        for (var i = 0; i < path.length; i++) {
          if (path[i] == '/') {
            if (i > start) segments.add(path.substring(start, i));
            start = i + 1;
          }
        }
        if (start < path.length) segments.add(path.substring(start));
        return segments;
      });

  void _evictCacheIfNeeded<K, V>(LinkedHashMap<K, V> cache) {
    if (cache.length >= _maxCacheSize) {
      const itemsToRemove = _maxCacheSize ~/ 4;
      final keysToRemove = cache.keys.take(itemsToRemove).toList();
      for (final key in keysToRemove) {
        cache.remove(key);
      }
    }
  }

  _MatchedRoute? _findBestMatch(String path) {
    final cached = _matchCache[path];
    if (cached != null) {
      _matchCache.remove(path);
      _matchCache[path] = cached;
      return (route: cached.route, matchedPath: cached.matchedPath, pathParams: cached.pathParams);
    }

    final pathParams = <String, String>{};
    final result = _trieMatch(_getPathSegments(path), 0, _trieRoot, pathParams, '');

    if (result != null && result.matchedPath == '/' && path != '/') {
      _matchCache[path] = null;
      return null;
    }

    _evictCacheIfNeeded(_matchCache);
    _matchCache[path] = result != null ? _CachedMatch(result.route, result.pathParams, result.matchedPath) : null;

    return result;
  }

  _MatchedRoute? _trieMatch(
    List<String> segments,
    int segmentIndex,
    _TrieNode node,
    Map<String, String> pathParams,
    String matchedPath,
  ) {
    // Base case: If we've consumed all segments from the URI.
    if (segmentIndex >= segments.length) {
      if (node.isLeaf) return (route: node.route!, matchedPath: matchedPath, pathParams: Map.unmodifiable(pathParams));
      return null;
    }

    final currentSegment = segments[segmentIndex];
    final nextSegmentIndex = segmentIndex + 1;
    final currentMatchedPath = matchedPath.isEmpty ? '/$currentSegment' : '$matchedPath/$currentSegment';

    _MatchedRoute? bestMatch;

    // Rule 1: Static routes are more specific and should be checked first.
    final staticChild = node.children[currentSegment];
    if (staticChild != null) {
      final staticMatch = _trieMatch(segments, nextSegmentIndex, staticChild, pathParams, currentMatchedPath);
      if (staticMatch != null) bestMatch = staticMatch;
    }

    // Rule 2: Check for parameterized routes.
    if (node.parameterChild != null) {
      final paramName = node.parameterChild!.parameterName!;
      pathParams[paramName] = currentSegment;
      final paramMatch = _trieMatch(segments, nextSegmentIndex, node.parameterChild!, pathParams, currentMatchedPath);
      pathParams.remove(paramName);

      if (paramMatch != null) {
        if (bestMatch == null || paramMatch.matchedPath.length > bestMatch.matchedPath.length) bestMatch = paramMatch;
      }
    }

    // Rule 3: Check if the current node itself is a leaf. This handles partial matches,
    // e.g., route `/users/:id` when the full path is `/users/123/settings`.
    // The logic must ensure that this partial match is not preferred over a longer, full match.
    if (node.isLeaf) {
      final leafMatch = (
        route: node.route!,
        matchedPath: matchedPath.isEmpty ? '/' : matchedPath,
        pathParams: Map<String, String>.unmodifiable(pathParams)
      );

      if (bestMatch == null || leafMatch.matchedPath.length > bestMatch.matchedPath.length) bestMatch = leafMatch;
    }

    return bestMatch;
  }

  Routable? findParentForRoute(Routable childRoute) {
    final segments = _getPathSegments(childRoute.path);
    if (segments.isEmpty || !segments.last.startsWith(':')) return null;

    final parentSegments = segments.sublist(0, segments.length - 1);
    if (parentSegments.isEmpty) return null;

    final parentPath = parentSegments.length == 1 ? '/${parentSegments[0]}' : '/${parentSegments.join('/')}';

    for (final route in routes) {
      if (route.path == parentPath) return route;
    }
    return null;
  }

  NavigationState parseUri(Uri uri) {
    var path = uri.path.replaceAll(_multipleSlashRegex, '/');

    if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
    if (path.isEmpty) path = '/';

    final cacheKey = uri.query.isEmpty ? path : '$path?${uri.query}';

    final cached = _parseCache[cacheKey];
    if (cached != null) {
      _parseCache.remove(cacheKey);
      _parseCache[cacheKey] = cached;
      return cached;
    }

    final NavigationState result = path == '/' ? _parseRootPath(uri) : _parseComplexPath(path, uri);

    // uncomment if show home page on uknown route initially
    // if (result.isEmpty) return _parseRootPath(uri);

    if (_parseCache.length >= _maxParseResults) {
      final keysToRemove = _parseCache.keys.take(_maxParseResults ~/ 4).toList();
      for (final key in keysToRemove) {
        _parseCache.remove(key);
      }
    }

    _parseCache[cacheKey] = List.unmodifiable(result);
    return result;
  }

  NavigationState _parseRootPath(Uri uri) {
    Routable? homeRoute;

    if (_trieRoot.isLeaf) {
      homeRoute = _trieRoot.route;
    } else if (routes.isNotEmpty) {
      homeRoute = routes.first;
    }

    if (homeRoute == null) return const <Page<Object?>>[];
    return <Page<Object?>>[homeRoute.page(queryParams: uri.queryParameters)];
  }

  NavigationState _parseComplexPath(String path, Uri uri) {
    if (!path.contains('/!') && !path.contains('!/')) return _buildStackFromPath(path, uri.queryParameters);

    final contextStack = <NavigationState>[<Page<Object?>>[]];
    var remainingPath = path;

    while (remainingPath.isNotEmpty) {
      final diveIndex = remainingPath.indexOf('/!');
      final riseIndex = remainingPath.indexOf('!/');

      int delimiterIndex;
      var isDive = false;
      var noMoreDelimiters = false;

      if (diveIndex != -1 && (riseIndex == -1 || diveIndex < riseIndex)) {
        delimiterIndex = diveIndex;
        isDive = true;
      } else if (riseIndex != -1) {
        delimiterIndex = riseIndex;
        isDive = false;
      } else {
        delimiterIndex = remainingPath.length;
        noMoreDelimiters = true;
      }

      final segment = remainingPath.substring(0, delimiterIndex);
      if (segment.isNotEmpty) {
        final pages = _buildStackFromPath(segment, uri.queryParameters);
        contextStack.last.addAll(pages);
      }

      if (noMoreDelimiters) break;

      if (isDive) {
        if (contextStack.last.isEmpty) return const <Page<Object?>>[];
        final parentPage = contextStack.last.last;
        final parentArgs = parentPage.meta;
        if (parentArgs == null) return const <Page<Object?>>[];

        final newChildren = <Page<Object?>>[];
        final newArgs = parentArgs.copyWith(children: () => newChildren);
        final newParentPage = MaterialPage<Object?>(
          key: parentPage.key,
          name: parentPage.name,
          arguments: newArgs,
          child: newArgs.route.builder(newArgs.pathParams, newArgs.queryParams),
        );
        contextStack.last[contextStack.last.length - 1] = newParentPage;
        contextStack.add(newChildren);
      } else {
        if (contextStack.length <= 1) return const <Page<Object?>>[];
        contextStack.removeLast();
      }
      remainingPath = remainingPath.substring(delimiterIndex + 2);
    }

    return contextStack.first;
  }

  NavigationState _buildStackFromPath(String path, Map<String, String> queryParams) {
    final pages = <Page<Object?>>[];
    var remainingPath = path;

    if (remainingPath.isNotEmpty && !remainingPath.startsWith('/')) remainingPath = '/$remainingPath';

    while (remainingPath.isNotEmpty && remainingPath != '/') {
      final bestMatch = _findBestMatch(remainingPath);

      if (bestMatch == null) break;

      final matchedRoute = bestMatch.route;
      final parentRoute = findParentForRoute(matchedRoute);

      if (parentRoute != null) {
        if (pages.isEmpty || (pages.last.meta)?.route != parentRoute) {
          pages.add(parentRoute.page());
        }
      }

      pages.add(matchedRoute.page(pathParams: bestMatch.pathParams, queryParams: queryParams));

      remainingPath = remainingPath.substring(bestMatch.matchedPath.length);
      if (remainingPath.isNotEmpty && !remainingPath.startsWith('/')) remainingPath = '/$remainingPath';
    }

    return pages;
  }

  String? restore(NavigationState pages) {
    if (pages.isEmpty) return null;

    var location = collectPath(pages);
    while (location.endsWith('!/')) {
      location = location.substring(0, location.length - 2);
    }
    if (location.isEmpty) location = '/';

    final allQueryParams = <String, String>{};
    _collectAllQueryParams(pages, allQueryParams);

    if (allQueryParams.isEmpty) return location;

    final uri = Uri(path: location, queryParameters: allQueryParams);
    return uri.toString();
  }

  void _collectAllQueryParams(NavigationState pages, Map<String, String> accumulator) {
    for (final page in pages) {
      final args = page.meta;
      if (args != null) {
        accumulator.addAll(args.queryParams);

        final children = args.children;
        if (children?.isNotEmpty == true) _collectAllQueryParams(children!, accumulator);
      }
    }
  }

  String collectPath(NavigationState pages) {
    if (pages.isEmpty) return '';

    final buffer = StringBuffer();
    var lastPathInThisScope = '';

    for (final page in pages) {
      final args = page.arguments;
      if (args is! $RouteMeta) continue;

      final currentPagePath = args.route.restorePathForRoute(args.pathParams);

      final pathToAppend = (lastPathInThisScope.isNotEmpty &&
              currentPagePath.startsWith(lastPathInThisScope) &&
              currentPagePath != lastPathInThisScope)
          ? currentPagePath.substring(lastPathInThisScope.length)
          : currentPagePath;

      buffer.write(pathToAppend);
      lastPathInThisScope = currentPagePath;

      final children = args.children;
      if (children?.isNotEmpty == true) {
        final childPath = collectPath(children!);
        buffer
          ..write('/!')
          ..write(childPath.startsWith('/') ? childPath.substring(1) : childPath)
          ..write('!/');
      }
    }

    final result = buffer.toString();
    return result.replaceAll(_doubleSlashRegex, '/');
  }

  Map<String, int> getCacheStats() => <String, int>{
        'matchCacheSize': _matchCache.length,
        'segmentCacheSize': _segmentCache.length,
        'parseCacheSize': _parseCache.length,
        'trieNodes': _countTrieNodes(),
      };

  int _countTrieNodes() {
    var count = 0;

    void traverse(_TrieNode node) {
      count++;
      for (final child in node.children.values) {
        traverse(child);
      }
      if (node.parameterChild != null) traverse(node.parameterChild!);
    }

    traverse(_trieRoot);
    return count;
  }
}

class HelmRouteInformationParser extends RouteInformationParser<NavigationState> {
  const HelmRouteInformationParser({required this.routeParser});
  final HelmRouteParser routeParser;

  @override
  Future<NavigationState> parseRouteInformation(RouteInformation routeInformation) {
    final pages = routeParser.parseUri(routeInformation.uri);
    return SynchronousFuture(pages);
  }

  @override
  RouteInformation? restoreRouteInformation(NavigationState configuration) {
    final location = routeParser.restore(configuration);
    if (location == null) return null;
    return RouteInformation(uri: Uri.parse(location));
  }
}
