import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';
import 'package:material_ui/material_ui.dart';

enum _R with Routable {
  home('/'),
  sheet('/sheet', PageType.bottomSheet),
  dialog('/dialog', PageType.dialog);

  const _R(this.path, [this.pageType = PageType.material]);

  @override
  final String path;
  @override
  final PageType pageType;

  @override
  Widget builder(Map<String, String> pathParams, Map<String, String> queryParams) => switch (this) {
        home => const Scaffold(body: Text('Home')),
        sheet => const SizedBox(height: 200, child: Text('Sheet')),
        dialog => const Dialog(child: Text('Dialog')),
      };
}

const _color = Color(0xFF123456);

Future<void> _push(WidgetTester tester, _R route) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async => null);
  await tester.pumpWidget(MaterialApp.router(
    theme: ThemeData(
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: _color),
      dialogTheme: const DialogThemeData(backgroundColor: _color),
    ),
    routerConfig: HelmRouter(routes: _R.values, enableLogs: false),
  ));
  await tester.pumpAndSettle();
  HelmRouter.push(tester.element(find.text('Home')), route);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a bottom sheet route uses the material_ui theme of the app', (tester) async {
    await _push(tester, _R.sheet);

    final sheet = find.ancestor(of: find.text('Sheet'), matching: find.byType(Material)).first;
    expect(tester.widget<Material>(sheet).color, _color);
  });

  testWidgets('a dialog route uses the material_ui theme of the app', (tester) async {
    await _push(tester, _R.dialog);

    final dialog = find.ancestor(of: find.text('Dialog'), matching: find.byType(Material)).first;
    expect(tester.widget<Material>(dialog).color, _color);
  });
}
