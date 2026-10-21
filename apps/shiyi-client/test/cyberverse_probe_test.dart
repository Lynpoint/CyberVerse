import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/check_backend.dart' as probe;

class ProbeServer {
  final HttpServer server;
  final List<String> requests = [];
  final List<WebSocket> peers = [];
  late final StreamSubscription<HttpRequest> subscription;
  bool healthy = true;
  bool replyError = false;
  String avatarBackend = 'local_image';
  Map<String, dynamic>? sentMessage;

  ProbeServer._(this.server) {
    subscription = server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final peer = await WebSocketTransformer.upgrade(request);
        peers.add(peer);
        peer.listen((raw) {
          sentMessage = jsonDecode(raw as String) as Map<String, dynamic>;
          peer.add(
            jsonEncode(
              replyError
                  ? {'type': 'error', 'message': 'Test provider failure'}
                  : {
                      'type': 'llm_token',
                      'accumulated': 'Test reply',
                      'is_final': true,
                    },
            ),
          );
        });
        return;
      }
      Object? body;
      switch (request.uri.path) {
        case '/api/v1/health':
          body = {
            'status': healthy ? 'ok' : 'error',
            'inference_connected': healthy,
          };
        case '/api/v1/characters':
          body = [
            {
              'id': 'test-character',
              'name': 'Test',
              'avatar_backend': avatarBackend,
            },
          ];
        case '/api/v1/sessions':
          await request.drain<void>();
          body = {
            'session_id': 's1',
            'streaming_mode': 'direct',
            'avatar_enabled': false,
          };
          request.response.statusCode = 201;
        case '/api/v1/sessions/s1':
          request.response.statusCode = 204;
        default:
          request.response.statusCode = 404;
          body = {'error': 'Unexpected route'};
      }
      request.response.headers.contentType = ContentType.json;
      if (body != null) request.response.write(jsonEncode(body));
      await request.response.close();
    });
  }

  static Future<ProbeServer> start() async =>
      ProbeServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  String get url => 'http://127.0.0.1:${server.port}';
  Future<void> close() async {
    for (final peer in peers) {
      await peer.close();
    }
    await subscription.cancel();
    await server.close(force: true);
  }
}

void main() {
  late ProbeServer server;
  setUp(() async {
    exitCode = 0;
    server = await ProbeServer.start();
  });
  tearDown(() async {
    await server.close();
    exitCode = 0;
  });

  test('Default probe is read-only and creates no session', () async {
    await probe.main([server.url]);
    expect(exitCode, 0);
    expect(server.requests, ['GET /api/v1/health', 'GET /api/v1/characters']);
  });

  test('Text probe receives a final reply and deletes its session', () async {
    await probe.main([server.url, 'test-character', 'Test input']);
    expect(exitCode, 0);
    expect(server.sentMessage, {'type': 'text_input', 'text': 'Test input'});
    expect(server.requests.last, 'DELETE /api/v1/sessions/s1');
  });

  test('Server error still releases the session and returns failure', () async {
    server.replyError = true;
    await probe.main([server.url, 'test-character']);
    expect(exitCode, 1);
    expect(server.requests.last, 'DELETE /api/v1/sessions/s1');
  });

  test('Unhealthy inference is a failure despite HTTP 200', () async {
    server.healthy = false;
    await probe.main([server.url, 'test-character']);
    expect(exitCode, 1);
    expect(server.requests.any((r) => r.startsWith('POST')), isFalse);
  });

  test(
    'Unsupported provider is rejected before a billable session starts',
    () async {
      server.avatarBackend = 'vidu';
      await probe.main([server.url, 'test-character']);
      expect(exitCode, 1);
      expect(server.requests.any((r) => r.startsWith('POST')), isFalse);
    },
  );
}
