import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

// Tests for NestedTabsNavigator. The apps below are small shops:
// - `/` is a home screen with a button that pushes the shop.
// - `/shop` is the tab shell. Its tabs are feed, search and profile by default.

void main() {
  group('filling the first tab', () {
    testWidgets('the first tab is selected by default and the URL gets its stack', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.feed.page()])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed');
      expect(_tabIndex(tester), 0);
      expect(find.text('Feed screen'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/feed'],
      ]);
    });

    testWidgets('initialTab selects another tab when the stack is empty', (tester) async {
      final app = _ShopApp(initialTab: _Screen.search);
      final router = await _pump(tester, app.routes, url: '/shop');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.search.page()])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search');
      expect(_tabIndex(tester), 1);
      expect(find.text('Search screen'), findsOneWidget);
    });

    testWidgets('initialState fills a tab with a deeper stack', (tester) async {
      final result = _Screen.result.page(pathParams: {'q': 'dart'});
      final app = _ShopApp(initialState: [_Screen.search.page(), result]);
      final router = await _pump(tester, app.routes, url: '/shop');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.search.page(), result])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/dart');
      expect(_tabIndex(tester), 1);
      expect(find.text('Result dart'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/search', '/search/results/dart'],
      ]);
    });

    testWidgets('a deep link wins over initialTab', (tester) async {
      final app = _ShopApp(initialTab: _Screen.search);
      final router = await _pump(tester, app.routes, url: '/shop/!profile');

      expect(router.delegate.currentUri.toString(), '/shop/!profile');
      expect(_tabIndex(tester), 2);
    });

    testWidgets('pushing the shop from home fills the first tab', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes);
      expect(find.text('Home screen'), findsOneWidget);

      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.home.page(),
        app.shell.page(children: [_Screen.feed.page()]),
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed');
      expect(find.text('Feed screen'), findsOneWidget);
    });

    testWidgets('filling replaces the history entry and a push adds one', (tester) async {
      final app = _ShopApp();
      final reports = <(String, bool)>[];
      await _pump(tester, app.routes, url: '/shop', reports: reports);
      // The platform URL is reported back, then the tabs widget adds the first tab. Both replace.
      expect(reports.map((r) => r.$2), everyElement(isTrue));
      expect(reports.last.$1, '/shop/!feed');

      reports.clear();
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      expect(reports, [('/shop/!feed/post/1', false)]);
    });

    test('invalid constructor arguments are rejected', () {
      Widget build(BuildContext context, Widget child, int index, ValueChanged<int> onTap) => child;
      expect(() => NestedTabsNavigator(tabs: const [], builder: build), throwsAssertionError);
      expect(
        () => NestedTabsNavigator(
          tabs: const [_Screen.feed],
          initialTab: _Screen.feed,
          initialState: [_Screen.feed.page()],
          builder: build,
        ),
        throwsAssertionError,
      );
      expect(
        () => NestedTabsNavigator(tabs: const [_Screen.feed], initialState: const [], builder: build),
        throwsAssertionError,
      );
    });
  });

  group('deep links', () {
    // URL -> tree, selected tab and the pages of each onstage Navigator.
    final cases = <({
      String name,
      String url,
      String? restored,
      NavigationState Function(_ShopApp app) tree,
      int tab,
      List<List<String>> navigators,
      String text,
    })>[
      (
        name: 'the second tab',
        url: '/shop/!search',
        restored: null,
        tree: (app) => [
              app.shell.page(children: [_Screen.search.page()])
            ],
        tab: 1,
        navigators: [
          ['/shop'],
          ['/search'],
        ],
        text: 'Search screen',
      ),
      (
        name: 'the last tab',
        url: '/shop/!profile',
        restored: null,
        tree: (app) => [
              app.shell.page(children: [_Screen.profile.page()])
            ],
        tab: 2,
        navigators: [
          ['/shop'],
          ['/profile'],
        ],
        text: 'Profile screen',
      ),
      (
        name: 'a tab with a page on top of it',
        url: '/shop/!search/post/5',
        restored: null,
        tree: (app) => [
              app.shell.page(children: [
                _Screen.search.page(),
                _Screen.post.page(pathParams: {'id': '5'}),
              ])
            ],
        tab: 1,
        navigators: [
          ['/shop'],
          ['/search', '/post/5'],
        ],
        text: 'Post 5',
      ),
      (
        name: 'a nested page with a path param adds its parent page',
        url: '/shop/!search/results/dart',
        restored: null,
        tree: (app) => [
              app.shell.page(children: [
                _Screen.search.page(),
                _Screen.result.page(pathParams: {'q': 'dart'}),
              ])
            ],
        tab: 1,
        navigators: [
          ['/shop'],
          ['/search', '/search/results/dart'],
        ],
        text: 'Result dart',
      ),
      (
        name: 'a tab with two pages of the same route on top of it',
        url: '/shop/!feed/post/1/post/2',
        restored: null,
        tree: (app) => [
              app.shell.page(children: [
                _Screen.feed.page(),
                _Screen.post.page(pathParams: {'id': '1'}),
                _Screen.post.page(pathParams: {'id': '2'}),
              ])
            ],
        tab: 0,
        navigators: [
          ['/shop'],
          ['/feed', '/post/1', '/post/2'],
        ],
        text: 'Post 2',
      ),
    ];

    for (final c in cases) {
      testWidgets(c.name, (tester) async {
        final app = _ShopApp();
        final router = await _pump(tester, app.routes, url: c.url);

        expect(router.delegate.currentConfiguration, c.tree(app));
        expect(router.delegate.currentUri.toString(), c.restored ?? c.url);
        expect(_tabIndex(tester), c.tab);
        expect(find.text(c.text), findsOneWidget);
        expect(_navigators(tester), c.navigators);
      });
    }

    testWidgets('the shell above the home page', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/!shop/!search');

      expect(router.delegate.currentConfiguration, [
        app.home.page(children: [
          app.shell.page(children: [_Screen.search.page()])
        ])
      ]);
    });

    testWidgets('query params are copied to every page of the tab and the URL keeps them', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search/post/5?lang=en');

      final query = {'lang': 'en'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [
          _Screen.search.page(queryParams: query),
          _Screen.post.page(pathParams: {'id': '5'}, queryParams: query),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/post/5?lang=en');
      expect(_tabIndex(tester), 1);
    });

    testWidgets('a first nested page that is not a tab gets the initial tab below it', (tester) async {
      final app = _ShopApp(initialTab: _Screen.search);
      final router = await _pump(tester, app.routes, url: '/shop/!post/5');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.search.page(),
          _Screen.post.page(pathParams: {'id': '5'}),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/post/5');
      expect(_tabIndex(tester), 1);
      expect(find.text('Post 5'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/search', '/post/5'],
      ]);

      // Back goes to the tab root, not out of the shell.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!search');
    });

    testWidgets('a replaced tab stack that does not start with a tab gets the initial tab, not the selected one',
        (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!profile');

      HelmRouter.replaceAll(_context(tester), [
        app.shell.page(children: [
          _Screen.post.page(pathParams: {'id': '7'})
        ])
      ]);
      await tester.pumpAndSettle();

      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/7');
      expect(_tabIndex(tester), 0);
      expect(find.text('Post 7'), findsOneWidget);
    });

    testWidgets('an unknown nested page leaves the shell with an empty tab that is filled', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!nothing');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.feed.page()])
      ]);
      expect(_tabIndex(tester), 0);
    });
  });

  group('switching tabs', () {
    testWidgets('tapping a tab selects it and updates state and URL', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.search.page()])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search');
      expect(_tabIndex(tester), 1);
      expect(find.text('Search screen'), findsOneWidget);
      expect(find.text('Feed screen'), findsNothing);
      expect(_navigators(tester), [
        ['/shop'],
        ['/search'],
      ]);

      await tester.tap(find.text('tab profile'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!profile');
      expect(_tabIndex(tester), 2);
      expect(find.text('Profile screen'), findsOneWidget);
    });

    testWidgets('a tab switch is a new history entry', (tester) async {
      final app = _ShopApp();
      final reports = <(String, bool)>[];
      await _pump(tester, app.routes, url: '/shop', reports: reports);
      reports.clear();

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();

      expect(reports, [('/shop/!search', false), ('/shop/!feed', false)]);
    });

    testWidgets('the stack of a tab is kept when you switch away and back', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next post'));
      await tester.pumpAndSettle();
      final feedStack = [
        _Screen.feed.page(),
        _Screen.post.page(pathParams: {'id': '1'}),
        _Screen.post.page(pathParams: {'id': '2'}),
      ];
      expect(router.delegate.currentConfiguration, [app.shell.page(children: feedStack)]);

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.search.page()])
      ]);
      expect(find.text('Post 2'), findsNothing);
      // The cached stack is still mounted, but offstage.
      expect(find.text('Post 2', skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentConfiguration, [app.shell.page(children: feedStack)]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1/post/2');
      expect(find.text('Post 2'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/feed', '/post/1', '/post/2'],
      ]);
    });

    testWidgets('widget state of an inactive tab is kept', (tester) async {
      final app = _ShopApp();
      await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Feed count: 0'));
      await tester.pump();
      await tester.tap(find.text('Feed count: 1'));
      await tester.pump();
      expect(find.text('Feed count: 2'), findsOneWidget);

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      expect(find.text('Feed count: 2'), findsNothing);
      expect(find.text('Feed count: 2', skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      expect(find.text('Feed count: 2'), findsOneWidget);
    });

    testWidgets('cacheTabState false drops the stack and the widget state of the tab you leave', (tester) async {
      final app = _ShopApp(cacheTabState: false);
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Feed count: 0'));
      await tester.pump();
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      expect(find.text('Post 1'), findsOneWidget);

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      expect(find.text('Post 1', skipOffstage: false), findsNothing);
      expect(find.text('Feed count: 1', skipOffstage: false), findsNothing);

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.feed.page()])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed');
      expect(find.text('Feed count: 0'), findsOneWidget);
      expect(find.text('Post 1', skipOffstage: false), findsNothing);
    });

    testWidgets('tapping the active tab again resets it to its first page', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      expect(find.text('Post 1'), findsOneWidget);

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.feed.page()])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed');
      expect(find.text('Post 1', skipOffstage: false), findsNothing);
      expect(find.text('Feed screen'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/feed'],
      ]);
    });

    testWidgets('clearStackOnDoubleTap false keeps the stack on a second tap', (tester) async {
      final app = _ShopApp(clearStackOnDoubleTap: false);
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      final before = router.delegate.currentConfiguration;

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, before);
      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1');
      expect(find.text('Post 1'), findsOneWidget);
    });

    testWidgets('a double tap resets only the active tab, other tabs keep their stacks', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search');
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!feed');

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/dart');
      expect(find.text('Result dart'), findsOneWidget);
    });
  });

  group('push inside a tab', () {
    testWidgets('a push goes to the stack of the selected tab', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search');

      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.search.page(),
          _Screen.result.page(pathParams: {'q': 'dart'}),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/dart');
      expect(find.text('Result dart'), findsOneWidget);
      // The tab bar stays, because the page is above the tab only.
      expect(find.text('tab feed'), findsOneWidget);
      expect(_tabIndex(tester), 1);
      expect(_navigators(tester), [
        ['/shop'],
        ['/search', '/search/results/dart'],
      ]);
    });

    testWidgets('a push from another tab adds the parent pages of the new page', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');

      HelmRouter.push(_context(tester), _Screen.result, pathParams: {'q': 'dart'});
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.feed.page(),
          _Screen.search.page(),
          _Screen.result.page(pathParams: {'q': 'dart'}),
        ])
      ]);
      expect(_tabIndex(tester), 0);
    });

    testWidgets('a push keeps the query params of the state', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!feed?lang=en');

      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();

      final query = {'lang': 'en'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [
          _Screen.feed.page(queryParams: query),
          _Screen.post.page(pathParams: {'id': '1'}, queryParams: query),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1?lang=en');
    });

    testWidgets('rootNavigator covers the whole shell and back returns to the same tab with its stack', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search/post/3');
      final shell = router.delegate.currentConfiguration.single;

      await tester.tap(find.text('Cover shop'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [shell, _Screen.promo.page()]);
      expect(find.text('Promo screen'), findsOneWidget);
      expect(find.text('tab feed'), findsNothing);
      expect(_navigators(tester).first, ['/shop', '/promo']);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [shell]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/post/3');
      expect(find.text('Post 3'), findsOneWidget);
      expect(_tabIndex(tester), 1);
    });
  });

  group('back inside a tab', () {
    testWidgets('the AppBar back button pops the tab page and updates state and URL', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next post'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1/post/2');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.feed.page(),
          _Screen.post.page(pathParams: {'id': '1'}),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1');
      expect(find.text('Post 1'), findsOneWidget);
      expect(_tabIndex(tester), 0);
    });

    testWidgets('system back pops the stack of the tab first', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes);
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // The shell stays and only the tab page goes.
      expect(router.delegate.currentConfiguration, [
        app.home.page(),
        app.shell.page(children: [_Screen.feed.page()]),
      ]);
      expect(find.text('Feed screen'), findsOneWidget);
    });

    testWidgets('system back at the root of a tab pops the shell off the root stack', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes);
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [app.home.page()]);
      expect(router.delegate.currentUri.toString(), '/');
      expect(find.text('Home screen'), findsOneWidget);
    });

    testWidgets('system back at the root of a non-first tab leaves the shell, it does not select the first tab',
        (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes);
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab profile'));
      await tester.pumpAndSettle();
      expect(_tabIndex(tester), 2);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [app.home.page()]);
      expect(find.text('Home screen'), findsOneWidget);
    });

    testWidgets('when the shell is the only root page, back is not handled so the app can exit', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      final before = router.delegate.currentConfiguration;

      expect(await router.delegate.popRoute(), isFalse);

      expect(router.delegate.currentConfiguration, before);
      expect(find.text('Feed screen'), findsOneWidget);
    });

    testWidgets('system back pops a page of a tab after a tab switch', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();

      expect(await router.delegate.popRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(router.delegate.currentUri.toString(), '/shop/!search');
      expect(find.text('Search screen'), findsOneWidget);
      expect(_tabIndex(tester), 1);
    });
  });

  group('deep link while the app runs', () {
    testWidgets('a link into another tab selects it and shows its stack', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');

      await _openLink(tester, '/shop/!search/post/5');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.search.page(),
          _Screen.post.page(pathParams: {'id': '5'}),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/post/5');
      expect(_tabIndex(tester), 1);
      expect(find.text('Post 5'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/search', '/post/5'],
      ]);
    });

    testWidgets('switching back to the previous tab shows its cached stack', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();

      await _openLink(tester, '/shop/!profile');
      expect(router.delegate.currentUri.toString(), '/shop/!profile');
      expect(_tabIndex(tester), 2);
      expect(find.text('Profile screen'), findsOneWidget);

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentUri.toString(), '/shop/!feed/post/1');
      expect(find.text('Post 1'), findsOneWidget);
      expect(_tabIndex(tester), 0);
    });

    testWidgets('a link that leaves the shell removes it and a link back opens it again', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');

      await _openLink(tester, '/');
      expect(router.delegate.currentConfiguration, [app.home.page()]);
      expect(find.text('Home screen'), findsOneWidget);

      await _openLink(tester, '/shop/!profile');
      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.profile.page()])
      ]);
      expect(_tabIndex(tester), 2);
    });
  });

  group('programmatic changes', () {
    testWidgets('replaceAll with a state of another tab selects that tab', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop');
      final next = [
        app.shell.page(children: [
          _Screen.search.page(),
          _Screen.result.page(pathParams: {'q': 'flutter'}),
        ])
      ];

      HelmRouter.replaceAll(_context(tester), next);
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, next);
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/flutter');
      expect(_tabIndex(tester), 1);
      expect(find.text('Result flutter'), findsOneWidget);
    });

    testWidgets('an empty shell page is filled with the initial tab, also while the shell stays mounted',
        (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search');

      HelmRouter.replaceWithRoute(_context(tester), app.shell);
      await tester.pumpAndSettle();

      // The same state gives the same tab, whatever tab was selected before.
      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.feed.page()])
      ]);
      expect(_tabIndex(tester), 0);
    });

    testWidgets('a shell that was removed and added again starts with the first tab', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search');

      HelmRouter.replaceAll(_context(tester), [app.home.page()]);
      await tester.pumpAndSettle();
      HelmRouter.replaceAll(_context(tester), [app.shell.page()]);
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [_Screen.feed.page()])
      ]);
      expect(_tabIndex(tester), 0);
    });

    testWidgets('changeQueryParams updates the pages of the selected tab and the URL', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!search');
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();

      HelmRouter.changeQueryParams(_context(tester), queryParams: {'sort': 'asc'});
      await tester.pumpAndSettle();

      final query = {'sort': 'asc'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [
          _Screen.search.page(queryParams: query),
          _Screen.result.page(pathParams: {'q': 'dart'}, queryParams: query),
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/dart?sort=asc');
      expect(find.text('Result dart'), findsOneWidget);

      HelmRouter.changeQueryParams(_context(tester), queryParams: {'sort': ''});
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/dart');
    });

    testWidgets('query params stay in the URL after a tab switch', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop?lang=en');

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentUri.toString(), '/shop/!search?lang=en');
      expect(router.delegate.currentQueryParams, {'lang': 'en'});
    });

    testWidgets('the first tab that fills the shell gets the query params of the URL', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop?lang=en');

      final query = {'lang': 'en'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [_Screen.feed.page(queryParams: query)])
      ]);
    });

    testWidgets('a cached tab stack gets the query params that changed while the tab was inactive', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!feed?lang=en');
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      HelmRouter.changeQueryParams(_context(tester), queryParams: {'lang': 'de'});
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();

      final query = {'lang': 'de'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [_Screen.feed.page(queryParams: query)])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed?lang=de');
    });

    testWidgets('a cached tab stack drops the query params that were removed while the tab was inactive',
        (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!feed?lang=en&sort=new');
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      HelmRouter.changeQueryParams(_context(tester), queryParams: {'lang': ''});
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!search?sort=new');
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();

      final query = {'sort': 'new'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [_Screen.feed.page(queryParams: query)])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!feed?sort=new');
    });

    testWidgets('a tab selected by tap gets the current query params', (tester) async {
      final app = _ShopApp();
      final router = await _pump(tester, app.routes, url: '/shop/!feed?lang=en');

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      final query = {'lang': 'en'};
      expect(router.delegate.currentConfiguration, [
        app.shell.page(queryParams: query, children: [_Screen.search.page(queryParams: query)])
      ]);
    });
  });

  group('NestedNavigator inside a tab', () {
    final tabs = [_Screen.feed, _Screen.host, _Screen.profile];

    testWidgets('a deep link opens the nested stack of the tab page', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!host/!step/a');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.host.page(children: [
            _Screen.step.page(pathParams: {'s': 'a'})
          ])
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a');
      expect(_tabIndex(tester), 1);
      expect(find.text('Host screen'), findsOneWidget);
      expect(find.text('Step a'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/host'],
        ['/step/a'],
      ]);
    });

    testWidgets('selecting the tab fills the nested stack with its initial page', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop');

      await tester.tap(find.text('tab host'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.host.page(children: [
            _Screen.step.page(pathParams: {'s': 'a'})
          ])
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a');
      expect(find.text('Step a'), findsOneWidget);
    });

    testWidgets('a push goes to the deepest stack and back pops level by level', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes);
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab host'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next step'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a/step/b');
      expect(find.text('Step b'), findsOneWidget);
      expect(_navigators(tester), [
        ['/', '/shop'],
        ['/host'],
        ['/step/a', '/step/b'],
      ]);

      // 1. The nested stack pops.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a');
      expect(find.text('Step a'), findsOneWidget);

      // 2. The nested stack and the tab have one page each, so the shell leaves the root stack.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.delegate.currentConfiguration, [app.home.page()]);
      expect(find.text('Home screen'), findsOneWidget);
    });

    testWidgets('switching tabs keeps the nested stack', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!host/!step/a');
      await tester.tap(find.text('Next step'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a/step/b');

      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!feed');
      expect(find.text('Step b'), findsNothing);

      await tester.tap(find.text('tab host'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a/step/b');
      expect(find.text('Step b'), findsOneWidget);
      expect(_tabIndex(tester), 1);
    });

    testWidgets('the AppBar back button of the nested stack pops only the nested page', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!host/!step/a/step/b');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(router.delegate.currentUri.toString(), '/shop/!host/!step/a');
      expect(_tabIndex(tester), 1);
      expect(find.text('Host screen'), findsOneWidget);
    });
  });

  group('tabs inside tabs', () {
    final tabs = [_Screen.feed, _Screen.section, _Screen.profile];

    testWidgets('a deep link selects the outer and the inner tab', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!section/!saved');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.section.page(children: [_Screen.saved.page()])
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!section/!saved');
      expect(_tabIndex(tester), 1);
      expect(_subTabIndex(tester), 1);
      expect(find.text('Saved screen'), findsOneWidget);
      expect(_navigators(tester), [
        ['/shop'],
        ['/section'],
        ['/saved'],
      ]);
    });

    testWidgets('the inner tab bar is filled with its first tab', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!section');

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.section.page(children: [_Screen.recent.page()])
        ])
      ]);
      expect(router.delegate.currentUri.toString(), '/shop/!section/!recent');
      expect(_subTabIndex(tester), 0);
    });

    testWidgets('inner and outer tabs switch independently and keep their stacks', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!section/!recent');

      // A page in the inner tab "recent".
      await tester.tap(find.text('Open recent post'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!section/!recent/post/7');
      expect(_navigators(tester), [
        ['/shop'],
        ['/section'],
        ['/recent', '/post/7'],
      ]);

      // Switch the inner tab.
      await tester.tap(find.text('sub saved'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!section/!saved');
      expect(_subTabIndex(tester), 1);
      expect(_tabIndex(tester), 1);
      expect(find.text('Saved screen'), findsOneWidget);

      // Switch the outer tab away and back: the inner tab is still "saved".
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!feed');
      await tester.tap(find.text('tab section'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!section/!saved');
      expect(find.text('Saved screen'), findsOneWidget);

      // The inner tab "recent" still has its post.
      await tester.tap(find.text('sub recent'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!section/!recent/post/7');
      expect(find.text('Post 7'), findsOneWidget);
    });

    testWidgets('back pops the inner tab stack, then leaves the shell', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes);
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab section'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open recent post'));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!section/!recent/post/7');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/shop/!section/!recent');
      expect(find.text('Recent screen'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.delegate.currentConfiguration, [app.home.page()]);
    });

    testWidgets('a second tap on the inner tab resets only the inner stack', (tester) async {
      final app = _ShopApp(tabs: tabs);
      final router = await _pump(tester, app.routes, url: '/shop/!section/!recent');
      await tester.tap(find.text('Open recent post'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('sub recent'));
      await tester.pumpAndSettle();

      expect(router.delegate.currentConfiguration, [
        app.shell.page(children: [
          _Screen.section.page(children: [_Screen.recent.page()])
        ])
      ]);
      expect(_tabIndex(tester), 1);
    });
  });

  group('observers and transitions', () {
    testWidgets('observersBuilder is called once per tab and each observer sees only its tab', (tester) async {
      final built = <int>[];
      final logs = <int, _Log>{};
      final app = _ShopApp(observersBuilder: (index) {
        built.add(index);
        return [logs[index] = _Log()];
      });
      await _pump(tester, app.routes, url: '/shop');
      expect(built, [0]);
      expect(logs[0]!.pushed, ['/feed']);

      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      expect(built, [0, 1]);
      expect(logs[0]!.pushed, ['/feed', '/post/1']);
      expect(logs[1]!.pushed, ['/search', '/search/results/dart']);
    });

    testWidgets('a custom transitionDelegate runs for the pages of the tabs', (tester) async {
      final delegate = _CountingTransitions();
      final app = _ShopApp(transitionDelegate: delegate);
      await _pump(tester, app.routes, url: '/shop');
      expect(delegate.lastTopPages, isEmpty);

      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      expect(delegate.lastTopPages.last, '/post/1');

      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();
      expect(delegate.lastTopPages.last, '/search/results/dart');
    });

    testWidgets('a custom transitionDelegate also runs when a page of a tab is popped', (tester) async {
      final delegate = _CountingTransitions();
      final app = _ShopApp(transitionDelegate: delegate);
      await _pump(tester, app.routes, url: '/shop/!feed/post/1');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(delegate.lastTopPages.last, '/feed');
    });
  });

  group('state restoration', () {
    testWidgets('the selected tab and its stack come back after a restart', (tester) async {
      final app = _ShopApp();
      final routers = <HelmRouter>[];
      _stubPlatform(tester);

      await tester.pumpWidget(_RestorableApp(app, routers.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();
      final before = routers.single.delegate.currentConfiguration;
      expect(routers.single.delegate.currentUri.toString(), '/shop/!search/results/dart');

      // The new router starts from `/`, so only restoration data can bring the state back.
      await tester.restartAndRestore();

      final router = routers.last;
      expect(routers, hasLength(2));
      expect(identical(router, routers.first), isFalse);
      expect(router.delegate.currentConfiguration, before);
      expect(router.delegate.currentUri.toString(), '/shop/!search/results/dart');
      expect(_tabIndex(tester), 1);
      expect(find.text('Result dart'), findsOneWidget);
      expect(_navigators(tester), [
        ['/', '/shop'],
        ['/search', '/search/results/dart'],
      ]);
    });

    testWidgets('the cached stack of an inactive tab is not restored', (tester) async {
      final app = _ShopApp();
      final routers = <HelmRouter>[];
      _stubPlatform(tester);

      await tester.pumpWidget(_RestorableApp(app, routers.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open post 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab search'));
      await tester.pumpAndSettle();

      await tester.restartAndRestore();

      expect(_tabIndex(tester), 1);
      expect(find.text('Search screen'), findsOneWidget);
      await tester.tap(find.text('tab feed'));
      await tester.pumpAndSettle();
      // Only the active stack is in the navigation state, so the feed tab starts at its first page.
      expect(routers.last.delegate.currentUri.toString(), '/shop/!feed');
      expect(find.text('Post 1', skipOffstage: false), findsNothing);
    });
  });
}

// --- Test apps ---

/// Routes without config. They are the pages inside the tabs.
enum _Screen with Routable {
  feed,
  search,
  result,
  post,
  profile,
  promo,
  host,
  step,
  section,
  recent,
  saved;

  @override
  String get path => switch (this) {
        feed => '/feed',
        search => '/search',
        result => '/search/results/{q}',
        post => '/post/{id}',
        profile => '/profile',
        promo => '/promo',
        host => '/host',
        step => '/step/{s}',
        section => '/section',
        recent => '/recent',
        saved => '/saved',
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        feed => const _View(
            title: 'Feed screen',
            children: [
              _Counter('Feed count'),
              _PushButton('Open post 1', _Screen.post, pathParams: {'id': '1'}),
            ],
          ),
        search => const _View(
            title: 'Search screen',
            children: [
              _Counter('Search count'),
              _PushButton('Open result', _Screen.result, pathParams: {'q': 'dart'}),
            ],
          ),
        result => _View(title: 'Result ${pathParams['q']}'),
        post => _View(
            title: 'Post ${pathParams['id']}',
            children: [
              _PushButton('Next post', _Screen.post, pathParams: {'id': '${int.parse(pathParams['id']!) + 1}'}),
              const _PushButton('Cover shop', _Screen.promo, rootNavigator: true),
            ],
          ),
        profile => const _View(title: 'Profile screen'),
        promo => const _View(title: 'Promo screen'),
        host => NestedNavigator(
            initialState: [
              _Screen.step.page(pathParams: const {'s': 'a'})
            ],
            builder: (context, child) => Column(children: [const Text('Host screen'), Expanded(child: child)]),
          ),
        step => _View(
            title: 'Step ${pathParams['s']}',
            children: [
              _PushButton('Next step', _Screen.step, pathParams: {'s': pathParams['s'] == 'a' ? 'b' : 'c'}),
            ],
          ),
        section => NestedTabsNavigator(
            tabs: const [_Screen.recent, _Screen.saved],
            builder: (context, child, index, onTap) => Column(children: [
              const Text('Section screen'),
              Expanded(child: child),
              BottomNavigationBar(
                currentIndex: index,
                onTap: onTap,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.history), label: 'sub recent'),
                  BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'sub saved'),
                ],
              ),
            ]),
          ),
        recent => const _View(
            title: 'Recent screen',
            children: [
              _PushButton('Open recent post', _Screen.post, pathParams: {'id': '7'})
            ],
          ),
        saved => const _View(title: 'Saved screen'),
      };
}

/// The home route, the shell route and all routes of one test app.
class _ShopApp {
  _ShopApp({
    List<Routable> tabs = const [_Screen.feed, _Screen.search, _Screen.profile],
    Routable? initialTab,
    NavigationState? initialState,
    bool cacheTabState = true,
    bool clearStackOnDoubleTap = true,
    List<NavigatorObserver> Function(int tabIndex)? observersBuilder,
    TransitionDelegate<Object?>? transitionDelegate,
  }) {
    shell = _Route(
      '/shop',
      (_, __) => NestedTabsNavigator(
        tabs: tabs,
        initialTab: initialTab,
        initialState: initialState,
        cacheTabState: cacheTabState,
        clearStackOnDoubleTap: clearStackOnDoubleTap,
        observersBuilder: observersBuilder,
        transitionDelegate: transitionDelegate,
        builder: (context, child, index, onTap) => Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onTap,
            destinations: [
              for (final tab in tabs)
                NavigationDestination(icon: const Icon(Icons.circle), label: 'tab ${tab.path.substring(1)}'),
            ],
          ),
        ),
      ),
    );
    home = _Route('/', (_, __) => _View(title: 'Home screen', children: [_PushButton('Open shop', shell)]));
  }

  late final _Route shell;
  late final _Route home;

  List<Routable> get routes => [home, shell, ..._Screen.values];
}

class _Route with Routable {
  _Route(this.path, this._build);

  @override
  final String path;
  final Widget Function(Map<String, String> pathParams, Map<String, String> queryParams) _build;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => _build(pathParams, queryParams);
}

/// A page with an AppBar title and some content.
class _View extends StatelessWidget {
  const _View({required this.title, this.children = const []});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: Column(children: children));
}

class _PushButton extends StatelessWidget {
  const _PushButton(this.label, this.route, {this.pathParams = const {}, this.rootNavigator = false});

  final String label;
  final Routable route;
  final Map<String, String> pathParams;
  final bool rootNavigator;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => HelmRouter.push(context, route, pathParams: pathParams, rootNavigator: rootNavigator),
        child: Text(label),
      );
}

/// A tap counter that keeps its value in its State.
class _Counter extends StatefulWidget {
  const _Counter(this.label);

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () => setState(() => _count++), child: Text('${widget.label}: $_count'));
}

class _Log extends NavigatorObserver {
  final pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
}

class _CountingTransitions extends TransitionDelegate<Object?> {
  /// The name of the top page at each call of [resolve].
  final lastTopPages = <String?>[];

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord> locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>> pageRouteToPagelessRoutes,
  }) {
    lastTopPages.add(newPageRouteHistory.lastOrNull?.route.settings.name);
    return const DefaultTransitionDelegate<Object?>().resolve(
      newPageRouteHistory: newPageRouteHistory,
      locationToExitingPageRoute: locationToExitingPageRoute,
      pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
    );
  }
}

/// An app with restoration. [onRouter] gets each router that the app creates.
class _RestorableApp extends StatefulWidget {
  const _RestorableApp(this.app, this.onRouter);

  /// The URL has no home page, so a guard adds it again after a restore.
  final _ShopApp app;
  final void Function(HelmRouter router) onRouter;

  @override
  State<_RestorableApp> createState() => _RestorableAppState();
}

class _RestorableAppState extends State<_RestorableApp> {
  late final HelmRouter router = HelmRouter(
    routes: widget.app.routes,
    guards: [
      (pages) => pages.first.route == widget.app.home ? pages : [widget.app.home.page(), ...pages]
    ],
    enableLogs: false,
  );

  @override
  void initState() {
    super.initState();
    widget.onRouter(router);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(restorationScopeId: 'app', routerConfig: router);
}

// --- Helpers ---

void _stubPlatform(WidgetTester tester, {List<(String, bool)>? reports}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
    if (reports != null && call.method == 'routeInformationUpdated') {
      final args = call.arguments as Map<Object?, Object?>;
      reports.add((args['uri']! as String, args['replace']! as bool));
    }
    return null;
  });
}

/// Starts the app like the platform does: [url] is the initial route.
/// [reports] collects the `(url, replace)` pairs that the router reports to the platform.
Future<HelmRouter> _pump(
  WidgetTester tester,
  List<Routable> routes, {
  String url = '/',
  List<NavigationGuard> guards = const [],
  List<(String, bool)>? reports,
}) async {
  _stubPlatform(tester, reports: reports);
  tester.platformDispatcher.defaultRouteNameTestValue = url; // HelmRouter reads it in its factory
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = HelmRouter(routes: routes, guards: guards, enableLogs: false);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

/// Page names of each onstage Navigator, root first. Inactive tabs and covered pages are offstage.
List<List<String?>> _navigators(WidgetTester tester) => [
      for (final navigator in tester.widgetList<Navigator>(find.byType(Navigator)))
        [for (final page in navigator.pages) page.name],
    ];

/// The selected index of the outer tab bar.
int _tabIndex(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// The selected index of the inner tab bar.
int _subTabIndex(WidgetTester tester) =>
    tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).currentIndex;

/// A context under the router, for the static `HelmRouter` API.
BuildContext _context(WidgetTester tester) => tester.element(find.byType(Navigator).first);

/// Sends a link to the running app, like the platform does.
Future<void> _openLink(WidgetTester tester, String url) async {
  final message =
      SystemChannels.navigation.codec.encodeMethodCall(MethodCall('pushRouteInformation', {'location': url}));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}
