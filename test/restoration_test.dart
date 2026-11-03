import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

import 'setup.dart';

void main() {
  testWidgets('a restarted app restores the full navigation tree', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async => null);

    await tester.pumpWidget(const _RestorableApp());
    await tester.pumpAndSettle();
    final before = _RestorableAppState.lastRouter!;

    await tester.tap(find.text('Push Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push Laptops'));
    await tester.pumpAndSettle();
    expect(before.delegate.currentUri.toString(), '/shop/!category/laptops/!settings');

    // The restart creates a new router. The platform still reports `/`, so only
    // restoration data can bring back the nested stacks.
    await tester.restartAndRestore();
    final after = _RestorableAppState.lastRouter!;
    expect(identical(after, before), isFalse);
    expect(after.delegate.currentConfiguration, before.delegate.currentConfiguration);
    expect(find.text('Category: laptops'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}

class _RestorableApp extends StatefulWidget {
  const _RestorableApp();

  @override
  State<_RestorableApp> createState() => _RestorableAppState();
}

class _RestorableAppState extends State<_RestorableApp> {
  static HelmRouter? lastRouter;

  late final HelmRouter router = lastRouter = HelmRouter(routes: Routes.values, guards: defaultGuards);

  @override
  Widget build(BuildContext context) => MaterialApp.router(restorationScopeId: 'app', routerConfig: router);
}
