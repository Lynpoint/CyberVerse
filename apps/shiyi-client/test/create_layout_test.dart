import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/main.dart';
import 'package:cyberverse_app/core/language.dart';
import 'package:cyberverse_app/core/ui.dart';
import 'package:cyberverse_app/core/voice_sample.dart';
import 'package:cyberverse_app/screens/create_screen.dart';
import 'voice_sample_test.dart' show FakeVoiceRecorder, FakeVoicePreview;

class _UploadPicker extends FilePicker {
  final Uint8List photo;
  _UploadPicker(this.photo);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final image = allowedExtensions!.contains('jpg');
    final bytes = image ? photo : Uint8List.fromList([82, 73, 70, 70]);
    return FilePickerResult([
      PlatformFile(
        name: image
            ? 'portrait-with-a-long-file-name.jpg'
            : 'voice-with-a-long-file-name.wav',
        size: bytes.length,
        bytes: bytes,
      ),
    ]);
  }
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final size in [
      const Size(360, 640),
      const Size(390, 844),
      const Size(1280, 900),
    ]) {
      testWidgets('Recording footer and lifecycle in $language at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => AppLanguage.code = 'zh');
        AppLanguage.code = language;
        final semantics = tester.ensureSemantics();
        SharedPreferences.setMockInitialValues({});
        final state = AppState(await SharedPreferences.getInstance());
        final recorder = FakeVoiceRecorder();
        final preview = FakeVoicePreview();
        final audio = VoiceSampleController(
          recorder: recorder,
          preview: preview,
        );
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        FilePicker.platform = _UploadPicker(
          (await rootBundle.load(
            'assets/portraits/lin.jpg',
          )).buffer.asUint8List(),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme('极光记忆'),
            home: Center(
              child: SizedBox(
                width: 440,
                child: Scaffold(
                  body: ValueListenableBuilder<bool>(
                    valueListenable: active,
                    builder: (_, value, _) => CreateScreen(
                      state: state,
                      onCreated: () {},
                      active: value,
                      voiceController: audio,
                    ),
                  ),
                  bottomNavigationBar: const SizedBox(
                    key: Key('test_navigation'),
                    height: 85,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const Key('create_content')),
          const Offset(0, -260),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('pick_photo')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pick_photo')));
        await tester.pump();
        for (
          var i = 0;
          i < 50 && find.text(tr('读取文件中…')).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final next = find.byKey(const Key('create_next'));
        final footer = find.byKey(const Key('create_actions'));
        await tester.tap(next);
        await tester.pumpAndSettle();
        final pinned = tester.getRect(footer);
        expect(
          tester.getRect(find.byKey(const Key('test_navigation'))).top -
              pinned.bottom,
          closeTo(8, .1),
        );
        await tester.ensureVisible(find.text(tr('直接录音')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tr('直接录音')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('voice_reading_passage')), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(LinearProgressIndicator)).label,
          tr('录音进度'),
        );
        expect(find.text(tr('朗读参考文本 · 内容由AI生成')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('record_voice')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('record_voice')));
        await tester.pump();
        expect(audio.recording, isTrue);
        recorder.addSeconds(12);
        await tester.pump(const Duration(seconds: 12));
        await tester.drag(
          find.byKey(const Key('create_content')),
          const Offset(0, -700),
        );
        await tester.pump();
        expect(tester.getRect(footer), pinned);
        expect(next.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: next, matching: find.text(tr('停止并使用录音'))),
          findsOneWidget,
        );
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(audio.sample!.duration, const Duration(seconds: 12));
        expect(
          find.descendant(of: next, matching: find.text(tr('下一步'))),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byKey(const Key('preview_voice')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preview_voice')));
        await tester.pumpAndSettle();
        expect(audio.playing, isTrue);
        await tester.tap(find.byKey(const Key('create_back')));
        await tester.pumpAndSettle();
        expect(audio.playing, isFalse);
        expect(audio.sample, isNotNull);
        await tester.tap(next);
        await tester.pumpAndSettle();
        await audio.startRecording();
        active.value = false;
        await tester.pumpAndSettle();
        expect(audio.busy, isFalse);
        expect(recorder.cancels, greaterThan(0));
        active.value = true;
        await tester.pumpAndSettle();
        await audio.startRecording();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(audio.busy, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(audio.sample, isNotNull);
        expect(tester.getRect(footer), pinned);
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets('Upload actions stay above navigation at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await tester.runAsync(() async {
        await state.initialize();
        await state.login('demo', 'Demo12345', consent: true);
      });
      FilePicker.platform = _UploadPicker(
        (await rootBundle.load(
          'assets/portraits/lin.jpg',
        )).buffer.asUint8List(),
      );
      await tester.pumpWidget(CyberVerseApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      final action = find.byKey(const Key('create_next'));
      final content = find.byKey(const Key('create_content'));
      final footer = find.byKey(const Key('create_actions'));
      void verifyPinned() {
        final nav = tester.getRect(find.byKey(const Key('home_navigation')));
        final bar = tester.getRect(footer);
        expect(nav.top - bar.bottom, closeTo(8, .1));
        expect(tester.getRect(action).bottom, lessThan(nav.top));
        expect(tester.getRect(content).bottom, lessThanOrEqualTo(bar.top));
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      verifyPinned();
      final initial = tester.getRect(footer);
      await tester.drag(content, const Offset(0, -240));
      await tester.pumpAndSettle();
      verifyPinned();
      await tester.ensureVisible(find.byKey(const Key('pick_photo')));
      expect(find.byKey(const Key('pick_photo')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick_photo')));
      await tester.pump();
      for (
        var i = 0;
        i < 50 && find.text('读取文件中…').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('更换'), findsOneWidget);
      verifyPinned();
      await tester.drag(content, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getRect(footer), initial);
      verifyPinned();

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('02 / 录入声音样本'), findsOneWidget);
      await tester.drag(content, const Offset(0, -240));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pick_voice')));
      expect(find.byKey(const Key('pick_voice')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick_voice')));
      await tester.pumpAndSettle();
      expect(find.text('更换声音文件'), findsOneWidget);
      verifyPinned();
      expect(tester.getRect(footer), initial);
      expect(
        find.byKey(const Key('create_back')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('create_back')));
      await tester.pumpAndSettle();
      expect(find.text('01 / 上传形象图片'), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('更换声音文件'), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('03 / 完善基础信息'), findsOneWidget);
      verifyPinned();

      await tester.ensureVisible(find.byKey(const Key('human_name')));
      await tester.tap(find.byKey(const Key('human_name')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(action).bottom,
        lessThanOrEqualTo(size.height - 240),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
