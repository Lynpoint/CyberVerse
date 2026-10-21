import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/main.dart';
import 'package:cyberverse_app/screens/contact_screen.dart';

void main() {
  testWidgets('Login remains disabled until the agreement is checked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.runAsync(state.initialize);
    await tester.pumpWidget(CyberVerseApp(state: state));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth_submit')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byKey(const Key('consent')));
    await tester.tap(find.byKey(const Key('consent')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth_submit')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Mobile navigation, contact search, chat and call screens render',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await tester.runAsync(() async {
        await state.initialize();
        await state.login('demo', 'Demo12345', consent: true);
      });
      await tester.pumpWidget(CyberVerseApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('我的记忆伙伴'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('发现'));
      await tester.pumpAndSettle();
      expect(find.text('生活记录'), findsOneWidget);
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(find.text('01 / 上传形象图片'), findsOneWidget);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('编辑个人资料'), findsOneWidget);
      await tester.tap(find.text('好友'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('contact_search')), '林屿');
      await tester.pumpAndSettle();
      expect(find.text('苏晚'), findsNothing);
      await tester.tap(find.text('林屿').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字聊天'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_input')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('chat_input')), '你好');
      await tester.tap(find.byKey(const Key('send_message')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(state.conversations['sample_lin']!.where((m) => m.mine).length, 1);
      expect(
        state.conversations['sample_lin']!.where((m) => !m.mine).length,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(home: CallScreen(human: state.contacts.first, video: true)),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('模拟视频通话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
