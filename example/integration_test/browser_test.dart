import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:helm/helm.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

/// The `<base href>` path of the page, always with a leading and a trailing slash.
String get _base => Uri.parse(web.document.baseURI).path;

/// The address bar URL without the `<base href>` prefix, the way the app sees it.
String get _browserUrl {
  final path = web.window.location.pathname;
  final stripped = path.startsWith(_base) ? path.substring(_base.length - 1) : path;
  return '$stripped${web.window.location.search}';
}

int get _historyLength => web.window.history.length;

/// Opens the example [App] at the root URL and returns the history length before the app started.
///
/// The engine reports the real page URL as the initial route only for the first app of a page load.
/// Later apps start at `/`, so tests that need a given start URL use the launch URL of the page.
Future<int> _startAtRoot(WidgetTester tester) async {
  web.window.history.replaceState(null, '', _base);
  final lengthBefore = _historyLength;
  await tester.pumpWidget(const App());
  await tester.pumpAndSettle();
  return lengthBefore;
}

String _stateUrl(WidgetTester tester) =>
    HelmRouter.delegateOf(tester.element(find.byType(Scaffold).first)).currentUri.toString();

/// Browser history events are async. Pumps and polls until [condition] holds.
Future<void> _waitFor(WidgetTester tester, bool Function() condition, String reason) async {
  for (var i = 0; i < 50; i++) {
    await tester.pumpAndSettle();
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for: $reason. Browser URL: $_browserUrl, state URL: ${_stateUrl(tester)}');
}

/// Waits until the address bar and the router state agree on [url].
Future<void> _waitForUrl(WidgetTester tester, String url) =>
    _waitFor(tester, () => _browserUrl == url && _stateUrl(tester) == url, 'URL $url');

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// The final URL for each launch URL (relative to `<base href>`), and the text the screen must show.
/// Run the test once per launch URL, with `flutter drive --web-launch-url`.
const _startCases = <String, (String url, String text)>{
  '/': ('/!home', 'Push Shop'),
  '/shop': ('/!home!/shop/!category', 'Categories'),
  '/does-not-exist': ('/!home!/404', '404 Not Found'),
  '/!home/products/123': ('/!home/products/123', 'Product: 123'),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final launchUrl = _browserUrl;
  final launchLength = _historyLength;

  // This test must run first. The engine reports the page URL only to the first app.
  testWidgets('the launch URL $launchUrl is normalized with replace, not push', (tester) async {
    // The test binding fakes the initial route as `/`. Use the real value from the browser.
    tester.platformDispatcher.clearDefaultRouteNameTestValue();
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(_browserUrl, _stateUrl(tester));
    expect(web.window.location.pathname, '$_base${_browserUrl.substring(1).split('?').first}');
    expect(_historyLength, launchLength);
    final expected = _startCases[launchUrl];
    if (expected == null) fail('No expectation for launch URL $launchUrl. Known: ${_startCases.keys.join(', ')}');
    expect(_stateUrl(tester), expected.$1);
    expect(find.text(expected.$2), findsWidgets);
  });

  testWidgets('a push adds one history entry', (tester) async {
    await _startAtRoot(tester);
    final before = _historyLength;

    await _tap(tester, 'Push Product 123');
    await _waitForUrl(tester, '/!home/products/123');

    expect(find.text('Product: 123'), findsOneWidget);
    expect(_historyLength, before + 1);
  });

  testWidgets('a page with an empty nested stack adds one entry in total', (tester) async {
    await _startAtRoot(tester);
    final before = _historyLength;

    await _tap(tester, 'Push Shop');
    await _waitForUrl(tester, '/!home/shop/!category');

    expect(find.text('Categories'), findsWidgets);
    expect(_historyLength, before + 1);

    // The category page hosts a NestedNavigator that fills itself with its initial route.
    await _tap(tester, 'Push Laptops');
    await _waitForUrl(tester, '/!home/shop/!category/laptops/!settings');
    expect(find.text('Category: laptops'), findsOneWidget);
    expect(_historyLength, before + 2);
  });

  testWidgets('browser back and forward move the app state', (tester) async {
    await _startAtRoot(tester);
    final first = _historyLength;

    await _tap(tester, 'Push Shop');
    await _waitForUrl(tester, '/!home/shop/!category');
    await _tap(tester, 'Push Laptops');
    await _waitForUrl(tester, '/!home/shop/!category/laptops/!settings');
    expect(_historyLength, first + 2);

    web.window.history.back();
    await _waitForUrl(tester, '/!home/shop/!category');
    expect(find.text('Category: laptops'), findsNothing);
    expect(find.text('Push Laptops'), findsOneWidget);

    web.window.history.back();
    await _waitForUrl(tester, '/!home');
    expect(find.text('Push Shop'), findsOneWidget);

    web.window.history.forward();
    await _waitForUrl(tester, '/!home/shop/!category');
    expect(find.text('Push Laptops'), findsOneWidget);

    web.window.history.forward();
    await _waitForUrl(tester, '/!home/shop/!category/laptops/!settings');
    expect(find.text('Category: laptops'), findsOneWidget);
    expect(_historyLength, first + 2);
  });
}
