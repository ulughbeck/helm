import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/helm.dart';

import 'setup.dart';

void main() {
  testWidgets('normalizing a platform URL replaces the history entry, navigation pushes one', (tester) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/shop';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    final reports = <(String, bool)>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      if (call.method == 'routeInformationUpdated') {
        final args = call.arguments as Map<Object?, Object?>;
        reports.add((args['uri']! as String, args['replace']! as bool));
      }
      return null;
    });

    final router = HelmRouter(routes: Routes.values, guards: defaultGuards);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    // The platform URL is reported back, then the tabs widget adds its first tab. Both replace.
    expect(reports.map((r) => r.$2), everyElement(isTrue));
    expect(reports.last.$1, '/shop/!category');

    HelmRouter.push(tester.element(find.text('Categories')), Routes.category, pathParams: {'cid': 'laptops'});
    await tester.pumpAndSettle();
    // The push adds an entry. The nested navigator then fills its stack with a replace.
    expect(reports.where((r) => !r.$2).map((r) => r.$1), ['/shop/!category/laptops']);
    expect(reports.last, ('/shop/!category/laptops/!settings', true));
  });
}
