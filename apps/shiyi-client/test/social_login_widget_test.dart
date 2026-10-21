import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/main.dart';

void main() {
  Future<AppState> setup(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    await tester.runAsync(state.initialize);
    await tester.pumpWidget(CyberVerseApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('Phone flow checks consent, wrong code, cooldown and logs in', (
    tester,
  ) async {
    final state = await setup(tester, width: 320);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('send_sms'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('phone')), '13800138000');
    await tap(tester, 'consent');
    await tap(tester, 'send_sms');
    final hint = tester.widget<Text>(find.byKey(const Key('sms_hint'))).data!;
    final code = RegExp(r'\d{6}').firstMatch(hint)!.group(0)!;
    expect(
      tester.widget<TextButton>(find.byKey(const Key('send_sms'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('sms_code')), '000000');
    await tap(tester, 'auth_submit');
    expect(state.loggedIn, false);
    expect(find.text('手机号或验证码不正确'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('sms_code')), code);
    await tap(tester, 'auth_submit');
    expect(state.loggedIn, true);
    expect(find.text('我的记忆伙伴'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Wechat can cancel without login then confirm an independent account',
    (tester) async {
      final state = await setup(tester);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('wechat_login')))
            .onPressed,
        isNull,
      );
      await tap(tester, 'consent');
      await tap(tester, 'wechat_login');
      expect(find.text('微信授权体验'), findsOneWidget);
      await tap(tester, 'wechat_cancel');
      expect(state.loggedIn, false);
      await tap(tester, 'wechat_login');
      await tap(tester, 'wechat_confirm');
      expect(state.loggedIn, true);
      expect(state.nickname, '微信体验用户');
      expect(find.text('我的记忆伙伴'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
