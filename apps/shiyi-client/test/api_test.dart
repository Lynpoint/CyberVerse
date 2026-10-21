import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cyberverse_app/core/cyberverse_api.dart';
import 'package:cyberverse_app/core/cyberverse_protocol.dart';

void main() {
  test('WebSocket paths encode IDs exactly once and retain proxy prefix', () {
    final api = CyberVerseApi('https://example.invalid/gateway/');
    final uri = api.chatSocket('a/b ?');
    expect(uri.pathSegments, ['gateway', 'ws', 'chat', 'a/b ?']);
    expect(uri.hasQuery, isFalse);
    api.close();
  });
  test(
    'Adapter follows verified CyberVerse session and message routes',
    () async {
      final requests = <http.Request>[];
      final api = CyberVerseApi(
        'http://localhost:8080/',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({'session_id': 'abc', 'status': 'ok'}),
            200,
          );
        }),
      );
      await api.health();
      final session = await api.createSession('person');
      expect(session.id, 'abc');
      await api.sendMessage('abc', '你好');
      expect(requests[0].url.path, '/api/v1/health');
      expect(requests[1].url.path, '/api/v1/sessions');
      expect(jsonDecode(requests[1].body)['character_id'], 'person');
      expect(jsonDecode(requests[1].body).containsKey('mode'), isFalse);
      expect(requests[2].url.path, '/api/v1/sessions/abc/message');
      expect(jsonDecode(requests[2].body)['text'], '你好');
      expect(
        api.chatSocket('abc').toString(),
        'ws://localhost:8080/ws/chat/abc',
      );
      api.close();
    },
  );
  test('Server failures are not treated as successful responses', () async {
    final api = CyberVerseApi(
      'https://example.invalid',
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    await expectLater(api.health(), throwsStateError);
    expect(api.chatSocket('abc').scheme, 'wss');
    api.close();
  });

  test(
    'Explicit mode, media fields and provider configuration survive parsing',
    () async {
      final api = CyberVerseApi(
        'https://example.invalid/gateway/api/v1/',
        client: MockClient((request) async {
          expect(request.url.path, '/gateway/api/v1/sessions');
          expect(jsonDecode(request.body)['mode'], 'omni');
          return http.Response(
            jsonEncode({
              'session_id': 's1',
              'mode': 'omni',
              'streaming_mode': 'livekit',
              'avatar_enabled': true,
              'audio_input': {'enabled': true},
              'livekit_url': 'wss://rtc.example.invalid',
              'livekit_token': 'test-token',
              'warnings': ['test warning'],
              'xunfei': {'protocol': 'flv'},
              'visual_input': {'enabled': true},
            }),
            201,
          );
        }),
      );
      final session = await api.createSession(
        'character',
        mode: CyberVerseMode.omni,
      );
      expect(session.streamingMode, 'livekit');
      expect(session.avatarEnabled, isTrue);
      expect(session.audioInputEnabled, isTrue);
      expect(session.liveKitUrl, 'wss://rtc.example.invalid');
      expect(session.liveKitToken, 'test-token');
      expect(session.externalAvatarProvider, 'xunfei');
      expect(session.warnings, ['test warning']);
      expect(session.data['visual_input'], {'enabled': true});
      expect(
        api.chatSocket('s1').toString(),
        'wss://example.invalid/gateway/ws/chat/s1',
      );
      api.close();
    },
  );

  test('Root validation rejects credentials and non-HTTP URLs', () {
    for (final input in [
      'localhost:8080',
      'ftp://host',
      'https://u:p@host',
      'https://host?token=x',
      'https://host/#x',
    ]) {
      expect(() => CyberVerseApi(input), throwsArgumentError);
    }
  });

  test('HTTP errors preserve bounded server detail', () async {
    final api = CyberVerseApi(
      'https://example.invalid',
      client: MockClient(
        (_) async => http.Response('{"error":"inference unavailable"}', 503),
      ),
    );
    await expectLater(
      api.health(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('inference unavailable'),
        ),
      ),
    );
    api.close();
  });

  test(
    'Character, history, component and deletion routes match upstream',
    () async {
      final requests = <http.Request>[];
      final api = CyberVerseApi(
        'http://localhost:8080',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            r.method == 'DELETE' ? '' : '[]',
            r.method == 'DELETE' ? 204 : 200,
          );
        }),
      );
      await api.getCharacter('char-1');
      await api.conversationMessages('char-1');
      await api.components();
      await api.deleteSession('s1');
      expect(requests.map((r) => r.url.path).toList(), [
        '/api/v1/characters/char-1',
        '/api/v1/characters/char-1/conversations/messages',
        '/api/v1/components',
        '/api/v1/sessions/s1',
      ]);
      expect(requests.last.method, 'DELETE');
      api.close();
    },
  );
}
