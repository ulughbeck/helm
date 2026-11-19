import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransition;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

// The test app: flat root stack only.
enum R with Routable {
  home('/'),
  settings('/settings'),
  products('/products'),
  product('/products/{pid+}'),
  map('/map/@{lat},{lng}'),
  login('/login'),
  account('/account'),
  about('/about', PageType.cupertino),
  confirm('/confirm', PageType.dialog),
  share('/share', PageType.bottomSheet),
  locked('/locked'),
  notFound('/404');

  const R(this.path, [this.pageType = PageType.material]);

  @override
  final String path;
  @override
  final PageType pageType;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        home => const _Home(),
        settings => const _Screen('Settings'),
        products => const _Screen('Products'),
        product => _Screen('Product ${pathParams['pid']}'),
        map => _Screen('Map ${pathParams['lat']} ${pathParams['lng']}'),
        login => const _Login(),
        account => const _Screen('Account'),
        about => const _Screen('About'),
        confirm => const AlertDialog(title: Text('Confirm?')),
        share => const Material(child: SizedBox(height: 200, child: Text('Share sheet'))),
        locked => const PopScope(canPop: false, child: _Screen('Locked')),
        notFound => const _Screen('Not found'),
      };
}

class _Screen extends StatelessWidget {
  const _Screen(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Column(children: [
          TextButton(onPressed: () => HelmRouter.push(context, R.settings), child: const Text('Open settings')),
          TextButton(
            onPressed: () => HelmRouter.push(context, R.product, pathParams: {'pid': '7'}),
            child: const Text('Open product 7'),
          ),
          TextButton(onPressed: () => HelmRouter.push(context, R.confirm), child: const Text('Open confirm')),
        ]),
      );
}

class _Login extends StatelessWidget {
  const _Login();

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Login')));
}

/// Page names of each onstage Navigator, root first.
List<List<String?>> _navigators(WidgetTester tester) => [
      for (final navigator in tester.widgetList<Navigator>(find.byType(Navigator)))
        [for (final page in navigator.pages) page.name],
    ];

NavigationState _stateOf(HelmRouter router) => router.delegate.currentConfiguration;
String _url(HelmRouter router) => router.delegate.currentUri.toString();

/// Empty state becomes the 404 page.
NavigationState _notFoundGuard(NavigationState pages) => pages.isEmpty ? [R.notFound.page()] : pages;

/// Every state except the 404 page starts with home.
NavigationState _homeGuard(NavigationState pages) =>
    pages.first.route == R.home || pages.first.route == R.notFound ? pages : [R.home.page(), ...pages];

const _guards = [_notFoundGuard, _homeGuard];

/// A context below the root Navigator, like the context of a screen.
BuildContext _ctx(WidgetTester tester) => tester.element(find.byType(Scaffold).last);

Future<void> _systemBack(WidgetTester tester) async {
  expect(await tester.binding.handlePopRoute(), isTrue);
  await tester.pumpAndSettle();
}

/// The platform pushes new route information, like a deep link while the app runs.
Future<void> _deepLink(WidgetTester tester, String location) async {
  final message = const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': location}));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

class _Route with Routable {
  _Route(this.path, this._build, {this.transitionDelegate});

  @override
  final String path;
  @override
  final TransitionDelegate<Object?>? transitionDelegate;
  final Widget Function(Map<String, String> pathParams, Map<String, String> queryParams) _build;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => _build(pathParams, queryParams);
}

Future<HelmRouter> _pump(
  WidgetTester tester,
  List<Routable> routes, {
  String url = '/',
  List<NavigationGuard> guards = const [],
  Listenable? refresh,
  List<NavigatorObserver> observers = const [],
  TransitionDelegate<Object?> defaultTransitionDelegate = const DefaultTransitionDelegate<Object?>(),
  List<(String, bool)>? reports,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
    if (reports != null && call.method == 'routeInformationUpdated') {
      final args = call.arguments as Map<Object?, Object?>;
      reports.add((args['uri']! as String, args['replace']! as bool));
    }
    return null;
  });
  tester.platformDispatcher.defaultRouteNameTestValue = url;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  final router = HelmRouter(
    routes: routes,
    guards: guards,
    refresh: refresh,
    observers: observers,
    defaultTransitionDelegate: defaultTransitionDelegate,
    enableLogs: false,
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

class _CountingDelegate extends DefaultTransitionDelegate<Object?> {
  int calls = 0;

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord> locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>> pageRouteToPagelessRoutes,
  }) {
    calls++;
    return super.resolve(
      newPageRouteHistory: newPageRouteHistory,
      locationToExitingPageRoute: locationToExitingPageRoute,
      pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
    );
  }
}

class _Recorder extends NavigatorObserver {
  final events = <(String, Object?)>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add(('push ${route.settings.name}', route.settings.arguments));

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add(('pop ${route.settings.name}', route.settings.arguments));
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Count: $count')),
        body: TextButton(onPressed: () => setState(() => count++), child: const Text('Increment')),
      );
}

class _RestorableApp extends StatefulWidget {
  const _RestorableApp({required this.onRouter});
  final void Function(HelmRouter router) onRouter;

  @override
  State<_RestorableApp> createState() => _RestorableAppState();
}

class _RestorableAppState extends State<_RestorableApp> {
  late final HelmRouter router = HelmRouter(routes: R.values, guards: _guards, enableLogs: false);

  @override
  void initState() {
    super.initState();
    widget.onRouter(router);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(restorationScopeId: 'app', routerConfig: router);
}

void main() {
  group('cold start deep links', () {
    final cases = <({
      String name,
      String url,
      NavigationState Function() tree,
      String expectedUrl,
      String text,
    })>[
      (name: 'root', url: '/', tree: () => [R.home.page()], expectedUrl: '/', text: 'Home'),
      (name: 'leading slashes normalize', url: '///', tree: () => [R.home.page()], expectedUrl: '/', text: 'Home'),
      (
        name: 'known route gets home below it',
        url: '/settings',
        tree: () => [R.home.page(), R.settings.page()],
        expectedUrl: '/settings',
        text: 'Settings',
      ),
      (
        name: 'unknown URL shows 404',
        url: '/this-does-not-exist',
        tree: () => [R.notFound.page()],
        expectedUrl: '/404',
        text: 'Not found',
      ),
      (
        name: 'unknown nested URL shows 404',
        url: '/some/unknown/route',
        tree: () => [R.notFound.page()],
        expectedUrl: '/404',
        text: 'Not found',
      ),
      (
        name: 'known followed by unknown keeps the known route',
        url: '/settings/unknown',
        tree: () => [R.home.page(), R.settings.page()],
        expectedUrl: '/settings',
        text: 'Settings',
      ),
      (
        name: 'known followed by many unknown keeps the known route',
        url: '/settings/many/unknown/routes',
        tree: () => [R.home.page(), R.settings.page()],
        expectedUrl: '/settings',
        text: 'Settings',
      ),
      (
        name: 'unknown followed by known shows 404',
        url: '/unknown/settings',
        tree: () => [R.notFound.page()],
        expectedUrl: '/404',
        text: 'Not found',
      ),
      (
        name: 'malformed URL with "!" does not hang',
        url: '/settings!',
        tree: () => [R.notFound.page()],
        expectedUrl: '/404',
        text: 'Not found',
      ),
      (
        name: 'query params reach every page',
        url: '/products/1?utm=x',
        tree: () => [
              R.home.page(),
              R.products.page(queryParams: {'utm': 'x'}),
              R.product.page(pathParams: {'pid': '1'}, queryParams: {'utm': 'x'}),
            ],
        expectedUrl: '/products/1?utm=x',
        text: 'Product 1',
      ),
      (
        name: 'parent pages are added from the URL',
        url: '/products/1',
        tree: () => [
              R.home.page(),
              R.products.page(),
              R.product.page(pathParams: {'pid': '1'})
            ],
        expectedUrl: '/products/1',
        text: 'Product 1',
      ),
      (
        name: 'percent-encoded path param is decoded',
        url: '/products/a%20b',
        tree: () => [
              R.home.page(),
              R.products.page(),
              R.product.page(pathParams: {'pid': 'a b'})
            ],
        expectedUrl: '/products/a%20b',
        text: 'Product a b',
      ),
      (
        name: 'sequence param makes one page per segment',
        url: '/products/1/2/3',
        tree: () => [
              R.home.page(),
              R.products.page(),
              for (final id in ['1', '2', '3']) R.product.page(pathParams: {'pid': id}),
            ],
        expectedUrl: '/products/1/2/3',
        text: 'Product 3',
      ),
      (
        name: '"~" ends a sequence before another route',
        url: '/products/1/2/~/settings',
        tree: () => [
              R.home.page(),
              R.products.page(),
              R.product.page(pathParams: {'pid': '1'}),
              R.product.page(pathParams: {'pid': '2'}),
              R.settings.page(),
            ],
        expectedUrl: '/products/1/2/~/settings',
        text: 'Settings',
      ),
      (
        name: 'pattern segment fills two params',
        url: '/map/@41.3,69.2',
        tree: () => [
              R.home.page(),
              R.map.page(pathParams: {'lat': '41.3', 'lng': '69.2'})
            ],
        expectedUrl: '/map/@41.3,69.2',
        text: 'Map 41.3 69.2',
      ),
    ];

    for (final c in cases) {
      testWidgets(c.name, (tester) async {
        final router = await _pump(tester, R.values, url: c.url, guards: _guards);
        expect(_stateOf(router), c.tree());
        expect(_url(router), c.expectedUrl);
        expect(find.text(c.text), findsOneWidget);
        expect(_navigators(tester), [
          [for (final page in c.tree()) page.name],
        ]);
      });
    }

    testWidgets('without guards an unknown URL leaves an empty app', (tester) async {
      final router = await _pump(tester, R.values, url: '/nope');
      expect(_stateOf(router), isEmpty);
      expect(find.byType(Scaffold), findsNothing);
    });
  });

  group('deep link while the app runs', () {
    testWidgets('a new URL replaces the stack', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings', guards: _guards);

      await _deepLink(tester, '/products/1/2');

      expect(_stateOf(router), [
        R.home.page(),
        R.products.page(),
        R.product.page(pathParams: {'pid': '1'}),
        R.product.page(pathParams: {'pid': '2'}),
      ]);
      expect(_url(router), '/products/1/2');
      expect(find.text('Product 2'), findsOneWidget);
      expect(_navigators(tester), [
        ['/', '/products', '/products/1', '/products/2'],
      ]);
    });

    testWidgets('an unknown URL shows 404', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings', guards: _guards);

      await _deepLink(tester, '/nope');

      expect(_stateOf(router), [R.notFound.page()]);
      expect(find.text('Not found'), findsOneWidget);
    });

    testWidgets('the app can go back after a deep link', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      await _deepLink(tester, '/products/1?utm=x');
      await _systemBack(tester);

      expect(_url(router), '/products?utm=x');
      expect(find.text('Products'), findsOneWidget);
    });
  });

  group('guards', () {
    testWidgets('a guard chain runs in order', (tester) async {
      NavigationState rename(NavigationState pages, R from, R to) =>
          [for (final page in pages) page.route == from ? to.page() : page];
      NavigationState settingsToAccount(NavigationState pages) => rename(pages, R.settings, R.account);
      NavigationState accountToLogin(NavigationState pages) => rename(pages, R.account, R.login);

      final forward = await _pump(tester, R.values, url: '/settings', guards: [settingsToAccount, accountToLogin]);
      expect(_stateOf(forward), [R.login.page()]);
      expect(find.text('Login'), findsOneWidget);

      final backward = await _pump(tester, R.values, url: '/settings', guards: [accountToLogin, settingsToAccount]);
      expect(_stateOf(backward), [R.account.page()]);
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('guards also run on changes from the app', (tester) async {
      await _pump(tester, R.values, guards: _guards);
      final router = HelmRouter.delegateOf(_ctx(tester));

      HelmRouter.replaceAll(_ctx(tester), const []);
      await tester.pumpAndSettle();

      expect(router.currentConfiguration, [R.notFound.page()]);
      expect(find.text('Not found'), findsOneWidget);
    });

    group('auth', () {
      late ValueNotifier<bool> loggedIn;

      setUp(() => loggedIn = ValueNotifier(false));
      tearDown(() => loggedIn.dispose());

      NavigationState authGuard(NavigationState pages) =>
          loggedIn.value || pages.findByRoute(R.account) == null ? pages : [R.home.page(), R.login.page()];

      testWidgets('a blocked push goes to login, and after login the page opens', (tester) async {
        final router = await _pump(tester, R.values, guards: [authGuard, ..._guards], refresh: loggedIn);

        HelmRouter.push(_ctx(tester), R.account);
        await tester.pumpAndSettle();
        expect(_stateOf(router), [R.home.page(), R.login.page()]);
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Account'), findsNothing);

        loggedIn.value = true;
        HelmRouter.replaceAll(_ctx(tester), [R.home.page(), R.account.page()]);
        await tester.pumpAndSettle();

        expect(_stateOf(router), [R.home.page(), R.account.page()]);
        expect(find.text('Account'), findsOneWidget);
      });

      testWidgets('a deep link to a protected page opens login', (tester) async {
        final router = await _pump(tester, R.values, url: '/account', guards: [authGuard, ..._guards]);

        expect(_stateOf(router), [R.home.page(), R.login.page()]);
        expect(_url(router), '/login');
      });

      testWidgets('logout redirects at once, without a frame of the old state', (tester) async {
        loggedIn.value = true;
        final router =
            await _pump(tester, R.values, url: '/account', guards: [authGuard, ..._guards], refresh: loggedIn);
        expect(find.text('Account'), findsOneWidget);
        var notifications = 0;
        router.delegate.addListener(() => notifications++);

        loggedIn.value = false;

        expect(_stateOf(router), [R.home.page(), R.login.page()]);
        expect(notifications, 1);
        await tester.pumpAndSettle();
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Account'), findsNothing);
      });

      testWidgets('a refresh that changes nothing does not notify', (tester) async {
        final router =
            await _pump(tester, R.values, url: '/settings', guards: [authGuard, ..._guards], refresh: loggedIn);
        var notifications = 0;
        router.delegate.addListener(() => notifications++);

        loggedIn.value = true;
        loggedIn.value = false;

        expect(notifications, 0);
        expect(_stateOf(router), [R.home.page(), R.settings.page()]);
      });
    });
  });

  group('HelmRouter API', () {
    testWidgets('push and back with the AppBar button', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(_stateOf(router), [R.home.page(), R.settings.page()]);
      expect(_url(router), '/settings');
      expect(find.text('Settings'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_stateOf(router), [R.home.page()]);
      expect(_url(router), '/');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('push adds missing parent pages', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      await tester.tap(find.text('Open product 7'));
      await tester.pumpAndSettle();

      expect(_stateOf(router), [
        R.home.page(),
        R.products.page(),
        R.product.page(pathParams: {'pid': '7'})
      ]);
      expect(_url(router), '/products/7');
      expect(_navigators(tester), [
        ['/', '/products', '/products/7'],
      ]);
    });

    testWidgets('push does not duplicate parents that are already in the stack', (tester) async {
      final router = await _pump(tester, R.values, url: '/products', guards: _guards);

      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': '1'});
      await tester.pumpAndSettle();

      expect(_stateOf(router), [
        R.home.page(),
        R.products.page(),
        R.product.page(pathParams: {'pid': '1'})
      ]);
    });

    testWidgets('push of a sequence route on the same route appends to the sequence', (tester) async {
      final router = await _pump(tester, R.values, url: '/products/1', guards: _guards);

      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': '2'});
      await tester.pumpAndSettle();

      expect(_stateOf(router), [
        R.home.page(),
        R.products.page(),
        R.product.page(pathParams: {'pid': '1'}),
        R.product.page(pathParams: {'pid': '2'}),
      ]);
      expect(_url(router), '/products/1/2');
      expect(find.text('Product 2'), findsOneWidget);
    });

    testWidgets('push of a sequence route after another route ends the sequence with "~"', (tester) async {
      final router = await _pump(tester, R.values, url: '/products/1', guards: _guards);

      HelmRouter.push(_ctx(tester), R.settings);
      await tester.pumpAndSettle();
      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': '2'});
      await tester.pumpAndSettle();

      expect(_stateOf(router).map((p) => p.name), ['/', '/products', '/products/1', '/settings', '/products/2']);
      expect(_url(router), '/products/1/~/settings/products/2');
    });

    testWidgets('push merges the current query params into the new pages', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings?utm=x', guards: _guards);

      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': '1'}, queryParams: {'ref': 'a'});
      await tester.pumpAndSettle();

      final query = {'utm': 'x', 'ref': 'a'};
      expect(_stateOf(router), [
        R.home.page(),
        R.settings.page(queryParams: {'utm': 'x'}),
        R.products.page(queryParams: query),
        R.product.page(pathParams: {'pid': '1'}, queryParams: query),
      ]);
      expect(HelmRouter.currentQueryParams(_ctx(tester)), query);
    });

    testWidgets('push encodes path param values in the URL', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': 'a/b c'});
      await tester.pumpAndSettle();

      expect(_url(router), '/products/a%2Fb%20c');
      expect(find.text('Product a/b c'), findsOneWidget);
    });

    testWidgets('push with a missing path param throws and keeps the state', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);
      final before = _stateOf(router);

      expect(() => HelmRouter.push(_ctx(tester), R.product), throwsArgumentError);
      await tester.pumpAndSettle();

      expect(_stateOf(router), before);
      expect(_url(router), '/');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('pop returns true and removes the top page', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings', guards: _guards);

      final popped = HelmRouter.pop(_ctx(tester));
      await tester.pumpAndSettle();

      expect(await popped, isTrue);
      expect(_stateOf(router), [R.home.page()]);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('pop returns false at the last page', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      expect(await HelmRouter.pop(_ctx(tester)), isFalse);
      await tester.pumpAndSettle();

      expect(_stateOf(router), [R.home.page()]);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('popUntilRoot returns to home', (tester) async {
      final router = await _pump(tester, R.values, url: '/products/1/2?utm=x', guards: _guards);

      HelmRouter.popUntilRoot(_ctx(tester));
      await tester.pumpAndSettle();

      expect(_stateOf(router), [R.home.page()]);
      expect(_url(router), '/');
      expect(find.text('Home'), findsOneWidget);
      expect(_navigators(tester), [
        ['/'],
      ]);
    });

    testWidgets('replaceAll sets a new stack', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      HelmRouter.replaceAll(_ctx(tester), [
        R.home.page(),
        R.products.page(),
        R.product.page(pathParams: {'pid': 'x'}),
      ]);
      await tester.pumpAndSettle();

      expect(_url(router), '/products/x');
      expect(find.text('Product x'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Products'), findsOneWidget);
    });

    testWidgets('replaceWithRoute leaves only that page, plus what the guards add', (tester) async {
      final router = await _pump(tester, R.values, url: '/products/1', guards: _guards);

      HelmRouter.replaceWithRoute(_ctx(tester), R.map, pathParams: {'lat': '1', 'lng': '2'}, queryParams: {'z': '3'});
      await tester.pumpAndSettle();

      expect(_stateOf(router), [
        R.home.page(),
        R.map.page(pathParams: {'lat': '1', 'lng': '2'}, queryParams: {'z': '3'})
      ]);
      expect(_url(router), '/map/@1,2?z=3');
      expect(find.text('Map 1 2'), findsOneWidget);
    });

    testWidgets('change replaces the state with the result of a function', (tester) async {
      final router = await _pump(tester, R.values, url: '/products/1/2', guards: _guards);

      HelmRouter.change(_ctx(tester), (pages) => pages.sublist(0, pages.length - 1));
      await tester.pumpAndSettle();

      expect(_url(router), '/products/1');
      expect(find.text('Product 1'), findsOneWidget);
    });

    testWidgets('changeQueryParams sets params on all pages, and an empty value removes one', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings?a=1', guards: _guards);

      HelmRouter.changeQueryParams(_ctx(tester), queryParams: {'b': '2'});
      await tester.pumpAndSettle();
      expect(HelmRouter.currentQueryParams(_ctx(tester)), {'a': '1', 'b': '2'});
      expect(_stateOf(router).last.queryParams, {'a': '1', 'b': '2'});
      expect(router.delegate.currentUri!.queryParameters, {'a': '1', 'b': '2'});

      HelmRouter.changeQueryParams(_ctx(tester), queryParams: {'b': ''});
      await tester.pumpAndSettle();
      expect(HelmRouter.currentQueryParams(_ctx(tester)), {'a': '1'});
      expect(_stateOf(router).last, R.settings.page(queryParams: {'a': '1'}));
      expect(_url(router), '/settings?a=1');
    });

    testWidgets('changeQueryParams rebuilds screens that read query params', (tester) async {
      final routes = [
        _Route('/', (_, query) => Scaffold(appBar: AppBar(title: Text('Query $query')))),
      ];
      await _pump(tester, routes);
      expect(find.text('Query {}'), findsOneWidget);

      HelmRouter.changeQueryParams(_ctx(tester), queryParams: {'sort': 'price'});
      await tester.pumpAndSettle();

      expect(find.text('Query {sort: price}'), findsOneWidget);
    });

    testWidgets('state, currentUri and path params describe the current stack', (tester) async {
      await _pump(tester, R.values, url: '/products/1/2?utm=x', guards: _guards);
      final context = _ctx(tester);

      expect(HelmRouter.state(context).map((p) => p.name), ['/', '/products', '/products/1', '/products/2']);
      expect(HelmRouter.currentUri(context).toString(), '/products/1/2?utm=x');
      expect(HelmRouter.currentQueryParams(context), {'utm': 'x'});
      expect(HelmRouter.currentPathParams(context), {'pid-0': '1', 'pid-1': '2'});
    });

    testWidgets('currentPathParams includes params of a pattern segment', (tester) async {
      await _pump(tester, R.values, url: '/map/@1,2', guards: _guards);

      expect(HelmRouter.currentPathParams(_ctx(tester)), {'lat-0': '1', 'lng-0': '2'});
    });

    testWidgets('delegateOf outside a HelmRouter throws a FlutterError', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => SizedBox(key: ValueKey(context = c)))));

      expect(() => HelmRouter.delegateOf(context), throwsFlutterError);
    });
  });

  group('page types', () {
    testWidgets('a dialog shows over the page below, and system back closes it', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      await tester.tap(find.text('Open confirm'));
      await tester.pumpAndSettle();
      expect(_stateOf(router), [R.home.page(), R.confirm.page()]);
      expect(_url(router), '/confirm');
      expect(find.text('Confirm?'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      await _systemBack(tester);
      expect(_stateOf(router), [R.home.page()]);
      expect(_url(router), '/');
      expect(find.text('Confirm?'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a tap on the barrier dismisses the dialog and updates the state', (tester) async {
      final router = await _pump(tester, R.values, url: '/confirm', guards: _guards);
      expect(find.text('Confirm?'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(_stateOf(router), [R.home.page()]);
      expect(_url(router), '/');
      expect(find.text('Confirm?'), findsNothing);
    });

    testWidgets('a deep link to a dialog URL shows the page below and the dialog', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings/confirm', guards: _guards);

      expect(_stateOf(router), [R.home.page(), R.settings.page(), R.confirm.page()]);
      expect(_navigators(tester), [
        ['/', '/settings', '/confirm'],
      ]);
      expect(find.text('Confirm?'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('a bottom sheet shows over the page below, and system back closes it', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings/share', guards: _guards);
      expect(_stateOf(router), [R.home.page(), R.settings.page(), R.share.page()]);
      expect(find.text('Share sheet'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await _systemBack(tester);

      expect(_stateOf(router), [R.home.page(), R.settings.page()]);
      expect(_url(router), '/settings');
      expect(find.text('Share sheet'), findsNothing);
    });

    testWidgets('a tap on the barrier dismisses the bottom sheet and updates the state', (tester) async {
      final router = await _pump(tester, R.values, url: '/share', guards: _guards);
      expect(find.text('Share sheet'), findsOneWidget);

      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect(_stateOf(router), [R.home.page()]);
      expect(find.text('Share sheet'), findsNothing);
    });

    testWidgets('a cupertino page opens and goes back', (tester) async {
      final router = await _pump(tester, R.values, guards: _guards);

      HelmRouter.push(_ctx(tester), R.about);
      await tester.pumpAndSettle();
      expect(find.text('About'), findsOneWidget);
      expect(find.byType(CupertinoPageTransition), findsWidgets);
      expect(_stateOf(router), [R.home.page(), R.about.page()]);

      await _systemBack(tester);
      expect(_stateOf(router), [R.home.page()]);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('system back', () {
    testWidgets('pops pages one by one, then reports that the app can exit', (tester) async {
      final router = await _pump(tester, R.values, url: '/products/1', guards: _guards);

      await _systemBack(tester);
      expect(_url(router), '/products');
      await _systemBack(tester);
      expect(_url(router), '/');
      expect(find.text('Home'), findsOneWidget);

      expect(await router.delegate.popRoute(), isFalse);
      expect(await tester.binding.handlePopRoute(), isFalse);
      expect(_stateOf(router), [R.home.page()]);
    });

    testWidgets('a pageless dialog closes first and the state stays the same', (tester) async {
      final router = await _pump(tester, R.values, url: '/settings', guards: _guards);
      final before = _stateOf(router);

      showDialog<void>(context: _ctx(tester), builder: (_) => const AlertDialog(title: Text('Pageless')));
      await tester.pumpAndSettle();
      expect(find.text('Pageless'), findsOneWidget);
      expect(_stateOf(router), before);

      await _systemBack(tester);
      expect(find.text('Pageless'), findsNothing);
      expect(_stateOf(router), before);
      expect(find.text('Settings'), findsOneWidget);

      await _systemBack(tester);
      expect(_stateOf(router), [R.home.page()]);
    });

    testWidgets('PopScope(canPop: false) blocks system back', (tester) async {
      final router = await _pump(tester, R.values, url: '/locked', guards: _guards);

      await _systemBack(tester);

      expect(find.text('Locked'), findsOneWidget);
      expect(_stateOf(router), [R.home.page(), R.locked.page()]);
    });
  });

  group('widget state', () {
    final routes = [
      _Route('/', (_, __) => const _Counter()),
      _Route('/other', (_, __) => const Scaffold(body: Text('Other'))),
    ];

    testWidgets('a lower page keeps its State while another page is pushed and popped', (tester) async {
      await _pump(tester, routes);
      await tester.tap(find.text('Increment'));
      await tester.tap(find.text('Increment'));
      await tester.pump();
      expect(find.text('Count: 2'), findsOneWidget);

      HelmRouter.push(_ctx(tester), routes[1]);
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
      await _systemBack(tester);

      expect(find.text('Count: 2'), findsOneWidget);
    });

    testWidgets('a page keeps its State when only query params change', (tester) async {
      await _pump(tester, routes);
      await tester.tap(find.text('Increment'));
      await tester.pump();

      HelmRouter.changeQueryParams(_ctx(tester), queryParams: {'tab': 'a'});
      await tester.pumpAndSettle();
      expect(find.text('Count: 1'), findsOneWidget);

      HelmRouter.changeQueryParams(_ctx(tester), queryParams: {'tab': ''});
      await tester.pumpAndSettle();
      expect(find.text('Count: 1'), findsOneWidget);
    });

    testWidgets('a deep link to the same URL keeps the State', (tester) async {
      await _pump(tester, routes);
      await tester.tap(find.text('Increment'));
      await tester.pump();

      await _deepLink(tester, '/');

      expect(find.text('Count: 1'), findsOneWidget);
    });
  });

  group('transition delegates', () {
    testWidgets('a route delegate runs when its route is on top, the default one otherwise', (tester) async {
      final fallback = _CountingDelegate();
      final own = _CountingDelegate();
      final home = _Route('/', (_, __) => const Scaffold(body: Text('Home')));
      final special = _Route('/special', (_, __) => const Scaffold(body: Text('Special')), transitionDelegate: own);
      final plain = _Route('/plain', (_, __) => const Scaffold(body: Text('Plain')));
      await _pump(tester, [home, special, plain], defaultTransitionDelegate: fallback);
      expect(own.calls, 0);
      final fallbackBefore = fallback.calls;

      HelmRouter.push(_ctx(tester), special);
      await tester.pumpAndSettle();
      expect(own.calls, greaterThan(0));
      expect(fallback.calls, fallbackBefore);

      final ownBefore = own.calls;
      HelmRouter.push(_ctx(tester), plain);
      await tester.pumpAndSettle();
      expect(own.calls, ownBefore);
      expect(fallback.calls, greaterThan(fallbackBefore));
      expect(find.text('Plain'), findsOneWidget);
    });
  });

  group('observers', () {
    testWidgets('get didPush and didPop with the HelmPage as arguments', (tester) async {
      final recorder = _Recorder();
      await _pump(tester, R.values, guards: _guards, observers: [recorder]);
      expect(recorder.events, [('push /', R.home.page())]);

      HelmRouter.push(_ctx(tester), R.settings);
      await tester.pumpAndSettle();
      expect(recorder.events.last, ('push /settings', R.settings.page()));

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(recorder.events.last, ('pop /settings', R.settings.page()));
      expect(recorder.events.length, 3);
    });

    testWidgets('see the pages of a deep link', (tester) async {
      final recorder = _Recorder();
      await _pump(tester, R.values, url: '/products/1', guards: _guards, observers: [recorder]);

      expect(recorder.events.map((e) => e.$1), ['push /', 'push /products', 'push /products/1']);
    });
  });

  group('route validation', () {
    final invalid = <String, List<Routable> Function()>{
      'empty route list': () => [],
      'empty path': () => [_Route('', (_, __) => const SizedBox())],
      'path without a leading slash': () => [_Route('a', (_, __) => const SizedBox())],
      'whitespace in a path': () => [_Route('/a b', (_, __) => const SizedBox())],
      'empty segment': () => [_Route('/a//b', (_, __) => const SizedBox())],
      '"!" in a path': () => [_Route('/a!', (_, __) => const SizedBox())],
      '"~" in a path': () => [_Route('/~', (_, __) => const SizedBox())],
      'same shape with different param names': () => [
            _Route('/a/{x}', (_, __) => const SizedBox()),
            _Route('/a/{y}', (_, __) => const SizedBox()),
          ],
      'same path twice': () => [
            _Route('/a', (_, __) => const SizedBox()),
            _Route('/a', (_, __) => const SizedBox()),
          ],
    };

    invalid.forEach((name, routes) {
      test('rejects $name', () {
        TestWidgetsFlutterBinding.ensureInitialized();
        expect(() => HelmRouter(routes: routes(), enableLogs: false), throwsArgumentError);
      });
    });

    test('accepts a static route next to a param route and a sequence route', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(
        () => HelmRouter(routes: [
          _Route('/a/b', (_, __) => const SizedBox()),
          _Route('/a/{x}', (_, __) => const SizedBox()),
          _Route('/a/{x+}', (_, __) => const SizedBox()),
        ], enableLogs: false),
        returnsNormally,
      );
    });
  });

  group('history reports', () {
    testWidgets('normalizing the platform URL replaces, a push and a pop add an entry', (tester) async {
      final reports = <(String, bool)>[];
      await _pump(tester, R.values, url: '/settings', guards: _guards, reports: reports);
      // The guard adds home, but the URL is the same as the platform URL.
      expect(reports, everyElement(predicate<(String, bool)>((r) => r.$2)));
      expect(reports.last.$1, '/settings');
      reports.clear();

      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': '1'});
      await tester.pumpAndSettle();
      expect(reports, [('/settings/products/1', false)]);
      reports.clear();

      await _systemBack(tester);
      expect(reports, [('/settings/products', false)]);
    });
  });

  group('restoration', () {
    testWidgets('a root stack built by pushes comes back after a restart', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async => null);
      late HelmRouter router;

      await tester.pumpWidget(_RestorableApp(onRouter: (r) => router = r));
      await tester.pumpAndSettle();
      final before = router;
      HelmRouter.push(_ctx(tester), R.settings);
      await tester.pumpAndSettle();
      HelmRouter.push(_ctx(tester), R.product, pathParams: {'pid': '5'});
      await tester.pumpAndSettle();
      final expected = _stateOf(before);
      expect(_url(before), '/settings/products/5');

      // The new router starts from the platform URL `/`, so only restoration data can bring the stack back.
      await tester.restartAndRestore();

      expect(identical(router, before), isFalse);
      expect(_stateOf(router), expected);
      expect(find.text('Product 5'), findsOneWidget);
      await _systemBack(tester);
      expect(find.text('Products'), findsOneWidget);
    });
  });
}
