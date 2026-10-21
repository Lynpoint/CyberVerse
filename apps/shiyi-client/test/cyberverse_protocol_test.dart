import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyberverse_app/core/cyberverse_protocol.dart';
import 'package:cyberverse_app/core/cyberverse_socket.dart';

void main() {
  test('Direct signaling uses upstream names and snake-case ICE fields', () {
    expect(CyberVerseSignal.ready, {'type': 'webrtc_ready'});
    expect(CyberVerseSignal.answer('sdp'), {
      'type': 'webrtc_answer',
      'sdp': 'sdp',
    });
    expect(
      CyberVerseSignal.iceCandidate(
        'candidate',
        sdpMid: 'audio',
        sdpMLineIndex: 0,
      ),
      {
        'type': 'ice_candidate',
        'candidate': 'candidate',
        'sdp_mid': 'audio',
        'sdp_mline_index': 0,
      },
    );
    expect(CyberVerseSignal.textInput('hello'), {
      'type': 'text_input',
      'text': 'hello',
    });
    expect(CyberVerseSignal.mediaReady, {'type': 'client_media_ready'});
    expect(() => CyberVerseSignal.textInput('  '), throwsArgumentError);
    expect(() => CyberVerseSignal.answer(''), throwsArgumentError);
    expect(
      () => CyberVerseSignal.iceCandidate('c', sdpMLineIndex: -1),
      throwsArgumentError,
    );
  });

  test(
    'Unknown streaming modes are not guessed and malformed sessions fail',
    () {
      final session = CyberVerseSession.fromJson({
        'session_id': 's',
        'streaming_mode': 'future',
      });
      expect(session.streamingMode, 'future');
      expect(session.audioInputEnabled, isFalse);
      expect(session.liveKitToken, isNull);
      expect(() => CyberVerseSession.fromJson({}), throwsFormatException);
      expect(
        () => CyberVerseSession.fromJson({'session_id': ''}),
        throwsFormatException,
      );
    },
  );

  test(
    'JSON events retain unknown fields and distinguish final transcripts',
    () {
      final event = CyberVerseEvent.decode(
        utf8.encode(
          jsonEncode({
            'type': 'transcript',
            'text': 'hello',
            'speaker': 'assistant',
            'is_final': true,
            'turn_seq': 7,
            'future': {'x': 1},
          }),
        ),
      );
      expect(event.type, 'transcript');
      expect(event.text, 'hello');
      expect(event.isFinal, isTrue);
      expect(event.turnSequence, 7);
      expect(event.data['future'], {'x': 1});
      expect(() => CyberVerseEvent.decode('[]'), throwsFormatException);
      expect(
        () => CyberVerseEvent.decode('{"text":"hi"}'),
        throwsFormatException,
      );
    },
  );

  test(
    'Loopback WebSocket receives early events, sends text and closes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<Map<String, dynamic>>();
      final peerReady = Completer<WebSocket>();
      final subscription = server.listen((request) async {
        final peer = await WebSocketTransformer.upgrade(request);
        peerReady.complete(peer);
        peer.add('{"type":"webrtc_config","ice_servers":[]}');
        peer.listen((payload) {
          if (!received.isCompleted) {
            received.complete(jsonDecode(payload as String));
          }
        });
      });
      final socket = await CyberVerseSocket.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws/chat/test'),
      );
      try {
        expect((await socket.events.first).type, 'webrtc_config');
        socket.sendText('hello');
        expect(await received.future.timeout(const Duration(seconds: 2)), {
          'type': 'text_input',
          'text': 'hello',
        });
        await socket.close();
        await socket.close();
        expect(() => socket.sendText('after close'), throwsStateError);
      } finally {
        await (await peerReady.future).close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('Failed WebSocket upgrade propagates an error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {
      request.response.statusCode = 403;
      request.response.close();
    });
    try {
      await expectLater(
        CyberVerseSocket.connect(
          Uri.parse('ws://127.0.0.1:${server.port}/rejected'),
        ),
        throwsA(isA<Exception>()),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
