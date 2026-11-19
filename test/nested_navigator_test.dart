import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

// ---------------------------------------------------------------------------
// Test app
// ---------------------------------------------------------------------------

/// Routes of the test app. Hosts (`host`, `host2`, `bare`, `side`, `outer`, `mid`) show a NestedNavigator.
enum _R with Routable {
  home('/'),
  host('/host'),
  host2('/host2'),
  bare('/bare'),
  side('/side'),
  outer('/outer'),
  mid('/mid'),
  leaf('/leaf'),
  detail('/detail/{id}'),
  a('/a'),
  b('/b'),
  products('/products'),
  product('/products/{pid}'),
  tags('/tags/{tag+}'),
  other('/other'),
  locked('/locked'),
  dialog('/dialog', PageType.dialog);

  const _R(this.path, [this.pageType = PageType.material]);

  @override
  final String path;
  @override
  final PageType pageType;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        _R.home => const _Screen('Home', [
            _Push('Open host', _R.host),
            _Push('Open host2', _R.host2),
            _Push('Open bare', _R.bare),
            _Push('Open side', _R.side),
            _Push('Open outer', _R.outer),
          ]),
        _R.host => NestedNavigator(
            initialRoute: _R.a,
            builder: (context, child) => Scaffold(
              body: Column(children: [
                const Text('Host'),
                const _Push('Host push b', _R.b),
                const _Push('Host push other', _R.other, root: true),
                Expanded(child: child),
              ]),
            ),
          ),
        _R.host2 => NestedNavigator(
            initialRoute: _R.b,
            builder: (context, child) =>
                Scaffold(body: Column(children: [const Text('Host2'), Expanded(child: child)])),
          ),
        _R.bare => NestedNavigator(
            builder: (context, child) => Scaffold(
              body: Column(children: [
                const Text('Bare'),
                const _Push('Bare push a', _R.a),
                Expanded(child: child),
              ]),
            ),
          ),
        // Master-detail: the sidebar is host content and has its own widget state.
        _R.side => NestedNavigator(
            initialRoute: _R.a,
            builder: (context, child) => Scaffold(
              body: Row(children: [
                const SizedBox(
                  width: 240,
                  child: Column(children: [
                    _Tally('Side'),
                    TextField(),
                    _Push('Side push other', _R.other, root: true),
                  ]),
                ),
                Expanded(child: child),
              ]),
            ),
          ),
        _R.outer => NestedNavigator(
            initialRoute: _R.mid,
            builder: (context, child) =>
                Scaffold(body: Column(children: [const Text('Outer'), Expanded(child: child)])),
          ),
        _R.mid => NestedNavigator(
            initialRoute: _R.leaf,
            builder: (context, child) => Scaffold(body: Column(children: [const Text('Mid'), Expanded(child: child)])),
          ),
        _R.leaf => const _Screen('Leaf', [
            _Push('Leaf push detail 7', _R.detail, pathParams: {'id': '7'})
          ]),
        _R.detail => _Screen('Detail ${pathParams['id']}'),
        _R.a => const _Screen('Page A', [
            _Tally('A'),
            _Push('A push b', _R.b),
            _Push('A push product 5', _R.product, pathParams: {'pid': '5'}),
            _Push('A push dialog', _R.dialog),
            _Push('A push locked', _R.locked),
            _Push('A push other', _R.other, root: true),
          ]),
        _R.b => _Screen('Page B', [Text('B query: $queryParams')]),
        _R.products => const _Screen('Products'),
        _R.product => _Screen('Product ${pathParams['pid']}'),
        _R.tags => _Screen('Tag ${pathParams['tag']}'),
        _R.other => const _Screen('Other'),
        _R.locked => const PopScope(canPop: false, child: _Screen('Locked')),
        _R.dialog => const AlertDialog(title: Text('Dialog')),
      };
}

class _Screen extends StatelessWidget {
  const _Screen(this.title, [this.children = const []]);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: Column(children: children));
}

class _Push extends StatelessWidget {
  const _Push(this.label, this.route, {this.pathParams = const {}, this.root = false});

  final String label;
  final _R route;
  final Map<String, String> pathParams;
  final bool root;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => HelmRouter.push(context, route, pathParams: pathParams, rootNavigator: root),
        child: Text(label),
      );
}

/// A counter with widget state. It shows `label: count` and has an `Add label` button.
class _Tally extends StatefulWidget {
  const _Tally(this.label);

  final String label;

  @override
  State<_Tally> createState() => _TallyState();
}

class _TallyState extends State<_Tally> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('${widget.label}: $_count'),
        TextButton(onPressed: () => setState(() => _count++), child: Text('Add ${widget.label}')),
      ]);
}

/// A route with its own builder, for tests that need custom config.
class _Route with Routable {
  _Route(this.path, this._build);

  @override
  final String path;
  final Widget Function(Map<String, String> pathParams, Map<String, String> queryParams) _build;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => _build(pathParams, queryParams);
}

/// A page that shows a push button.
Widget _pushButton(String label, Routable Function() route, {bool root = false}) => Builder(
      builder: (context) => TextButton(
        onPressed: () => HelmRouter.push(context, route(), rootNavigator: root),
        child: Text(label),
      ),
    );

class _PushLog extends NavigatorObserver {
  final pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
}

/// Adds new pages without animation and counts how often it runs.
class _InstantDelegate extends TransitionDelegate<Object?> {
  int resolves = 0;

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord> locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>> pageRouteToPagelessRoutes,
  }) {
    resolves++;
    final results = <RouteTransitionRecord>[];
    for (final record in newPageRouteHistory) {
      if (record.isWaitingForEnteringDecision) record.markForAdd();
      results.add(record);
    }
    for (final record in locationToExitingPageRoute.values) {
      if (record.isWaitingForExitingDecision) {
        record.markForComplete();
        pageRouteToPagelessRoutes[record]?.forEach((route) => route.markForComplete());
      }
      results.add(record);
    }
    return results;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps an app at [url], like a deep link. [history] collects `(uri, replace)` of each history report.
Future<HelmRouter> _pump(
  WidgetTester tester,
  List<Routable> routes, {
  String url = '/',
  List<NavigationGuard> guards = const [],
  List<NavigatorObserver> observers = const [],
  List<(String, bool)>? history,
}) async {
  tester.view
    ..physicalSize = const Size(800, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
    if (history != null && call.method == 'routeInformationUpdated') {
      final args = call.arguments as Map<Object?, Object?>;
      history.add((args['uri']! as String, args['replace']! as bool));
    }
    return null;
  });
  tester.platformDispatcher.defaultRouteNameTestValue = url;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

  final router = HelmRouter(routes: routes, guards: guards, observers: observers, enableLogs: false);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

/// Page names of each onstage Navigator, root first. Covered pages are offstage.
List<List<String?>> _navigators(WidgetTester tester) => [
      for (final navigator in tester.widgetList<Navigator>(find.byType(Navigator)))
        [for (final page in navigator.pages) page.name],
    ];

/// A context under the router that stays mounted, for calls to the public `HelmRouter` API.
BuildContext _appContext(WidgetTester tester) => tester.element(find.byType(Navigator).first);

/// Guard: the root stack starts with the home page.
NavigationGuard _homeFirst =
    (pages) => pages.isNotEmpty && pages.first.route != _R.home ? [_R.home.page(), ...pages] : pages;

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// System back button.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void _expectState(HelmRouter router, NavigationState tree, String url) {
  expect(router.delegate.currentConfiguration, tree);
  expect(router.delegate.currentUri.toString(), url);
}

typedef _UrlCase = ({
  String name,
  String url,
  NavigationState tree,
  String finalUrl,
  List<List<String?>> navigators,
  String text,
});

void main() {
  group('Deep links', () {
    final query = {'ref': 'mail'};
    final cases = <_UrlCase>[
      (
        name: 'a host without a dive is filled with its initial route',
        url: '/host',
        tree: [
          _R.host.page(children: [_R.a.page()])
        ],
        finalUrl: '/host/!a',
        navigators: [
          ['/host'],
          ['/a']
        ],
        text: 'Page A',
      ),
      (
        name: 'a dive replaces the initial stack',
        url: '/host/!b',
        tree: [
          _R.host.page(children: [_R.b.page()])
        ],
        finalUrl: '/host/!b',
        navigators: [
          ['/host'],
          ['/b']
        ],
        text: 'Page B',
      ),
      (
        name: 'several nested pages',
        url: '/host/!a/b',
        tree: [
          _R.host.page(children: [_R.a.page(), _R.b.page()])
        ],
        finalUrl: '/host/!a/b',
        navigators: [
          ['/host'],
          ['/a', '/b']
        ],
        text: 'Page B',
      ),
      (
        name: 'parent pages are added inside the nested stack',
        url: '/host/!products/5',
        tree: [
          _R.host.page(children: [
            _R.products.page(),
            _R.product.page(pathParams: {'pid': '5'})
          ]),
        ],
        finalUrl: '/host/!products/5',
        navigators: [
          ['/host'],
          ['/products', '/products/5']
        ],
        text: 'Product 5',
      ),
      (
        name: 'encoded path param in a nested page',
        url: '/host/!products/a%20b%2Fc%21',
        tree: [
          _R.host.page(children: [
            _R.products.page(),
            _R.product.page(pathParams: {'pid': 'a b/c!'})
          ]),
        ],
        finalUrl: '/host/!products/a%20b%2Fc%21',
        navigators: [
          ['/host'],
          ['/products', '/products/a b/c!']
        ],
        text: 'Product a b/c!',
      ),
      (
        name: 'a {name+} sequence in the nested stack',
        url: '/host/!tags/x/y',
        tree: [
          _R.host.page(children: [
            _R.tags.page(pathParams: {'tag': 'x'}),
            _R.tags.page(pathParams: {'tag': 'y'}),
          ]),
        ],
        finalUrl: '/host/!tags/x/y',
        navigators: [
          ['/host'],
          ['/tags/x', '/tags/y']
        ],
        text: 'Tag y',
      ),
      (
        name: 'a ~ ends the sequence and a page follows in the nested stack',
        url: '/host/!tags/x/y/~/b',
        tree: [
          _R.host.page(children: [
            _R.tags.page(pathParams: {'tag': 'x'}),
            _R.tags.page(pathParams: {'tag': 'y'}),
            _R.b.page(),
          ]),
        ],
        finalUrl: '/host/!tags/x/y/~/b',
        navigators: [
          ['/host'],
          ['/tags/x', '/tags/y', '/b']
        ],
        text: 'Page B',
      ),
      (
        name: 'a rise then a sibling page covers the host',
        url: '/host/!a!/other',
        tree: [
          _R.host.page(children: [_R.a.page()]),
          _R.other.page()
        ],
        finalUrl: '/host/!a!/other',
        navigators: [
          ['/host', '/other']
        ],
        text: 'Other',
      ),
      (
        name: 'two hosts in the root stack, each with its own nested stack',
        url: '/host/!a!/host2/!b',
        tree: [
          _R.host.page(children: [_R.a.page()]),
          _R.host2.page(children: [_R.b.page()])
        ],
        finalUrl: '/host/!a!/host2/!b',
        navigators: [
          ['/host', '/host2'],
          ['/b']
        ],
        text: 'Page B',
      ),
      (
        name: 'a second host without a dive is filled too',
        url: '/host/!a!/host2',
        tree: [
          _R.host.page(children: [_R.a.page()]),
          _R.host2.page(children: [_R.b.page()])
        ],
        finalUrl: '/host/!a!/host2/!b',
        navigators: [
          ['/host', '/host2'],
          ['/b']
        ],
        text: 'Page B',
      ),
      (
        name: 'a trailing rise is dropped',
        url: '/host/!b!/',
        tree: [
          _R.host.page(children: [_R.b.page()])
        ],
        finalUrl: '/host/!b',
        navigators: [
          ['/host'],
          ['/b']
        ],
        text: 'Page B',
      ),
      (
        name: 'query params reach nested pages',
        url: '/host/!products/5?ref=mail',
        tree: [
          _R.host.page(queryParams: query, children: [
            _R.products.page(queryParams: query),
            _R.product.page(pathParams: {'pid': '5'}, queryParams: query),
          ]),
        ],
        finalUrl: '/host/!products/5?ref=mail',
        navigators: [
          ['/host'],
          ['/products', '/products/5']
        ],
        text: 'Product 5',
      ),
      (
        name: 'nested pages of a host inside a host',
        url: '/outer',
        tree: [
          _R.outer.page(children: [
            _R.mid.page(children: [_R.leaf.page()])
          ]),
        ],
        finalUrl: '/outer/!mid/!leaf',
        navigators: [
          ['/outer'],
          ['/mid'],
          ['/leaf']
        ],
        text: 'Leaf',
      ),
    ];

    for (final c in cases) {
      testWidgets(c.name, (tester) async {
        final router = await _pump(tester, _R.values, url: c.url);
        _expectState(router, c.tree, c.finalUrl);
        expect(_navigators(tester), c.navigators);
        expect(find.text(c.text), findsOneWidget);
      });
    }

    testWidgets('the initial page that fills the stack gets the query params of the URL', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host?ref=mail');
      final query = {'ref': 'mail'};
      expect(router.delegate.currentConfiguration, [
        _R.host.page(queryParams: query, children: [_R.a.page(queryParams: query)])
      ]);
      expect(router.delegate.currentUri.toString(), '/host/!a?ref=mail');
      expect(find.text('Page A'), findsOneWidget);
    });
  });

  group('Filling', () {
    testWidgets('initialState fills the stack with several pages', (tester) async {
      final a = _Route('/a', (_, __) => const _Screen('Page A'));
      final b = _Route('/b', (_, __) => const _Screen('Page B'));
      final host = _Route(
        '/host',
        (_, __) => NestedNavigator(
          initialState: [a.page(), b.page()],
          builder: (context, child) => Scaffold(body: child),
        ),
      );
      final router = await _pump(tester, [a, b, host], url: '/host');

      _expectState(
          router,
          [
            host.page(children: [a.page(), b.page()])
          ],
          '/host/!a/b');
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/b']
      ]);
      expect(find.text('Page B'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('a dive in the URL wins over initialState', (tester) async {
      final a = _Route('/a', (_, __) => const _Screen('Page A'));
      final b = _Route('/b', (_, __) => const _Screen('Page B'));
      final host = _Route(
        '/host',
        (_, __) => NestedNavigator(initialState: [a.page(), b.page()], builder: (context, child) => child),
      );
      final router = await _pump(tester, [a, b, host], url: '/host/!b');

      _expectState(
          router,
          [
            host.page(children: [b.page()])
          ],
          '/host/!b');
    });

    testWidgets('without initialRoute and initialState the stack stays empty until a push', (tester) async {
      final router = await _pump(tester, _R.values, url: '/bare');

      _expectState(router, [_R.bare.page(children: [])], '/bare');
      expect(_navigators(tester), [
        ['/bare']
      ]);
      expect(find.text('Bare'), findsOneWidget);

      await _tap(tester, 'Bare push a');
      _expectState(
          router,
          [
            _R.bare.page(children: [_R.a.page()])
          ],
          '/bare/!a');
      expect(_navigators(tester), [
        ['/bare'],
        ['/a']
      ]);
      expect(find.text('Page A'), findsOneWidget);
    });

    testWidgets('the builder gets an empty child when the stack is empty', (tester) async {
      final a = _Route('/a', (_, __) => const Text('Page A'));
      final host = _Route(
        '/host',
        (_, __) => NestedNavigator(builder: (context, child) => Text(child is Navigator ? 'has navigator' : 'empty')),
      );
      await _pump(tester, [a, host], url: '/host');

      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('initialRoute and initialState together are rejected', (tester) async {
      expect(
        () => NestedNavigator(initialRoute: _R.a, initialState: [_R.a.page()], builder: (context, child) => child),
        throwsAssertionError,
      );
    });

    testWidgets('an empty initialState is rejected', (tester) async {
      expect(() => NestedNavigator(initialState: [], builder: (context, child) => child), throwsAssertionError);
    });

    testWidgets('a NestedNavigator outside a Helm page throws a FlutterError', (tester) async {
      // A pageless dialog is inside the router but not inside a page.
      final home = _Route(
        '/',
        (_, __) => Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => NestedNavigator(builder: (context, child) => child),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await _pump(tester, [home]);

      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(tester.takeException(), isA<FlutterError>().having((e) => e.message, 'message', contains('Helm')));
    });
  });

  group('Push', () {
    testWidgets('from a nested page goes to the nested stack', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');

      await _tap(tester, 'A push b');
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page(), _R.b.page()])
          ],
          '/host/!a/b');
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/b']
      ]);
      expect(find.text('Page B'), findsOneWidget);
    });

    testWidgets('from the host content goes to the nested stack', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');

      await _tap(tester, 'Host push b');
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page(), _R.b.page()])
          ],
          '/host/!a/b');
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/b']
      ]);
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Page B'), findsOneWidget);
    });

    testWidgets('adds missing parent pages to the nested stack', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');

      await _tap(tester, 'A push product 5');
      _expectState(
        router,
        [
          _R.host.page(children: [
            _R.a.page(),
            _R.products.page(),
            _R.product.page(pathParams: {'pid': '5'}),
          ]),
        ],
        '/host/!a/products/5',
      );
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/products', '/products/5']
      ]);
      expect(find.text('Product 5'), findsOneWidget);
    });

    testWidgets('with rootNavigator pushes on the root stack and covers the host', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');

      await _tap(tester, 'A push other');
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page()]),
            _R.other.page()
          ],
          '/host/!a!/other');
      expect(_navigators(tester), [
        ['/host', '/other']
      ]);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Host'), findsNothing);
    });

    testWidgets('merges the current query params into the nested page', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host/!a?ref=mail');

      await _tap(tester, 'A push b');
      final query = {'ref': 'mail'};
      _expectState(
        router,
        [
          _R.host.page(queryParams: query, children: [_R.a.page(queryParams: query), _R.b.page(queryParams: query)])
        ],
        '/host/!a/b?ref=mail',
      );
      expect(find.text('B query: {ref: mail}'), findsOneWidget);
    });

    testWidgets('a host page pushed from the root stack is filled and the URL follows each step', (tester) async {
      final router = await _pump(tester, _R.values);
      _expectState(router, [_R.home.page()], '/');

      await _tap(tester, 'Open host');
      _expectState(
          router,
          [
            _R.home.page(),
            _R.host.page(children: [_R.a.page()])
          ],
          '/host/!a');
      expect(_navigators(tester), [
        ['/', '/host'],
        ['/a']
      ]);

      await _tap(tester, 'A push b');
      expect(router.delegate.currentUri.toString(), '/host/!a/b');

      await _tap(tester, 'Host push other');
      expect(router.delegate.currentUri.toString(), '/host/!a/b!/other');
      expect(_navigators(tester), [
        ['/', '/host', '/other']
      ]);
    });
  });

  group('Back', () {
    testWidgets('the AppBar back button pops the nested page', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host/!a/b');
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page()])
          ],
          '/host/!a');
      expect(_navigators(tester), [
        ['/host'],
        ['/a']
      ]);
      expect(find.text('Page A'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('system back pops the nested stack first, then the host', (tester) async {
      final router = await _pump(tester, _R.values);
      await _tap(tester, 'Open host');
      await _tap(tester, 'A push b');
      expect(router.delegate.currentUri.toString(), '/host/!a/b');

      await _systemBack(tester);
      _expectState(
          router,
          [
            _R.home.page(),
            _R.host.page(children: [_R.a.page()])
          ],
          '/host/!a');
      expect(find.text('Page A'), findsOneWidget);

      // One nested page left: the pop goes to the root stack.
      await _systemBack(tester);
      _expectState(router, [_R.home.page()], '/');
      expect(find.text('Home'), findsOneWidget);
      expect(_navigators(tester), [
        ['/']
      ]);

      // The root page cannot pop: the app can exit.
      expect(await router.delegate.popRoute(), isFalse);
    });

    testWidgets('HelmRouter.pop pops the nested page and reports the result', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host/!a/b');

      expect(await HelmRouter.pop(tester.element(find.text('Page B'))), isTrue);
      await tester.pumpAndSettle();
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page()])
          ],
          '/host/!a');

      // One nested page in the only root page: nothing to pop.
      expect(await HelmRouter.pop(tester.element(find.text('Page A'))), isFalse);
      expect(router.delegate.currentUri.toString(), '/host/!a');
    });

    testWidgets('PopScope(canPop: false) on a nested page blocks system back', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');
      await _tap(tester, 'A push locked');
      final locked = [
        _R.host.page(children: [_R.a.page(), _R.locked.page()])
      ];
      _expectState(router, locked, '/host/!a/locked');

      await _systemBack(tester);
      _expectState(router, locked, '/host/!a/locked');
      expect(find.text('Locked'), findsOneWidget);
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/locked']
      ]);
    });

    testWidgets('a root page on top of the host pops first', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host/!a/b!/other');
      expect(find.text('Other'), findsOneWidget);

      await _systemBack(tester);
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page(), _R.b.page()])
          ],
          '/host/!a/b');
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/b']
      ]);

      await _systemBack(tester);
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page()])
          ],
          '/host/!a');
    });
  });

  group('Host covered by a root page', () {
    testWidgets('the nested stack stays and shows again after back', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');
      await _tap(tester, 'A push b');
      await _tap(tester, 'Host push other');
      final covered = [
        _R.host.page(children: [_R.a.page(), _R.b.page()]),
        _R.other.page()
      ];
      _expectState(router, covered, '/host/!a/b!/other');
      expect(_navigators(tester), [
        ['/host', '/other']
      ]);

      await _systemBack(tester);
      _expectState(router, [covered.first], '/host/!a/b');
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/b']
      ]);
      expect(find.text('Page B'), findsOneWidget);
    });

    testWidgets('widget state of host and nested pages survives', (tester) async {
      await _pump(tester, _R.values, url: '/side');
      await _tap(tester, 'Add Side');
      await _tap(tester, 'Add A');
      await _tap(tester, 'Add A');

      await _tap(tester, 'Side push other');
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('A: 2'), findsNothing);

      await _systemBack(tester);
      expect(find.text('Side: 1'), findsOneWidget);
      expect(find.text('A: 2'), findsOneWidget);
    });
  });

  group('Two-level nesting', () {
    const url = '/outer/!mid/!leaf/detail/7!/b';

    testWidgets('deep link builds both levels', (tester) async {
      final router = await _pump(tester, _R.values, url: url, guards: [_homeFirst]);

      _expectState(
        router,
        [
          _R.home.page(),
          _R.outer.page(children: [
            _R.mid.page(children: [
              _R.leaf.page(),
              _R.detail.page(pathParams: {'id': '7'})
            ]),
            _R.b.page(),
          ]),
        ],
        url,
      );
      // `b` covers `mid`, so the navigator of `mid` is offstage.
      expect(_navigators(tester), [
        ['/', '/outer'],
        ['/mid', '/b']
      ]);
      expect(find.text('Page B'), findsOneWidget);
    });

    testWidgets('system back pops one level at a time', (tester) async {
      final router = await _pump(tester, _R.values, url: url, guards: [_homeFirst]);

      await _systemBack(tester);
      expect(router.delegate.currentUri.toString(), '/outer/!mid/!leaf/detail/7');
      expect(_navigators(tester), [
        ['/', '/outer'],
        ['/mid'],
        ['/leaf', '/detail/7']
      ]);
      expect(find.text('Detail 7'), findsOneWidget);

      await _systemBack(tester);
      expect(router.delegate.currentUri.toString(), '/outer/!mid/!leaf');
      expect(_navigators(tester), [
        ['/', '/outer'],
        ['/mid'],
        ['/leaf']
      ]);

      // Both nested stacks have one page: the pop goes to the root stack.
      await _systemBack(tester);
      _expectState(router, [_R.home.page()], '/');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a push goes to the deepest stack', (tester) async {
      final router = await _pump(tester, _R.values);
      await _tap(tester, 'Open outer');
      _expectState(
        router,
        [
          _R.home.page(),
          _R.outer.page(children: [
            _R.mid.page(children: [_R.leaf.page()])
          ])
        ],
        '/outer/!mid/!leaf',
      );

      await _tap(tester, 'Leaf push detail 7');
      _expectState(
        router,
        [
          _R.home.page(),
          _R.outer.page(children: [
            _R.mid.page(children: [
              _R.leaf.page(),
              _R.detail.page(pathParams: {'id': '7'})
            ]),
          ]),
        ],
        '/outer/!mid/!leaf/detail/7',
      );
      expect(_navigators(tester), [
        ['/', '/outer'],
        ['/mid'],
        ['/leaf', '/detail/7']
      ]);

      // The AppBar back button of the deepest page pops only the deepest stack.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/outer/!mid/!leaf');
    });
  });

  group('Master-detail', () {
    testWidgets('host content and its state stay while the nested stack changes', (tester) async {
      final router = await _pump(tester, _R.values, url: '/side');
      await _tap(tester, 'Add Side');
      await _tap(tester, 'Add Side');
      await tester.enterText(find.byType(TextField), 'draft');

      await _tap(tester, 'A push b');
      expect(find.text('Page B'), findsOneWidget);
      expect(find.text('Side: 2'), findsOneWidget);
      expect(find.text('draft'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      _expectState(
          router,
          [
            _R.side.page(children: [_R.a.page()])
          ],
          '/side/!a');
      expect(find.text('Side: 2'), findsOneWidget);
      expect(find.text('draft'), findsOneWidget);
    });

    testWidgets('a nested page keeps its state when a page is pushed on top and popped', (tester) async {
      await _pump(tester, _R.values, url: '/side');
      await _tap(tester, 'Add A');
      expect(find.text('A: 1'), findsOneWidget);

      await _tap(tester, 'A push b');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('A: 1'), findsOneWidget);
    });

    testWidgets('replacing the nested stack keeps the host state', (tester) async {
      final router = await _pump(tester, _R.values, url: '/side/!a/b');
      await _tap(tester, 'Add Side');

      HelmRouter.change(_appContext(tester), (pages) => pages.updateAt([0], (_) => [_R.products.page()]));
      await tester.pumpAndSettle();
      _expectState(
          router,
          [
            _R.side.page(children: [_R.products.page()])
          ],
          '/side/!products');
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Side: 1'), findsOneWidget);
    });
  });

  group('Dialog in the nested stack', () {
    testWidgets('shows, and system back closes it', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host');

      await _tap(tester, 'A push dialog');
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page(), _R.dialog.page()])
          ],
          '/host/!a/dialog');
      expect(_navigators(tester), [
        ['/host'],
        ['/a', '/dialog']
      ]);
      expect(find.text('Dialog'), findsOneWidget);
      expect(find.text('Page A'), findsOneWidget);

      await _systemBack(tester);
      _expectState(
          router,
          [
            _R.host.page(children: [_R.a.page()])
          ],
          '/host/!a');
      expect(find.text('Dialog'), findsNothing);
      expect(find.text('Page A'), findsOneWidget);
    });
  });

  group('Programmatic changes', () {
    testWidgets('replaceAll with nested children', (tester) async {
      final router = await _pump(tester, _R.values);
      final next = [
        _R.home.page(),
        _R.host.page(children: [
          _R.b.page(),
          _R.product.page(pathParams: {'pid': '9'})
        ]),
      ];

      HelmRouter.replaceAll(_appContext(tester), next);
      await tester.pumpAndSettle();
      _expectState(router, next, '/host/!b/products/9');
      expect(_navigators(tester), [
        ['/', '/host'],
        ['/b', '/products/9']
      ]);
      expect(find.text('Product 9'), findsOneWidget);
    });

    testWidgets('changeQueryParams reaches nested pages', (tester) async {
      final router = await _pump(tester, _R.values, url: '/host/!a/b');
      expect(find.text('B query: {}'), findsOneWidget);

      HelmRouter.changeQueryParams(_appContext(tester), queryParams: {'q': '1'});
      await tester.pumpAndSettle();
      final query = {'q': '1'};
      _expectState(
        router,
        [
          _R.host.page(queryParams: query, children: [_R.a.page(queryParams: query), _R.b.page(queryParams: query)])
        ],
        '/host/!a/b?q=1',
      );
      expect(find.text('B query: {q: 1}'), findsOneWidget);

      HelmRouter.changeQueryParams(_appContext(tester), queryParams: {'q': ''});
      await tester.pumpAndSettle();
      expect(router.delegate.currentUri.toString(), '/host/!a/b');
      expect(find.text('B query: {}'), findsOneWidget);
    });

    testWidgets('popUntilRoot drops the host and its nested stack', (tester) async {
      final router = await _pump(tester, _R.values);
      await _tap(tester, 'Open host');
      await _tap(tester, 'A push b');

      HelmRouter.popUntilRoot(_appContext(tester));
      await tester.pumpAndSettle();
      _expectState(router, [_R.home.page()], '/');
      expect(_navigators(tester), [
        ['/']
      ]);
    });
  });

  group('Observers and transitions', () {
    /// A root page with a nested stack. `nestedHome` can push `detail` and `other`.
    ({List<Routable> routes, Routable detail}) app({
      List<NavigatorObserver> nestedObservers = const [],
      TransitionDelegate<Object?>? transitionDelegate,
    }) {
      late final _Route nestedHome;
      late final _Route detail;
      late final _Route other;
      final root = _Route(
        '/',
        (_, __) => NestedNavigator(
          initialRoute: nestedHome,
          observers: nestedObservers,
          transitionDelegate: transitionDelegate,
          builder: (context, child) => Scaffold(body: child),
        ),
      );
      nestedHome = _Route(
        '/nested-home',
        (_, __) => Column(children: [
          _pushButton('Push detail', () => detail),
          _pushButton('Push other', () => other, root: true),
        ]),
      );
      detail = _Route('/detail', (_, __) => const Text('Detail'));
      other = _Route('/other', (_, __) => const Text('Other'));
      return (routes: [root, nestedHome, detail, other], detail: detail);
    }

    testWidgets('a nested observer sees nested pushes only', (tester) async {
      final nested = _PushLog();
      final root = _PushLog();
      await _pump(tester, app(nestedObservers: [nested]).routes, observers: [root]);
      expect(nested.pushed, ['/nested-home']);
      expect(root.pushed, ['/']);

      await _tap(tester, 'Push detail');
      expect(nested.pushed, ['/nested-home', '/detail']);
      expect(root.pushed, ['/']);

      // A root push is not seen by the nested observer.
      await _systemBack(tester);
      await _tap(tester, 'Push other');
      expect(nested.pushed, ['/nested-home', '/detail']);
      expect(root.pushed, ['/', '/other']);
    });

    testWidgets('a custom transition delegate runs for nested changes only', (tester) async {
      final delegate = _InstantDelegate();
      await _pump(tester, app(transitionDelegate: delegate).routes);
      final afterFill = delegate.resolves;

      await tester.tap(find.text('Push detail'));
      await tester.pump();
      expect(delegate.resolves, greaterThan(afterFill));
      // The delegate adds the page without animation.
      expect(ModalRoute.of(tester.element(find.text('Detail')))!.animation!.value, 1.0);
      await tester.pumpAndSettle();

      await _systemBack(tester);
      final afterNested = delegate.resolves;
      await _tap(tester, 'Push other');
      expect(find.text('Other'), findsOneWidget);
      expect(delegate.resolves, afterNested);
    });

    testWidgets('without a delegate the default animation runs for nested changes', (tester) async {
      await _pump(tester, app().routes);

      await tester.tap(find.text('Push detail'));
      await tester.pump();
      expect(ModalRoute.of(tester.element(find.text('Detail')))!.animation!.value, lessThan(1.0));
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsOneWidget);
    });
  });

  group('History', () {
    testWidgets('the initial nested fill replaces the history entry', (tester) async {
      final history = <(String, bool)>[];
      await _pump(tester, _R.values, url: '/host', history: history);

      expect(history, isNotEmpty);
      expect(history.map((r) => r.$2), everyElement(isTrue));
      expect(history.last.$1, '/host/!a');
    });

    testWidgets('a push into the nested stack adds one entry', (tester) async {
      final history = <(String, bool)>[];
      await _pump(tester, _R.values, url: '/host', history: history);
      history.clear();

      await _tap(tester, 'A push b');
      expect(history, [('/host/!a/b', false)]);
    });

    testWidgets('a pushed host page adds one entry, then its nested fill replaces it', (tester) async {
      final history = <(String, bool)>[];
      await _pump(tester, _R.values, history: history);
      history.clear();

      await _tap(tester, 'Open host');
      expect(history.where((r) => !r.$2).map((r) => r.$1), ['/host']);
      expect(history.last, ('/host/!a', true));
    });
  });

  group('Restoration', () {
    testWidgets('nested stacks come back after a restart although the platform URL is /', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async => null);
      final routers = <HelmRouter>[];

      await tester.pumpWidget(_RestorableApp(onRouter: routers.add));
      await tester.pumpAndSettle();
      await _tap(tester, 'Open host');
      await _tap(tester, 'A push b');
      final before = routers.single.delegate.currentConfiguration;
      expect(routers.single.delegate.currentUri.toString(), '/host/!a/b');

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(routers, hasLength(2));
      expect(routers.last.delegate.currentConfiguration, before);
      expect(routers.last.delegate.currentUri.toString(), '/host/!a/b');
      expect(find.text('Page B'), findsOneWidget);

      // The restored nested navigator takes part in system back.
      await _systemBack(tester);
      expect(routers.last.delegate.currentUri.toString(), '/host/!a');
    });
  });
}

class _RestorableApp extends StatefulWidget {
  const _RestorableApp({required this.onRouter});

  final void Function(HelmRouter router) onRouter;

  @override
  State<_RestorableApp> createState() => _RestorableAppState();
}

class _RestorableAppState extends State<_RestorableApp> {
  late final router = HelmRouter(routes: _R.values, guards: [_homeFirst], enableLogs: false);

  @override
  void initState() {
    super.initState();
    widget.onRouter(router);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(restorationScopeId: 'app', routerConfig: router);
}
