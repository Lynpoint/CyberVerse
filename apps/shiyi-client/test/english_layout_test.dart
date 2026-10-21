import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/main.dart';

void main() {
  testWidgets('English primary screens at 360 pixels', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'language_v1': 'en'});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.runAsync(() async {
      await state.initialize();
      await state.login('demo', 'Demo12345', consent: true);
    });
    await tester.pumpWidget(CyberVerseApp(state: state));
    await tester.pumpAndSettle();
    for (final title in ['Discover', 'Create', 'Me', 'Friends']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
  });
}
