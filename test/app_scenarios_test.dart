import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

// Two small apps that combine Helm features, and user journeys through them.
// After every step a journey checks the state tree, the URL and the rendered navigators.

// ---------------------------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------------------------

/// One running app. It records what the app tells the platform.
class _Run {
  _Run({bool loggedIn = false}) : session = ValueNotifier(loggedIn);

  /// Auth state. The guards read it and the router refreshes when it changes.
  final ValueNotifier<bool> session;

  /// URL reports to the platform history, in order.
  final history = <({String uri, bool replace})>[];

  /// How many times the app asked the platform to exit.
  var exits = 0;

  /// The newest router. A restart creates a new one.
  late HelmRouter router;

  NavigationState get tree => router.delegate.currentConfiguration;
  String get url => router.delegate.currentUri.toString();

  /// History entries added by navigation (not replaced).
  List<String> get pushed => [
        for (final report in history)
          if (!report.replace) report.uri,
      ];
}

class _Session extends InheritedNotifier<ValueNotifier<bool>> {
  const _Session({required ValueNotifier<bool> super.notifier, required super.child});

  static ValueNotifier<bool> of(BuildContext context) => context.getInheritedWidgetOfExactType<_Session>()!.notifier!;
}

class _App extends StatefulWidget {
  const _App({required this.run, required this.routes, required this.guards, required this.restore});

  final _Run run;
  final List<Routable> routes;
  final List<NavigationGuard> Function(ValueNotifier<bool> loggedIn) guards;
  final bool restore;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final HelmRouter router = widget.run.router = HelmRouter(
    routes: widget.routes,
    guards: widget.guards(widget.run.session),
    refresh: widget.run.session,
    enableLogs: false,
  );

  @override
  Widget build(BuildContext context) => _Session(
        notifier: widget.run.session,
        child: MaterialApp.router(restorationScopeId: widget.restore ? 'app' : null, routerConfig: router),
      );
}

/// Starts the app like a cold start. The platform opens it with [url].
Future<_Run> _pump(
  WidgetTester tester,
  List<Routable> routes,
  List<NavigationGuard> Function(ValueNotifier<bool> loggedIn) guards, {
  String url = '/',
  bool loggedIn = false,
  bool restore = false,
}) async {
  final run = _Run(loggedIn: loggedIn);
  tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') run.exits++;
      return null;
    })
    ..setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        final args = call.arguments as Map<Object?, Object?>;
        run.history.add((uri: args['uri']! as String, replace: args['replace']! as bool));
      }
      return null;
    });
  tester.platformDispatcher.defaultRouteNameTestValue = url; // HelmRouter reads it in its factory
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

  await tester.pumpWidget(_App(run: run, routes: routes, guards: guards, restore: restore));
  await tester.pumpAndSettle();
  return run;
}

/// A deep link while the app runs. The platform sends `pushRouteInformation`.
Future<void> _deepLink(WidgetTester tester, String url) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(MethodCall('pushRouteInformation', {'location': url})),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// System back.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Page names of each onstage Navigator, root first. Inactive tabs and covered pages are offstage.
List<List<String?>> _navigators(WidgetTester tester) => [
      for (final navigator in tester.widgetList<Navigator>(find.byType(Navigator)))
        [for (final page in navigator.pages) page.name],
    ];

/// Checks the three levels at once: state tree, URL and rendered navigators, and one visible text.
void _expectAt(
  WidgetTester tester,
  _Run run, {
  required NavigationState tree,
  required String url,
  required List<List<String?>> navigators,
  required String visible,
}) {
  expect(run.tree, tree, reason: 'state tree');
  expect(run.url, url, reason: 'url');
  expect(_navigators(tester), navigators, reason: 'navigators');
  expect(find.text(visible), findsOneWidget, reason: 'visible text');
}

HelmPage _p(
  Routable route, {
  Map<String, String> path = const {},
  Map<String, String> query = const {},
  NavigationState? children,
}) =>
    route.page(pathParams: path, queryParams: query, children: children);

// Small screen widgets with unique texts.

Widget _screen(String title, {List<Widget> children = const [], bool appBar = false}) => Scaffold(
      appBar: appBar ? AppBar(title: Text(title)) : null,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (!appBar) Text(title), ...children]),
    );

Widget _button(String label, VoidCallback onPressed) => TextButton(onPressed: onPressed, child: Text(label));

// ---------------------------------------------------------------------------------------------
// App 1: store
// ---------------------------------------------------------------------------------------------

enum Store with Routable {
  shell,
  feed,
  categories,
  category,
  noSelection,
  product,
  profile,
  cart,
  confirm,
  checkout,
  login,
  notFound;

  @override
  String get path => switch (this) {
        Store.shell => '/',
        Store.feed => '/feed',
        Store.categories => '/categories',
        Store.category => '/category/{cid}',
        Store.noSelection => '/no-selection',
        Store.product => '/product/{pid}',
        Store.profile => '/profile',
        Store.cart => '/cart',
        Store.confirm => '/confirm',
        Store.checkout => '/checkout',
        Store.login => '/login/{next}',
        Store.notFound => '/404',
      };

  @override
  PageType get pageType => switch (this) {
        Store.cart => PageType.bottomSheet,
        Store.confirm => PageType.dialog,
        _ => PageType.material,
      };

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        Store.shell => const _StoreShell(),
        Store.feed => Builder(
            builder: (context) => _screen('Feed screen', children: [
              _button('Browse laptops', () => HelmRouter.push(context, Store.category, pathParams: {'cid': 'laptops'})),
            ]),
          ),
        Store.categories => Builder(
            builder: (context) => _screen('Categories screen', children: [
              _button('Browse phones', () => HelmRouter.push(context, Store.category, pathParams: {'cid': 'phones'})),
            ]),
          ),
        Store.category => _CategoryScreen(cid: pathParams['cid']!),
        Store.noSelection => _screen('No product selected'),
        Store.product => Builder(
            builder: (context) => _screen('Product ${pathParams['pid']}', children: [
              _button('Buy now', () => HelmRouter.push(context, Store.checkout, rootNavigator: true)),
            ]),
          ),
        Store.profile => Builder(
            builder: (context) => _screen('Profile screen', children: [
              ValueListenableBuilder(
                valueListenable: _Session.of(context),
                builder: (_, loggedIn, __) => Text(loggedIn ? 'Signed in' : 'Signed out'),
              ),
              _button('Log out', () => _Session.of(context).value = false),
            ]),
          ),
        Store.cart => Builder(
            builder: (context) => Material(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Cart sheet'),
                _button('Clear cart', () => HelmRouter.push(context, Store.confirm, rootNavigator: true)),
              ]),
            ),
          ),
        Store.confirm => Builder(
            builder: (context) => AlertDialog(
              title: const Text('Confirm dialog'),
              actions: [_button('Yes, clear', () => HelmRouter.pop(context))],
            ),
          ),
        Store.checkout => _screen('Checkout screen', appBar: true),
        Store.login => Builder(
            builder: (context) => _screen('Login for ${pathParams['next']}', appBar: true, children: [
              _button('Log in', () => _Session.of(context).value = true),
            ]),
          ),
        Store.notFound => _screen('Page not found', appBar: true),
      };
}

class _StoreShell extends StatelessWidget {
  const _StoreShell();

  @override
  Widget build(BuildContext context) => NestedTabsNavigator(
        tabs: const [Store.feed, Store.categories, Store.profile],
        builder: (context, child, selectedIndex, onTabPressed) => Scaffold(
          appBar: AppBar(
            title: const Text('Store'),
            actions: [_button('Open cart', () => HelmRouter.push(context, Store.cart, rootNavigator: true))],
          ),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onTabPressed,
            destinations: const [
              NavigationDestination(label: 'Feed', icon: Icon(Icons.home)),
              NavigationDestination(label: 'Catalog', icon: Icon(Icons.category)),
              NavigationDestination(label: 'Profile', icon: Icon(Icons.person)),
            ],
          ),
        ),
      );
}

/// Master-detail: the product list on the left, the nested product stack on the right.
class _CategoryScreen extends StatelessWidget {
  const _CategoryScreen({required this.cid});

  final String cid;

  @override
  Widget build(BuildContext context) => NestedNavigator(
        initialRoute: Store.noSelection,
        builder: (context, child) => Row(children: [
          SizedBox(
            width: 220,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Category $cid'),
              _Like(cid: cid),
              for (final pid in const ['p1', 'p2'])
                _button('Open $pid', () => HelmRouter.push(context, Store.product, pathParams: {'pid': pid})),
            ]),
          ),
          Expanded(child: child),
        ]),
      );
}

/// Has its own widget state, to check that a stack keeps it.
class _Like extends StatefulWidget {
  const _Like({required this.cid});

  final String cid;

  @override
  State<_Like> createState() => _LikeState();
}

class _LikeState extends State<_Like> {
  var liked = false;

  @override
  Widget build(BuildContext context) =>
      _button(liked ? 'Liked ${widget.cid}' : 'Like ${widget.cid}', () => setState(() => liked = !liked));
}

/// The shell is always the first page. Checkout needs a login, and a login for checkout leads to it.
List<NavigationGuard> _storeGuards(ValueNotifier<bool> loggedIn) => [
      (pages) => pages.isEmpty ? [Store.notFound.page()] : pages,
      (pages) =>
          const [Store.shell, Store.notFound].contains(pages.first.route) ? pages : [Store.shell.page(), ...pages],
      (pages) => pages.mapPages((page) {
            if (loggedIn.value) {
              final resume = page.route == Store.login && page.pathParams['next'] == 'checkout';
              return resume ? Store.checkout.page(queryParams: page.queryParams) : page;
            }
            final blocked = page.route == Store.checkout;
            return blocked ? Store.login.page(pathParams: {'next': 'checkout'}, queryParams: page.queryParams) : page;
          }),
    ];

Future<_Run> _pumpStore(WidgetTester tester, {String url = '/', bool loggedIn = false, bool restore = false}) =>
    _pump(tester, Store.values, _storeGuards, url: url, loggedIn: loggedIn, restore: restore);

// Expected trees of the store.
HelmPage _shell(NavigationState tab, {Map<String, String> query = const {}}) =>
    _p(Store.shell, query: query, children: tab);
HelmPage _category(String cid, NavigationState detail, {Map<String, String> query = const {}}) =>
    _p(Store.category, path: {'cid': cid}, query: query, children: detail);
HelmPage _product(String pid, {Map<String, String> query = const {}}) =>
    _p(Store.product, path: {'pid': pid}, query: query);
HelmPage _loginForCheckout() => _p(Store.login, path: {'next': 'checkout'});

// Rendered navigators of the store, root first.
const _phonesP1 = [
  ['/', '/cart'],
  ['/categories', '/category/phones'],
  ['/product/p1'],
];

// ---------------------------------------------------------------------------------------------
// App 2: mail (no `/` route)
// ---------------------------------------------------------------------------------------------

enum Mail with Routable {
  inbox,
  none,
  thread,
  compose,
  search,
  settings,
  section;

  @override
  String get path => switch (this) {
        Mail.inbox => '/inbox',
        Mail.none => '/none',
        Mail.thread => '/thread/{ids+}',
        Mail.compose => '/compose',
        Mail.search => '/search/q={query}',
        Mail.settings => '/settings',
        Mail.section => '/section/{name}',
      };

  @override
  PageType get pageType => this == Mail.compose ? PageType.dialog : PageType.material;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        Mail.inbox => const _InboxScreen(),
        Mail.none => _screen('No message selected'),
        Mail.thread => Builder(
            builder: (context) {
              final id = pathParams['ids']!;
              return _screen('Message $id', children: [
                _button('Reply $id', () => HelmRouter.push(context, Mail.thread, pathParams: {'ids': '${id}r'})),
              ]);
            },
          ),
        Mail.compose => Builder(
            builder: (context) => AlertDialog(
              title: const Text('Compose dialog'),
              actions: [_button('Discard', () => HelmRouter.pop(context))],
            ),
          ),
        Mail.search => _screen('Results for ${pathParams['query']}', appBar: true),
        Mail.settings => const _SettingsScreen(),
        Mail.section => _screen('Section ${pathParams['name']}'),
      };
}

class _InboxScreen extends StatelessWidget {
  const _InboxScreen();

  @override
  Widget build(BuildContext context) => NestedNavigator(
        initialRoute: Mail.none,
        builder: (context, child) => Scaffold(
          appBar: AppBar(title: const Text('Inbox'), actions: [
            _button('Compose', () => HelmRouter.push(context, Mail.compose, rootNavigator: true)),
            _button('Settings', () => HelmRouter.push(context, Mail.settings, rootNavigator: true)),
            _button(
              'Search invoices',
              () => HelmRouter.push(context, Mail.search, pathParams: {'query': 'invoices'}, rootNavigator: true),
            ),
          ]),
          body: Row(children: [
            SizedBox(
              width: 160,
              child: Column(children: [
                for (final id in const ['m1', 'm2'])
                  // Opening a message replaces the detail pane.
                  _button(
                    'Open $id',
                    () => HelmRouter.change(
                      context,
                      (pages) => pages.updateDeepest((_) => [
                            Mail.thread.page(pathParams: {'ids': id})
                          ]),
                    ),
                  ),
              ]),
            ),
            Expanded(child: child),
          ]),
        ),
      );
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) => NestedNavigator(
        initialState: [
          Mail.section.page(pathParams: {'name': 'general'})
        ],
        builder: (context, child) => Scaffold(
          appBar: AppBar(title: const Text('Settings screen')),
          body: Column(children: [
            _button('Privacy', () => HelmRouter.push(context, Mail.section, pathParams: {'name': 'privacy'})),
            Expanded(child: child),
          ]),
        ),
      );
}

/// Without a `/` route, an empty URL leads to the inbox. The inbox is always the first page.
List<NavigationGuard> _mailGuards(ValueNotifier<bool> loggedIn) => [
      (pages) => pages.isEmpty ? [Mail.inbox.page()] : pages,
      (pages) => pages.first.route == Mail.inbox ? pages : [Mail.inbox.page(), ...pages],
    ];

Future<_Run> _pumpMail(WidgetTester tester, {String url = '/inbox', bool restore = false}) =>
    _pump(tester, Mail.values, _mailGuards, url: url, restore: restore);

HelmPage _inbox(NavigationState detail, {Map<String, String> query = const {}}) =>
    _p(Mail.inbox, query: query, children: detail);
HelmPage _thread(String id) => _p(Mail.thread, path: {'ids': id});
HelmPage _section(String name) => _p(Mail.section, path: {'name': name});
HelmPage _settings(String section) => _p(Mail.settings, children: [_section(section)]);
final _noMessage = _p(Mail.none);

// ---------------------------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------------------------

typedef _Case = ({
  String url,
  bool loggedIn,
  NavigationState tree,
  String restored,
  List<List<String?>> navigators,
  String visible,
});

_Case _case(
  String url, {
  bool loggedIn = false,
  required NavigationState tree,
  String? restored,
  required List<List<String?>> navigators,
  required String visible,
}) =>
    (url: url, loggedIn: loggedIn, tree: tree, restored: restored ?? url, navigators: navigators, visible: visible);

void main() {
  group('store: cold start deep links', () {
    final cases = <_Case>[
      _case(
        '/',
        tree: [
          _shell([_p(Store.feed)]),
        ],
        restored: '/!feed',
        navigators: [
          ['/'],
          ['/feed'],
        ],
        visible: 'Feed screen',
      ),
      _case(
        '/!profile',
        tree: [
          _shell([_p(Store.profile)]),
        ],
        navigators: [
          ['/'],
          ['/profile'],
        ],
        visible: 'Signed out',
      ),
      _case(
        '/!categories/category/phones',
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_p(Store.noSelection)]),
          ]),
        ],
        restored: '/!categories/category/phones/!no-selection',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection'],
        ],
        visible: 'No product selected',
      ),
      _case(
        '/!categories/category/phones/!product/p1',
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_product('p1')]),
          ]),
        ],
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/product/p1'],
        ],
        visible: 'Product p1',
      ),
      _case(
        // The nested stack has two products. Unknown parts at the end are dropped.
        '/!categories/category/laptops/!no-selection/product/p1/product/p2/nope',
        tree: [
          _shell([
            _p(Store.categories),
            _category('laptops', [_p(Store.noSelection), _product('p1'), _product('p2')]),
          ]),
        ],
        restored: '/!categories/category/laptops/!no-selection/product/p1/product/p2',
        navigators: [
          ['/'],
          ['/categories', '/category/laptops'],
          ['/no-selection', '/product/p1', '/product/p2'],
        ],
        visible: 'Product p2',
      ),
      _case(
        // A bottom sheet on the root stack above a nested product.
        '/!categories/category/phones/!product/p1!/!/cart',
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_product('p1')]),
          ]),
          _p(Store.cart),
        ],
        navigators: _phonesP1,
        visible: 'Cart sheet',
      ),
      _case(
        // A dialog above a sheet above the shell.
        '/!feed!/cart/confirm',
        tree: [
          _shell([_p(Store.feed)]),
          _p(Store.cart),
          _p(Store.confirm),
        ],
        navigators: [
          ['/', '/cart', '/confirm'],
          ['/feed'],
        ],
        visible: 'Confirm dialog',
      ),
      _case(
        // Query params go to every page, also in nested stacks.
        '/!categories/category/phones/!product/p1?ref=mail',
        tree: [
          _shell([
            _p(Store.categories, query: {'ref': 'mail'}),
            _category('phones', [
              _product('p1', query: {'ref': 'mail'})
            ], query: {
              'ref': 'mail'
            }),
          ], query: {
            'ref': 'mail'
          }),
        ],
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/product/p1'],
        ],
        visible: 'Product p1',
      ),
      _case(
        // A plain link without a dive: the guard adds the shell below. The category is on the root stack.
        '/category/phones',
        tree: [
          _shell([_p(Store.feed)]),
          _category('phones', [_p(Store.noSelection)]),
        ],
        restored: '/!feed!/category/phones/!no-selection',
        navigators: [
          ['/', '/category/phones'],
          ['/no-selection'],
        ],
        visible: 'No product selected',
      ),
      _case(
        '/nope',
        tree: [_p(Store.notFound)],
        restored: '/404',
        navigators: [
          ['/404'],
        ],
        visible: 'Page not found',
      ),
      _case(
        // An unknown part in front of a known route: nothing matches, the guard shows the 404 page.
        '/nope/category/phones',
        tree: [_p(Store.notFound)],
        restored: '/404',
        navigators: [
          ['/404'],
        ],
        visible: 'Page not found',
      ),
      _case(
        // Logged out: the guard turns checkout into the login page.
        '/checkout',
        tree: [
          _shell([_p(Store.feed)]),
          _loginForCheckout(),
        ],
        restored: '/!feed!/login/checkout',
        navigators: [
          ['/', '/login/checkout'],
        ],
        visible: 'Login for checkout',
      ),
      _case(
        '/checkout',
        loggedIn: true,
        tree: [
          _shell([_p(Store.feed)]),
          _p(Store.checkout),
        ],
        restored: '/!feed!/checkout',
        navigators: [
          ['/', '/checkout'],
        ],
        visible: 'Checkout screen',
      ),
    ];

    for (final c in cases) {
      testWidgets('${c.url}${c.loggedIn ? ' (logged in)' : ''}', (tester) async {
        final run = await _pumpStore(tester, url: c.url, loggedIn: c.loggedIn);
        _expectAt(tester, run, tree: c.tree, url: c.restored, navigators: c.navigators, visible: c.visible);
      });
    }
  });

  group('store journeys', () {
    testWidgets('deep link to a nested product, then system back to the exit', (tester) async {
      const url = '/!categories/category/phones/!no-selection/product/p1/product/p2';
      final run = await _pumpStore(tester, url: url);
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_p(Store.noSelection), _product('p1'), _product('p2')]),
          ]),
        ],
        url: url,
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1', '/product/p2'],
        ],
        visible: 'Product p2',
      );

      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_p(Store.noSelection), _product('p1')]),
          ]),
        ],
        url: '/!categories/category/phones/!no-selection/product/p1',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1'],
        ],
        visible: 'Product p1',
      );

      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_p(Store.noSelection)]),
          ]),
        ],
        url: '/!categories/category/phones/!no-selection',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection'],
        ],
        visible: 'No product selected',
      );

      // The detail stack has one page left, so back pops the category from the tab stack.
      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.categories)]),
        ],
        url: '/!categories',
        navigators: [
          ['/'],
          ['/categories'],
        ],
        visible: 'Categories screen',
      );
      expect(run.exits, 0);

      // Nothing is left to pop: the delegate says so, and the system back exits the app.
      expect(await run.router.delegate.popRoute(), isFalse);
      await _back(tester);
      expect(run.exits, 1);
      expect(run.url, '/!categories');
    });

    testWidgets('browse: tabs keep the catalog stack and the master list state', (tester) async {
      final run = await _pumpStore(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.feed)]),
        ],
        url: '/!feed',
        navigators: [
          ['/'],
          ['/feed'],
        ],
        visible: 'Feed screen',
      );

      await _tap(tester, 'Catalog');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.categories)]),
        ],
        url: '/!categories',
        navigators: [
          ['/'],
          ['/categories'],
        ],
        visible: 'Categories screen',
      );

      await _tap(tester, 'Browse phones');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_p(Store.noSelection)]),
          ]),
        ],
        url: '/!categories/category/phones/!no-selection',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection'],
        ],
        visible: 'No product selected',
      );

      await _tap(tester, 'Like phones');
      await _tap(tester, 'Open p1');
      final catalog = [
        _p(Store.categories),
        _category('phones', [_p(Store.noSelection), _product('p1')]),
      ];
      _expectAt(
        tester,
        run,
        tree: [_shell(catalog)],
        url: '/!categories/category/phones/!no-selection/product/p1',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1'],
        ],
        visible: 'Product p1',
      );
      expect(find.text('Liked phones'), findsOneWidget);

      await _tap(tester, 'Profile');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.profile)]),
        ],
        url: '/!profile',
        navigators: [
          ['/'],
          ['/profile'],
        ],
        visible: 'Profile screen',
      );
      expect(find.text('Liked phones'), findsNothing, reason: 'the catalog tab is offstage');

      // Back on the catalog tab: the stack and the like button are as they were.
      await _tap(tester, 'Catalog');
      _expectAt(
        tester,
        run,
        tree: [_shell(catalog)],
        url: '/!categories/category/phones/!no-selection/product/p1',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1'],
        ],
        visible: 'Product p1',
      );
      expect(find.text('Liked phones'), findsOneWidget);

      // Selecting the active tab again resets it, and the new category page starts fresh.
      await _tap(tester, 'Catalog');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.categories)]),
        ],
        url: '/!categories',
        navigators: [
          ['/'],
          ['/categories'],
        ],
        visible: 'Categories screen',
      );
      await _tap(tester, 'Browse phones');
      expect(find.text('Like phones'), findsOneWidget);
    });

    testWidgets('sheet over a nested product: back closes the sheet only, a dialog sits on the sheet', (tester) async {
      const url = '/!categories/category/phones/!product/p1';
      final run = await _pumpStore(tester, url: url);
      final shell = _shell([
        _p(Store.categories),
        _category('phones', [_product('p1')]),
      ]);

      await _tap(tester, 'Open cart');
      _expectAt(
        tester,
        run,
        tree: [shell, _p(Store.cart)],
        url: '/!categories/category/phones/!product/p1!/!/cart',
        navigators: _phonesP1,
        visible: 'Cart sheet',
      );

      await _tap(tester, 'Clear cart');
      _expectAt(
        tester,
        run,
        tree: [shell, _p(Store.cart), _p(Store.confirm)],
        url: '/!categories/category/phones/!product/p1!/!/cart/confirm',
        navigators: [
          ['/', '/cart', '/confirm'],
          ['/categories', '/category/phones'],
          ['/product/p1'],
        ],
        visible: 'Confirm dialog',
      );

      // The dialog button pops the dialog only.
      await _tap(tester, 'Yes, clear');
      _expectAt(
        tester,
        run,
        tree: [shell, _p(Store.cart)],
        url: '/!categories/category/phones/!product/p1!/!/cart',
        navigators: _phonesP1,
        visible: 'Cart sheet',
      );

      // System back closes the sheet. The nested product stays.
      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [shell],
        url: url,
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/product/p1'],
        ],
        visible: 'Product p1',
      );
      expect(run.exits, 0);
    });

    testWidgets('checkout: login first, then checkout; log out on checkout leads back to login', (tester) async {
      const catalogUrl = '/!categories/category/phones/!no-selection/product/p1';
      final run = await _pumpStore(tester, url: catalogUrl);
      final shell = _shell([
        _p(Store.categories),
        _category('phones', [_p(Store.noSelection), _product('p1')]),
      ]);

      await _tap(tester, 'Buy now');
      _expectAt(
        tester,
        run,
        tree: [shell, _loginForCheckout()],
        url: '$catalogUrl!/!/login/checkout',
        navigators: [
          ['/', '/login/checkout'],
        ],
        visible: 'Login for checkout',
      );

      // The login page has a back button. It leads to the catalog with its stack.
      await tester.pageBack();
      await tester.pumpAndSettle();
      _expectAt(
        tester,
        run,
        tree: [shell],
        url: catalogUrl,
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1'],
        ],
        visible: 'Product p1',
      );

      await _tap(tester, 'Buy now');
      await _tap(tester, 'Log in');
      _expectAt(
        tester,
        run,
        tree: [shell, _p(Store.checkout)],
        url: '$catalogUrl!/!/checkout',
        navigators: [
          ['/', '/checkout'],
        ],
        visible: 'Checkout screen',
      );

      // The session ends while the user is on checkout. The guard acts at once, before any frame.
      run.session.value = false;
      expect(run.tree, [shell, _loginForCheckout()]);
      await tester.pumpAndSettle();
      _expectAt(
        tester,
        run,
        tree: [shell, _loginForCheckout()],
        url: '$catalogUrl!/!/login/checkout',
        navigators: [
          ['/', '/login/checkout'],
        ],
        visible: 'Login for checkout',
      );

      // Log in again, then system back: login was replaced, so back goes to the catalog.
      await _tap(tester, 'Log in');
      expect(find.text('Checkout screen'), findsOneWidget);
      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [shell],
        url: catalogUrl,
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1'],
        ],
        visible: 'Product p1',
      );
    });

    testWidgets('a login link opens checkout when the user is already signed in', (tester) async {
      final run = await _pumpStore(tester, loggedIn: true);
      await _deepLink(tester, '/login/checkout');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.feed)]),
          _p(Store.checkout),
        ],
        url: '/!feed!/checkout',
        navigators: [
          ['/', '/checkout'],
        ],
        visible: 'Checkout screen',
      );
    });

    testWidgets('deep links while the app runs replace the tab and nested stacks, then back', (tester) async {
      final run = await _pumpStore(tester, url: '/!feed');

      await _deepLink(tester, '/!categories/category/laptops/!no-selection/product/p2');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('laptops', [_p(Store.noSelection), _product('p2')]),
          ]),
        ],
        url: '/!categories/category/laptops/!no-selection/product/p2',
        navigators: [
          ['/'],
          ['/categories', '/category/laptops'],
          ['/no-selection', '/product/p2'],
        ],
        visible: 'Product p2',
      );

      // A link to another tab. The tab bar follows.
      await _deepLink(tester, '/!profile');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.profile)]),
        ],
        url: '/!profile',
        navigators: [
          ['/'],
          ['/profile'],
        ],
        visible: 'Profile screen',
      );

      // A link to a sheet over a nested product. The product list of that tab is built from the URL.
      await _deepLink(tester, '/!categories/category/phones/!product/p1!/!/cart');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_product('p1')]),
          ]),
          _p(Store.cart),
        ],
        url: '/!categories/category/phones/!product/p1!/!/cart',
        navigators: _phonesP1,
        visible: 'Cart sheet',
      );

      await _back(tester);
      expect(find.text('Cart sheet'), findsNothing);
      expect(find.text('Product p1'), findsOneWidget);

      // Back pops the nested stacks step by step until the exit.
      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _shell([_p(Store.categories)]),
        ],
        url: '/!categories',
        navigators: [
          ['/'],
          ['/categories'],
        ],
        visible: 'Categories screen',
      );
      await _back(tester);
      expect(run.exits, 1);
    });

    testWidgets('a link to another tab keeps the cached catalog stack for the tab bar', (tester) async {
      final run = await _pumpStore(tester, url: '/!categories/category/phones/!product/p1');
      await _deepLink(tester, '/!profile');
      expect(run.url, '/!profile');

      await _tap(tester, 'Catalog');
      _expectAt(
        tester,
        run,
        tree: [
          _shell([
            _p(Store.categories),
            _category('phones', [_product('p1')]),
          ]),
        ],
        url: '/!categories/category/phones/!product/p1',
        navigators: [
          ['/'],
          ['/categories', '/category/phones'],
          ['/product/p1'],
        ],
        visible: 'Product p1',
      );
    });

    testWidgets('history: one pushed entry for each user navigation, nested fills replace', (tester) async {
      final run = await _pumpStore(tester);
      // The cold start only normalizes the URL.
      expect(run.pushed, isEmpty);
      expect(run.history.last.uri, '/!feed');

      await _tap(tester, 'Catalog');
      await _tap(tester, 'Browse phones'); // the nested stack fills with a replace afterwards
      await _tap(tester, 'Open p1');
      await _tap(tester, 'Profile');
      await _tap(tester, 'Catalog');
      await _tap(tester, 'Open cart');
      expect(run.pushed, [
        '/!categories',
        '/!categories/category/phones',
        '/!categories/category/phones/!no-selection/product/p1',
        '/!profile',
        '/!categories/category/phones/!no-selection/product/p1',
        '/!categories/category/phones/!no-selection/product/p1!/!/cart',
      ]);
      expect(run.history.where((r) => r.replace).map((r) => r.uri),
          contains('/!categories/category/phones/!no-selection'));
    });

    testWidgets('restart and restore: the full tree with a sheet over a nested product comes back', (tester) async {
      final run = await _pumpStore(tester, restore: true);
      await _tap(tester, 'Catalog');
      await _tap(tester, 'Browse phones');
      await _tap(tester, 'Open p1');
      await _tap(tester, 'Open cart');
      final before = run.router;
      final tree = run.tree;
      final url = run.url;
      expect(url, '/!categories/category/phones/!no-selection/product/p1!/!/cart');

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(identical(run.router, before), isFalse, reason: 'a restart creates a new router');
      _expectAt(
        tester,
        run,
        tree: tree,
        url: url,
        navigators: [
          ['/', '/cart'],
          ['/categories', '/category/phones'],
          ['/no-selection', '/product/p1'],
        ],
        visible: 'Cart sheet',
      );

      // The restored app works: close the sheet, then pop the product.
      await _back(tester);
      expect(find.text('Product p1'), findsOneWidget);
      await _back(tester);
      expect(run.url, '/!categories/category/phones/!no-selection');
    });

    testWidgets('restart and restore: the tree of a deep link with query params comes back', (tester) async {
      final run = await _pumpStore(tester, url: '/!categories/category/phones?ref=mail', restore: true);
      final tree = run.tree;
      final url = run.url;
      expect(url, '/!categories/category/phones/!no-selection?ref=mail');

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(run.url, url);
      expect(run.tree, tree);
    });
  });

  group('mail: cold start deep links', () {
    final cases = <_Case>[
      _case(
        // No `/` route: the guard shows the inbox.
        '/',
        tree: [
          _inbox([_noMessage]),
        ],
        restored: '/inbox/!none',
        navigators: [
          ['/inbox'],
          ['/none'],
        ],
        visible: 'No message selected',
      ),
      _case(
        '/inbox/!thread/m1',
        tree: [
          _inbox([_thread('m1')]),
        ],
        navigators: [
          ['/inbox'],
          ['/thread/m1'],
        ],
        visible: 'Message m1',
      ),
      _case(
        // One `{ids+}` route, three pages in the nested stack.
        '/inbox/!thread/m1/m1r/m1rr',
        tree: [
          _inbox([_thread('m1'), _thread('m1r'), _thread('m1rr')]),
        ],
        navigators: [
          ['/inbox'],
          ['/thread/m1', '/thread/m1r', '/thread/m1rr'],
        ],
        visible: 'Message m1rr',
      ),
      _case(
        // A dialog on the root stack after a nested thread.
        '/inbox/!thread/m1/m1r!/compose',
        tree: [
          _inbox([_thread('m1'), _thread('m1r')]),
          _p(Mail.compose),
        ],
        navigators: [
          ['/inbox', '/compose'],
          ['/thread/m1', '/thread/m1r'],
        ],
        visible: 'Compose dialog',
      ),
      _case(
        // `~` ends the thread sequence, so `compose` is a new page on the same stack.
        '/thread/a/b/~/compose',
        tree: [
          _inbox([_noMessage]),
          _thread('a'),
          _thread('b'),
          _p(Mail.compose),
        ],
        restored: '/inbox/!none!/thread/a/b/~/compose',
        navigators: [
          ['/inbox', '/thread/a', '/thread/b', '/compose'],
        ],
        visible: 'Compose dialog',
      ),
      _case(
        '/settings',
        tree: [
          _inbox([_noMessage]),
          _settings('general'),
        ],
        restored: '/inbox/!none!/settings/!section/general',
        navigators: [
          ['/inbox', '/settings'],
          ['/section/general'],
        ],
        visible: 'Section general',
      ),
      _case(
        '/inbox/!thread/m2!/settings/!section/privacy',
        tree: [
          _inbox([_thread('m2')]),
          _settings('privacy'),
        ],
        navigators: [
          ['/inbox', '/settings'],
          ['/section/privacy'],
        ],
        visible: 'Section privacy',
      ),
      _case(
        // A pattern segment with an encoded space.
        '/search/q=big%20deal',
        tree: [
          _inbox([_noMessage]),
          _p(Mail.search, path: {'query': 'big deal'}),
        ],
        restored: '/inbox/!none!/search/q=big%20deal',
        navigators: [
          ['/inbox', '/search/q=big deal'],
        ],
        visible: 'Results for big deal',
      ),
      _case(
        '/nope',
        tree: [
          _inbox([_noMessage]),
        ],
        restored: '/inbox/!none',
        navigators: [
          ['/inbox'],
          ['/none'],
        ],
        visible: 'No message selected',
      ),
    ];

    for (final c in cases) {
      testWidgets(c.url, (tester) async {
        final run = await _pumpMail(tester, url: c.url);
        _expectAt(tester, run, tree: c.tree, url: c.restored, navigators: c.navigators, visible: c.visible);
      });
    }
  });

  group('mail journeys', () {
    testWidgets('read, reply, compose, change settings, then back to the exit', (tester) async {
      final run = await _pumpMail(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_noMessage]),
        ],
        url: '/inbox/!none',
        navigators: [
          ['/inbox'],
          ['/none'],
        ],
        visible: 'No message selected',
      );

      await _tap(tester, 'Open m1');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m1')]),
        ],
        url: '/inbox/!thread/m1',
        navigators: [
          ['/inbox'],
          ['/thread/m1'],
        ],
        visible: 'Message m1',
      );

      await _tap(tester, 'Reply m1');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m1'), _thread('m1r')]),
        ],
        url: '/inbox/!thread/m1/m1r',
        navigators: [
          ['/inbox'],
          ['/thread/m1', '/thread/m1r'],
        ],
        visible: 'Message m1r',
      );

      // Opening another message replaces the whole thread.
      await _tap(tester, 'Open m2');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m2')]),
        ],
        url: '/inbox/!thread/m2',
        navigators: [
          ['/inbox'],
          ['/thread/m2'],
        ],
        visible: 'Message m2',
      );

      await _tap(tester, 'Reply m2');
      await _tap(tester, 'Compose');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m2'), _thread('m2r')]),
          _p(Mail.compose),
        ],
        url: '/inbox/!thread/m2/m2r!/compose',
        navigators: [
          ['/inbox', '/compose'],
          ['/thread/m2', '/thread/m2r'],
        ],
        visible: 'Compose dialog',
      );

      await _tap(tester, 'Discard');
      expect(run.url, '/inbox/!thread/m2/m2r');
      expect(find.text('Compose dialog'), findsNothing);

      await _tap(tester, 'Settings');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m2'), _thread('m2r')]),
          _settings('general'),
        ],
        url: '/inbox/!thread/m2/m2r!/settings/!section/general',
        navigators: [
          ['/inbox', '/settings'],
          ['/section/general'],
        ],
        visible: 'Section general',
      );

      await _tap(tester, 'Privacy');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m2'), _thread('m2r')]),
          _p(Mail.settings, children: [_section('general'), _section('privacy')]),
        ],
        url: '/inbox/!thread/m2/m2r!/settings/!section/general/section/privacy',
        navigators: [
          ['/inbox', '/settings'],
          ['/section/general', '/section/privacy'],
        ],
        visible: 'Section privacy',
      );

      // Back: privacy section, then the settings page, then the reply, then the thread, then exit.
      await _back(tester);
      expect(run.url, '/inbox/!thread/m2/m2r!/settings/!section/general');
      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m2'), _thread('m2r')]),
        ],
        url: '/inbox/!thread/m2/m2r',
        navigators: [
          ['/inbox'],
          ['/thread/m2', '/thread/m2r'],
        ],
        visible: 'Message m2r',
      );
      await _back(tester);
      expect(run.url, '/inbox/!thread/m2');
      // The last thread page passes the back to the root stack, which has the inbox only.
      await _back(tester);
      expect(run.exits, 1);
      expect(run.url, '/inbox/!thread/m2');
    });

    testWidgets('search link from the inbox uses a pattern segment', (tester) async {
      final run = await _pumpMail(tester, url: '/inbox/!thread/m1');
      await _tap(tester, 'Search invoices');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_thread('m1')]),
          _p(Mail.search, path: {'query': 'invoices'}),
        ],
        url: '/inbox/!thread/m1!/search/q=invoices',
        navigators: [
          ['/inbox', '/search/q=invoices'],
        ],
        visible: 'Results for invoices',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(run.url, '/inbox/!thread/m1');
      expect(find.text('Message m1'), findsOneWidget);
    });

    testWidgets('a deep link while reading opens settings in a section, back returns to the inbox', (tester) async {
      final run = await _pumpMail(tester, url: '/inbox/!thread/m1');

      await _deepLink(tester, '/settings/!section/privacy');
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_noMessage]),
          _settings('privacy'),
        ],
        url: '/inbox/!none!/settings/!section/privacy',
        navigators: [
          ['/inbox', '/settings'],
          ['/section/privacy'],
        ],
        visible: 'Section privacy',
      );

      await _back(tester);
      _expectAt(
        tester,
        run,
        tree: [
          _inbox([_noMessage]),
        ],
        url: '/inbox/!none',
        navigators: [
          ['/inbox'],
          ['/none'],
        ],
        visible: 'No message selected',
      );
    });

    testWidgets('history: one pushed entry for each user navigation', (tester) async {
      final run = await _pumpMail(tester);
      expect(run.pushed, isEmpty);

      await _tap(tester, 'Open m1');
      await _tap(tester, 'Reply m1');
      await _tap(tester, 'Compose');
      await _tap(tester, 'Discard');
      expect(run.pushed, [
        '/inbox/!thread/m1',
        '/inbox/!thread/m1/m1r',
        '/inbox/!thread/m1/m1r!/compose',
        '/inbox/!thread/m1/m1r',
      ]);
    });

    testWidgets('restart and restore: a thread under settings with a section comes back', (tester) async {
      final run = await _pumpMail(tester, restore: true);
      await _tap(tester, 'Open m1');
      await _tap(tester, 'Reply m1');
      await _tap(tester, 'Settings');
      await _tap(tester, 'Privacy');
      final tree = run.tree;
      final url = run.url;
      expect(url, '/inbox/!thread/m1/m1r!/settings/!section/general/section/privacy');

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      _expectAt(
        tester,
        run,
        tree: tree,
        url: url,
        navigators: [
          ['/inbox', '/settings'],
          ['/section/general', '/section/privacy'],
        ],
        visible: 'Section privacy',
      );
    });
  });
}
