import 'dart:async';
import 'dart:convert';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/core/backend_defaults.dart';
import 'package:cyberverse_app/core/cyberverse_api.dart';
import 'package:cyberverse_app/core/cyberverse_protocol.dart';
import 'package:cyberverse_app/core/language.dart';
import 'package:cyberverse_app/core/models.dart';
import 'package:cyberverse_app/core/voice_call.dart';
import 'package:cyberverse_app/core/voice_character.dart';
import 'package:cyberverse_app/core/voice_media.dart';
import 'package:cyberverse_app/screens/contact_screen.dart';
import 'package:cyberverse_app/screens/voice_call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeVoiceMedia extends VoiceMedia {
  bool mic = false, closed = false, denyMicrophone = false;
  bool speaker = true;
  final List<String> signals = [];
  @override
  bool get microphoneEnabled => mic;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> handleSignal(CyberVerseEvent event) async {
    signals.add(event.type);
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    if (enabled && denyMicrophone) throw StateError('denied');
    mic = enabled;
    if (enabled) onState?.call(VoiceMediaState.connecting);
  }

  @override
  Future<void> setSpeaker(bool enabled) async {
    speaker = enabled;
  }

  @override
  Future<void> close() async {
    closed = true;
    mic = false;
    onState = null;
    onSignal = null;
  }

  void connected() => onState?.call(VoiceMediaState.connected);
}

class FakeVoiceSignaling implements VoiceSignaling {
  final source = StreamController<CyberVerseEvent>();
  final List<Map<String, dynamic>> sent = [];
  bool closed = false;
  @override
  Stream<CyberVerseEvent> get events => source.stream;
  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
  }

  void emit(Map<String, dynamic> message) =>
      source.add(CyberVerseEvent.decode(jsonEncode(message)));
  @override
  Future<void> close() async {
    closed = true;
    unawaited(source.close());
  }
}

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppLanguage.code = 'zh';
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    AppLanguage.code = 'zh';
  });

  test(
    'TURN loopback rewrites only host and preserves credentials and public endpoints',
    () {
      final original = [
        {
          'urls': [
            'turn:127.0.0.1:18443?transport=tcp',
            'turns:localhost:443?transport=tcp',
            'stun:stun.example.com:3478',
          ],
          'username': 'opaque',
          'credential': 'private',
        },
        {'urls': 'turn:public.example.com:3478'},
      ];
      final result = voiceIceServers(original, 'http://10.0.2.2:18080');
      expect(result.first['urls'], [
        'turn:10.0.2.2:18443?transport=tcp',
        'turns:10.0.2.2:443?transport=tcp',
        'stun:stun.example.com:3478',
      ]);
      expect(result.first['credential'], 'private');
      expect(result.last, original.last);
      expect((original.first['urls'] as List).first, contains('127.0.0.1'));
      expect(defaultBackendUrl(web: true), 'http://127.0.0.1:18080');
    },
  );

  test(
    'character mapping is persistent and account scoped; no image or audio upload',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final records = <Map<String, dynamic>>[];
      final api = CyberVerseApi(
        'http://test:18080',
        client: MockClient((r) async {
          if (r.method == 'GET' && r.url.path == '/api/v1/characters') {
            return jsonResponse(records);
          }
          if (r.method == 'GET') {
            return jsonResponse(
              records.firstWhere((c) => r.url.path.endsWith(c['id'] as String)),
            );
          }
          final form = jsonDecode(r.body) as Map<String, dynamic>;
          expect(form.keys, isNot(contains('voice_path')));
          expect(form.keys, isNot(contains('avatar_path')));
          expect(form['voice_type'], 'Tina');
          expect(form['system_prompt'], contains('不是真人'));
          records.add({...form, 'id': 'id${records.length}'});
          return jsonResponse(records.last);
        }),
      );
      final human = DigitalHuman.fromJson({
        ...voiceAssistant().toJson(),
        'id': 'personal-contact',
      });
      final repo = VoiceCharacterRepository(prefs, api, 'alice');
      expect(await repo.resolve(human), 'id0');
      expect(await repo.resolve(human), 'id0');
      expect(
        await VoiceCharacterRepository(prefs, api, 'bob').resolve(human),
        'id1',
      );
      expect(records.length, 2);
      api.close();
    },
  );

  test(
    'character create timeout recovers by persisted opaque tag without another POST',
    () async {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? record;
      var posts = 0;
      final api = CyberVerseApi(
        'http://test',
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return jsonResponse([if (record != null) record]);
          }
          posts++;
          record = {
            ...jsonDecode(r.body) as Map<String, dynamic>,
            'id': 'recovered',
          };
          throw TimeoutException('response lost');
        }),
      );
      final human = DigitalHuman.fromJson({
        ...voiceAssistant().toJson(),
        'id': 'personal',
      });
      final repo = VoiceCharacterRepository(prefs, api, 'alice');
      await expectLater(repo.resolve(human), throwsA(isA<TimeoutException>()));
      expect(await repo.resolve(human), 'recovered');
      expect(posts, 1);
      api.close();
    },
  );

  test('avatar requires a portrait before any request', () async {
    var requests = 0;
    final api = CyberVerseApi(
      'http://test',
      client: MockClient((r) async {
        requests++;
        return jsonResponse({});
      }),
    );
    final repo = VoiceCharacterRepository(
      await SharedPreferences.getInstance(),
      api,
      'alice',
      avatar: true,
    );
    await expectLater(repo.resolve(voiceAssistant()), throwsStateError);
    expect(requests, 0);
    api.close();
  });

  test(
    'avatar upload retries without duplicate character; unchanged photos skip upload',
    () async {
      Map<String, dynamic>? record;
      var creates = 0, uploads = 0;
      final api = CyberVerseApi(
        'http://test',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/avatar')) {
            uploads++;
            expect(r.headers['content-type'], contains('multipart/form-data'));
            expect(r.body, contains('name="avatar"'));
            if (uploads == 1) return jsonResponse({'error': 'retry'}, 503);
            if (uploads == 3) {
              return jsonResponse({'error': 'upload retry'}, 404);
            }
            return jsonResponse({'id': 'photo-id'});
          }
          if (r.method == 'GET') {
            return jsonResponse(
              r.url.path.endsWith('/characters')
                  ? [if (record != null) record]
                  : record!,
            );
          }
          creates++;
          record = {
            ...jsonDecode(r.body) as Map<String, dynamic>,
            'id': 'photo-id',
          };
          return jsonResponse(record!);
        }),
      );
      final repo = VoiceCharacterRepository(
        await SharedPreferences.getInstance(),
        api,
        'alice',
        avatar: true,
      );
      final human = DigitalHuman.fromJson({
        ...voiceAssistant().toJson(),
        'photo': base64Encode([1, 2, 3]),
      });
      await expectLater(
        repo.resolve(human),
        throwsA(isA<CyberVerseHttpException>()),
      );
      expect(await repo.resolve(human), 'photo-id');
      expect(await repo.resolve(human), 'photo-id');
      expect(creates, 1);
      expect(uploads, 2);
      final changed = DigitalHuman.fromJson({
        ...human.toJson(),
        'photo': base64Encode([4, 5, 6]),
      });
      await expectLater(
        repo.resolve(changed),
        throwsA(isA<CyberVerseHttpException>()),
      );
      expect(await repo.resolve(changed), 'photo-id');
      expect(uploads, 4);
      expect(creates, 1);
      api.close();
    },
  );

  test('video rejects voice-only server and cleans its session', () async {
    var deleted = false, mediaOpened = false;
    final api = CyberVerseApi(
      'http://test',
      client: MockClient((r) async {
        if (r.method == 'DELETE') {
          deleted = true;
          return http.Response('', 204);
        }
        return jsonResponse(
          r.method == 'POST'
              ? {
                  'session_id': 'voice-only',
                  'avatar_enabled': false,
                  'streaming_mode': 'direct',
                }
              : {'status': 'ok', 'inference_connected': true},
        );
      }),
    );
    final call = VoiceCallController(
      api: api,
      human: voiceAssistant(),
      video: true,
      resolveCharacter: () async => 'character',
      mediaFactory: () {
        mediaOpened = true;
        return FakeVoiceMedia();
      },
    );
    await call.start();
    expect(call.phase, VoiceCallPhase.failed);
    expect(call.error, contains('照片视频'));
    expect(deleted, true);
    expect(mediaOpened, false);
    call.dispose();
  });

  test(
    'unavailable saved character propagates non-404 instead of duplicating',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final human = voiceAssistant();
      final key =
          'voice_character_v1_${base64UrlEncode(utf8.encode('alice|http://test|${human.id}'))}';
      await prefs.setString(key, jsonEncode({'id': 'saved', 'token': 'token'}));
      var calls = 0;
      final api = CyberVerseApi(
        'http://test',
        client: MockClient((r) async {
          calls++;
          return jsonResponse({'error': 'unavailable'}, 503);
        }),
      );
      await expectLater(
        VoiceCharacterRepository(prefs, api, 'alice').resolve(human),
        throwsA(isA<CyberVerseHttpException>()),
      );
      expect(calls, 1);
      api.close();
    },
  );

  test(
    'greeting waits for actual media; transcript merges; hangup cleans session',
    () async {
      final media = FakeVoiceMedia(), socket = FakeVoiceSignaling();
      final deleted = <String>[];
      final api = CyberVerseApi(
        'http://test',
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            deleted.add(r.url.path);
            return http.Response('', 204);
          }
          return jsonResponse(
            r.url.path.endsWith('health')
                ? {'status': 'ok', 'inference_connected': true}
                : {'session_id': 'one', 'streaming_mode': 'direct'},
          );
        }),
      );
      final call = VoiceCallController(
        api: api,
        human: voiceAssistant(),
        resolveCharacter: () async => 'character',
        mediaFactory: () => media,
        socketFactory: (_) async => socket,
      );
      await call.start();
      expect(socket.sent.single['type'], 'webrtc_ready');
      expect(call.canSend, false);
      media.connected();
      media.connected();
      expect(socket.sent.where((s) => s['type'] == 'text_input').length, 1);
      expect(call.canSend, true);
      socket.emit({
        'type': 'transcript',
        'speaker': 'assistant',
        'turn_seq': 1,
        'text': '你',
        'is_final': false,
      });
      socket.emit({
        'type': 'transcript',
        'speaker': 'assistant',
        'turn_seq': 1,
        'text': '好',
        'is_final': false,
      });
      socket.emit({
        'type': 'transcript',
        'speaker': 'assistant',
        'turn_seq': 1,
        'text': '你好！',
        'is_final': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(call.transcripts.single.text, '你好！');
      call.sendText('hello');
      expect(socket.sent.last['text'], 'hello');
      await call.toggleMicrophone();
      expect(call.microphone, true);
      await call.end();
      expect(media.closed, true);
      expect(media.mic, false);
      expect(socket.closed, true);
      expect(deleted, ['/api/v1/sessions/one']);
      expect(call.canStart, true);
      call.dispose();
    },
  );

  test(
    'cancel while session creation is pending deletes late session and never opens media',
    () async {
      final create = Completer<http.Response>();
      final requested = Completer<void>();
      var deleted = false, opened = false;
      final api = CyberVerseApi(
        'http://test',
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            deleted = true;
            return http.Response('', 204);
          }
          if (r.method == 'POST') {
            requested.complete();
            return create.future;
          }
          return jsonResponse({'inference_connected': true});
        }),
      );
      final call = VoiceCallController(
        api: api,
        human: voiceAssistant(),
        resolveCharacter: () async => 'character',
        mediaFactory: () {
          opened = true;
          return FakeVoiceMedia();
        },
      );
      final start = call.start();
      await requested.future;
      await call.end();
      create.complete(
        jsonResponse({'session_id': 'late', 'streaming_mode': 'direct'}),
      );
      await start;
      expect(deleted, true);
      expect(opened, false);
      expect(call.phase, VoiceCallPhase.ended);
      call.dispose();
    },
  );

  test('microphone denial still permits text and live replies', () async {
    final media = FakeVoiceMedia()..denyMicrophone = true;
    final socket = FakeVoiceSignaling();
    final api = CyberVerseApi(
      'http://test',
      client: MockClient(
        (r) async => r.method == 'DELETE'
            ? http.Response('', 204)
            : jsonResponse(
                r.method == 'POST'
                    ? {'session_id': 'one'}
                    : {'inference_connected': true},
              ),
      ),
    );
    final call = VoiceCallController(
      api: api,
      human: voiceAssistant(),
      resolveCharacter: () async => 'character',
      mediaFactory: () => media,
      socketFactory: (_) async => socket,
    );
    await call.start(microphone: true);
    media.connected();
    expect(call.microphone, false);
    expect(call.warning, contains('麦克风不可用'));
    expect(call.canSend, true);
    await call.end();
    call.dispose();
  });

  test('retry waits for old server session cleanup', () async {
    final deletion = Completer<http.Response>();
    final deleteStarted = Completer<void>();
    var creates = 0;
    final media = FakeVoiceMedia(), socket = FakeVoiceSignaling();
    final api = CyberVerseApi(
      'http://test',
      client: MockClient((r) async {
        if (r.method == 'DELETE') {
          deleteStarted.complete();
          return deletion.future;
        }
        if (r.method == 'POST') {
          creates++;
          return jsonResponse({
            'session_id': 'one',
            'streaming_mode': 'direct',
          });
        }
        return jsonResponse({'status': 'ok', 'inference_connected': true});
      }),
    );
    final call = VoiceCallController(
      api: api,
      human: voiceAssistant(),
      resolveCharacter: () async => 'character',
      mediaFactory: () => media,
      socketFactory: (_) async => socket,
    );
    await call.start();
    media.connected();
    media.onState?.call(VoiceMediaState.failed);
    await deleteStarted.future;
    expect(call.phase, VoiceCallPhase.failed);
    expect(call.canStart, false);
    await call.start();
    expect(creates, 1);
    deletion.complete(http.Response('', 204));
    await Future<void>.delayed(Duration.zero);
    expect(call.canStart, true);
    expect(media.closed, true);
    call.dispose();
  });

  for (final language in ['zh', 'en']) {
    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      testWidgets('voice consent and fixed controls at $size in $language', (
        tester,
      ) async {
        AppLanguage.code = language;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState(await SharedPreferences.getInstance());
        await tester.pumpWidget(
          MaterialApp(
            home: VoiceCallScreen(state: state, human: voiceAssistant()),
          ),
        );
        await tester.pumpAndSettle();
        final start = find.byKey(const Key('voice_start'));
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        final controls = find.byKey(const Key('voice_fixed_controls'));
        expect(tester.getRect(controls).bottom, lessThanOrEqualTo(size.height));
        expect(
          tester.getRect(find.byKey(const Key('voice_hangup'))).bottom,
          lessThan(size.height),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('voice_consent')),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('voice_call_body')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('voice_consent'))),
          alignment: .4,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('voice_consent')));
        await tester.pump();
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('original contact voice button opens an in-App consent screen', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: ContactScreen(state: state, human: voiceAssistant()),
      ),
    );
    await tester.tap(find.text('语音通话'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceCallScreen), findsOneWidget);
    expect(find.byKey(const Key('voice_consent')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('voice_start')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final language in ['zh', 'en']) {
    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      testWidgets('photo video consent and controls at $size in $language', (
        tester,
      ) async {
        AppLanguage.code = language;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState(await SharedPreferences.getInstance());
        final human = DigitalHuman.fromJson({
          ...voiceAssistant().toJson(),
          'sample': true,
        });
        await tester.pumpWidget(
          MaterialApp(
            home: VoiceCallScreen(state: state, human: human, video: true),
          ),
        );
        await tester.pumpAndSettle();
        final start = find.byKey(const Key('voice_start'));
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        expect(
          tester.getRect(find.byKey(const Key('voice_fixed_controls'))).bottom,
          lessThanOrEqualTo(size.height),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('voice_consent')),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('voice_call_body')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('voice_consent'))),
          alignment: .4,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('voice_consent')));
        await tester.pump();
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('contact video button opens photo video, not simulated call', (
    tester,
  ) async {
    final state = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: ContactScreen(state: state, human: voiceAssistant()),
      ),
    );
    await tester.tap(find.text('视频聊天'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<VoiceCallScreen>(find.byType(VoiceCallScreen)).video,
      true,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('avatar_pick_photo')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('voice_call_body')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('avatar_pick_photo')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('voice_start')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
