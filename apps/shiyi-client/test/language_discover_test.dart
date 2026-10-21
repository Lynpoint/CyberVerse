import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/core/language.dart';
import 'package:cyberverse_app/main.dart';
import 'package:cyberverse_app/screens/discover_screen.dart';

void main() {
  testWidgets('language toggles without losing login fields and persists', (
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
    await tester.pumpAndSettle();
    expect(find.text('欢迎回到时忆'), findsNothing);
    expect(find.byKey(const Key('auth_brand')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone')), '13800138000');
    await tester.tap(find.byKey(const Key('language_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('13800138000'), findsOneWidget);
    expect(find.text('微信登录 · 演示'), findsNothing);
    expect(state.prefs.getString('language_v1'), 'en');
    await tester.tap(find.byKey(const Key('language_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('手机号登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['zh', 'en']) {
    for (final size in [
      const Size(360, 640),
      const Size(390, 844),
      const Size(1280, 900),
    ]) {
      testWidgets('life journal and editor work in $language at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        SharedPreferences.setMockInitialValues({'language_v1': language});
        final state = AppState(await SharedPreferences.getInstance());
        await tester.runAsync(() async {
          await state.initialize();
          await state.login('demo', 'Demo12345', consent: true);
        });
        await tester.pumpWidget(CyberVerseApp(state: state));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tr('发现')));
        await tester.pumpAndSettle();
        expect(find.byType(DiscoverScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('post_life_lin')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('post_comment')),
          'A meaningful day',
        );
        await tester.tap(find.byKey(const Key('send_comment')));
        await tester.pumpAndSettle();
        expect(
          state.life.comments['life_lin']!.single.body,
          'A meaningful day',
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('new_post')));
        await tester.pumpAndSettle();
        final footer = find.byKey(const Key('post_editor_actions'));
        final initial = tester.getRect(footer);
        await tester.enterText(find.byKey(const Key('post_title')), '自己的标题');
        await tester.enterText(
          find.byKey(const Key('post_body')),
          'Keep my original content.',
        );
        await tester.drag(find.byType(ListView).last, const Offset(0, -350));
        await tester.pumpAndSettle();
        final aiSwitch = find.byKey(const Key('post_ai_generated'));
        await tester.ensureVisible(aiSwitch);
        expect(tester.widget<SwitchListTile>(aiSwitch).value, isFalse);
        await tester.tap(aiSwitch);
        await tester.pumpAndSettle();
        expect(tester.getRect(footer), initial);
        expect(
          find.byKey(const Key('publish_post')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('save_draft')));
        await tester.pumpAndSettle();
        expect(state.life.draft!['title'], '自己的标题');
        expect(state.life.draft!['aiGenerated'], isTrue);
        await tester.drag(find.byType(ListView).last, const Offset(0, 1400));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('post_title')));
        expect(
          find.byKey(const Key('post_title')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('post_title')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('publish_post'))).bottom,
          lessThanOrEqualTo(size.height - 240),
        );
        expect(
          find.byKey(const Key('publish_post')).hitTestable(),
          findsOneWidget,
        );
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('publish_post')));
        await tester.pumpAndSettle();
        expect(state.life.posts.first.title, '自己的标题');
        expect(state.life.posts.first.aiGenerated, isTrue);
        expect(find.text(tr('内容由AI生成')), findsWidgets);
        expect(state.life.draft, isNull);
        expect(find.text('自己的标题'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
