import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';
import 'package:helm/src/parser.dart';

void main() {
  final parser = HelmRouteParser(_ParserRoutes.values);

  String? roundTrip(String url) => parser.restoreUri(parser.parseUri(Uri.parse(url)))?.toString();

  group('HelmRouteParser round trips', () {
    test('nested URLs', () {
      expect(roundTrip('/category/laptops/!settings'), '/category/laptops/!settings');
    });

    test('arbitrary multi-segment URLs', () {
      expect(roundTrip('/products/123/456/789'), '/products/123/456/789');
    });

    test('nested URLs with query params', () {
      final restored = parser.restoreUri(parser.parseUri(Uri.parse('/shop/!settings?tab=info&sort=asc')))!;
      expect(restored.path, '/shop/!settings');
      expect(restored.queryParameters, {'tab': 'info', 'sort': 'asc'});
    });

    test('state with an arbitrary sequence followed by another route', () {
      final state = [
        _ParserRoutes.products.page(),
        _ParserRoutes.product.page(pathParams: {'pid': '1'}),
        _ParserRoutes.product.page(pathParams: {'pid': '2'}),
        _ParserRoutes.settings.page(),
      ];

      final uri = parser.restoreUri(state)!;
      expect(uri.toString(), '/products/1/2/~/settings');
      expect(parser.parseUri(uri), state);
    });

    test('state with a sibling route after a nested stack', () {
      final state = [
        _ParserRoutes.shop.page(children: [
          _ParserRoutes.category.page(pathParams: {'cid': 'laptops'})
        ]),
        _ParserRoutes.settings.page(),
      ];

      final uri = parser.restoreUri(state)!;
      expect(uri.toString(), '/shop/!category/laptops!/settings');
      expect(parser.parseUri(uri), state);
    });

    test('path params with reserved characters', () {
      final state = [
        _ParserRoutes.category.page(pathParams: {'cid': 'a b/c!d~'})
      ];

      final uri = parser.restoreUri(state)!;
      expect(uri.path, '/category/a%20b%2Fc%21d~');
      expect(parser.parseUri(Uri.parse(uri.toString())).single.pathParams, {'cid': 'a b/c!d~'});
    });

    test('parsing the same URL twice gives equal state', () {
      const url = '/shop/!category/laptops!/products/1/2?q=x';
      expect(parser.parseUri(Uri.parse(url)), parser.parseUri(Uri.parse(url)));
    });
  });

  group('Path params', () {
    test('a missing or empty param throws', () {
      expect(() => _ParserRoutes.category.page(), throwsArgumentError);
      expect(() => _ParserRoutes.category.page(pathParams: {'cid': ''}), throwsArgumentError);
      expect(() => _ParserRoutes.product.page(), throwsArgumentError);
    });
  });

  group('Pattern segments', () {
    test('several params in one segment round trip', () {
      const url = '/map/@41.31,69.24,12z';
      final page = parser.parseUri(Uri.parse(url)).last;
      expect(page.route, _ParserRoutes.mapPoint);
      expect(page.pathParams, {'lat': '41.31', 'lng': '69.24', 'zoom': '12'});
      expect(roundTrip(url), url);
    });

    test('values with separator characters are encoded', () {
      final state = [
        _ParserRoutes.mapPoint.page(pathParams: {'lat': 'a,b', 'lng': '@', 'zoom': '1z'})
      ];
      final uri = parser.restoreUri(state)!;
      expect(uri.path, '/map/@a%2Cb,%40,1zz');
      expect(parser.parseUri(Uri.parse(uri.toString())).last.pathParams, state.single.pathParams);
    });

    test('a pattern segment wins over a param segment', () {
      expect(parser.parseUri(Uri.parse('/category/@1,2')).last.route, _ParserRoutes.categoryPoint);
      expect(parser.parseUri(Uri.parse('/category/laptops')).last.route, _ParserRoutes.category);
    });

    test('a pattern segment works at the root', () {
      final pages = parser.parseUri(Uri.parse('/@x,y'));
      expect(pages.single.route, _ParserRoutes.place);
      expect(pages.single.pathParams, {'a': 'x', 'b': 'y'});
    });

    test('parent pages get pattern params by position', () {
      final pages = parser.parseUri(Uri.parse('/map/@1,2,3z/info'));
      expect(pages.map((p) => p.name), ['/map', '/map/@1,2,3z', '/map/@1,2,3z/info']);
    });

    test('a segment that does not fit the pattern does not match', () {
      final pages = parser.parseUri(Uri.parse('/map/@1'));
      expect(pages.map((p) => p.route), [_ParserRoutes.map]);
    });

    test('templates whose values cannot be told apart are rejected', () {
      for (final path in ['/x/{a}{b}', '/x/{a}-{b}', '/x/@{a+}', '/x/{a}%{b}', '/x/@{a}{', '/x/{a} {b}']) {
        expect(() => HelmRouteParser([_PathRoute(path)]), throwsArgumentError, reason: path);
      }
      expect(() => HelmRouteParser([_PathRoute('/x/{a};{b}.json')]), returnsNormally);
    });
  });

  group('HelmRouteParser parents', () {
    test('parent pages keep earlier params', () {
      final pages = parser.parseUri(Uri.parse('/category/x/items/5'));
      expect(pages.map((p) => p.name), ['/category/x', '/category/x/items', '/category/x/items/5']);
    });

    test('a page without a dive has no children', () {
      expect(parser.parseUri(Uri.parse('/shop')).single.children, isNull);
    });

    test('a dive sets the children of the previous page', () {
      final pages = parser.parseUri(Uri.parse('/shop/!category/x'));
      expect(pages.single.children!.map((p) => p.name), ['/category/x']);
    });
  });

  group('HelmRouteParser query params', () {
    test('restores query params as global URL state', () {
      final state = [
        _ParserRoutes.shop.page(queryParams: const {'tab': 'featured', 'q': 'laptop'}),
        _ParserRoutes.settings.page(queryParams: const {'tab': 'details'}),
      ];

      final restored = parser.restoreUri(state)!;
      expect(restored.path, '/shop/settings');
      expect(restored.queryParameters, {'tab': 'details', 'q': 'laptop'});
    });

    test('accepts "?" inside the query', () {
      final pages = parser.parseUri(Uri.parse('/settings?q=a%3Fb'));
      expect(pages.single.queryParams, {'q': 'a?b'});
    });
  });

  group('HelmRouteParser malformed grammar', () {
    test('a lone "!" does not hang', () {
      expect(parser.parseUri(Uri.parse('/settings!')), isEmpty);
      expect(parser.parseUri(Uri.parse('/a!b/settings')), isEmpty);
    });

    test('ignores unexpected rise at root', () {
      final pages = parser.parseUri(Uri.parse('/settings!/'));
      expect(pages.last.route, _ParserRoutes.settings);
    });

    test('ignores dive when no root route exists', () {
      final pages = HelmRouteParser(_NoRootRoutes.values).parseUri(Uri.parse('/!settings'));
      expect(pages.single.route, _NoRootRoutes.settings);
    });
  });

  group('NavigationState helpers', () {
    final deep = [
      _ParserRoutes.root.page(children: [
        _ParserRoutes.shop.page(children: [_ParserRoutes.settings.page(), _ParserRoutes.products.page()]),
      ]),
    ];

    test('removeAllByRoute removes pages two levels deep', () {
      final recursive = deep.removeAllByRoute(_ParserRoutes.settings, recursive: true);
      expect(recursive.findByRoute(_ParserRoutes.settings), isNull);

      final deepest = deep.removeAllByRoute(_ParserRoutes.settings);
      expect(deepest.findByRoute(_ParserRoutes.settings), isNull);
      expect(deepest.findByRoute(_ParserRoutes.products), isNotNull);
    });

    test('removeByRoute removes the deepest match', () {
      final result = deep.removeByRoute(_ParserRoutes.products);
      expect(result.single.children!.single.children, [_ParserRoutes.settings.page()]);
    });

    test('mapPages keeps identity when nothing changes', () {
      expect(identical(deep.mapPages((page) => page), deep), isTrue);
    });
  });
}

enum _ParserRoutes with Routable {
  root,
  shop,
  categories,
  category,
  items,
  item,
  settings,
  products,
  product,
  categoryPoint,
  place,
  map,
  mapPoint,
  mapInfo;

  @override
  String get path => switch (this) {
        _ParserRoutes.categoryPoint => '/category/@{x},{y}',
        _ParserRoutes.place => '/@{a},{b}',
        _ParserRoutes.map => '/map',
        _ParserRoutes.mapPoint => '/map/@{lat},{lng},{zoom}z',
        _ParserRoutes.mapInfo => '/map/@{lat},{lng},{zoom}z/info',
        _ParserRoutes.root => '/',
        _ParserRoutes.shop => '/shop',
        _ParserRoutes.categories => '/categories',
        _ParserRoutes.category => '/category/{cid}',
        _ParserRoutes.items => '/category/{cid}/items',
        _ParserRoutes.item => '/category/{cid}/items/{iid}',
        _ParserRoutes.settings => '/settings',
        _ParserRoutes.products => '/products',
        _ParserRoutes.product => '/products/{pid+}',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => const SizedBox.shrink();
}

class _PathRoute with Routable {
  _PathRoute(this.path);

  @override
  final String path;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => const SizedBox.shrink();
}

enum _NoRootRoutes with Routable {
  settings;

  @override
  String get path => '/settings';

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => const SizedBox.shrink();
}
