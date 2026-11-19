import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';
import 'package:material_ui/material_ui.dart';

enum _R with Routable {
  home('/'),
  fade('/fade'),
  sheet('/sheet', PageType.bottomSheet);

  const _R(this.path, [this.pageType = PageType.material]);

  @override
  final String path;
  @override
  final PageType pageType;

  @override
  Page<Object?>? buildPage(LocalKey key, HelmPage page, Widget child) =>
      this == fade ? _FadePage(key: key, name: page.name, arguments: page, child: child) : null;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        home => const Scaffold(body: Text('Home')),
        fade => Scaffold(body: Text('Fade ${queryParams['n'] ?? ''}')),
        sheet => const SizedBox(height: 200, child: Text('Sheet')),
      };
}

class _FadePage extends Page<Object?> {
  const _FadePage({required this.child, super.key, super.name, super.arguments});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) => _FadeRoute(this);
}

class _FadeRoute extends PageRouteBuilder<Object?> {
  _FadeRoute(_FadePage page)
      : super(
          settings: page,
          pageBuilder: (context, animation, _) => FadeTransition(
            opacity: animation,
            child: (ModalRoute.of(context)!.settings as _FadePage).child,
          ),
        );
}

Future<HelmRouter> _pump(WidgetTester tester, {ThemeData? theme}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async => null);
  final router = HelmRouter(routes: _R.values, enableLogs: false);
  await tester.pumpWidget(MaterialApp.router(theme: theme, routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

BuildContext _ctx(WidgetTester tester) => tester.element(find.text('Home'));

void main() {
  testWidgets('buildPage gives a route its own page and route', (tester) async {
    await _pump(tester);

    HelmRouter.push(_ctx(tester), _R.fade);
    await tester.pumpAndSettle();

    expect(find.text('Fade '), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('Fade '))), isA<_FadeRoute>());
  });

  testWidgets('a custom page updates its content in the same route', (tester) async {
    final router = await _pump(tester);
    HelmRouter.push(_ctx(tester), _R.fade, queryParams: {'n': '1'});
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('Fade 1')));

    router.delegate.change((pages) => [pages.first, _R.fade.page(queryParams: {'n': '2'})]);
    await tester.pumpAndSettle();

    expect(find.text('Fade 2'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('Fade 2'))), same(route));
  });

  testWidgets('routes without buildPage use pageType', (tester) async {
    await _pump(tester);

    HelmRouter.push(_ctx(tester), _R.sheet);
    await tester.pumpAndSettle();

    expect(ModalRoute.of(tester.element(find.text('Sheet'))), isA<ModalBottomSheetRoute<Object?>>());
  });

  testWidgets('a bottom sheet route uses the material_ui theme of the app', (tester) async {
    const color = Color(0xFF123456);
    await _pump(tester, theme: ThemeData(bottomSheetTheme: const BottomSheetThemeData(backgroundColor: color)));

    HelmRouter.push(_ctx(tester), _R.sheet);
    await tester.pumpAndSettle();

    final sheet = find.ancestor(of: find.text('Sheet'), matching: find.byType(Material)).first;
    expect(tester.widget<Material>(sheet).color, color);
  });
}
