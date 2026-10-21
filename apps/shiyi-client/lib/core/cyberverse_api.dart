import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'cyberverse_protocol.dart';
import 'cyberverse_socket.dart';

class CyberVerseHttpException extends StateError {
  final int statusCode;
  CyberVerseHttpException(this.statusCode, String message) : super(message);
}

/// Adapter for verified upstream routes. Authentication and voice enrollment
/// require an application backend; this adapter does not invent those routes.
class CyberVerseApi {
  final String baseUrl;
  final http.Client client;
  CyberVerseApi(String url, {http.Client? client})
    : baseUrl = normalizeBaseUrl(url),
      client = client ?? http.Client();

  static String normalizeBaseUrl(String url) {
    var uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError(
        'Expected an http(s) server root without credentials, query or fragment',
      );
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v1')) path = path.substring(0, path.length - 7);
    uri = uri.replace(path: path);
    return uri.toString().replaceAll(RegExp(r'/+$'), '');
  }

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');
  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['error'] is String) {
          detail = decoded['error'] as String;
          if (detail.length > 500) detail = detail.substring(0, 500);
        }
      } on FormatException {
        // Reverse proxies may return HTML instead of API JSON.
      }
      throw CyberVerseHttpException(
        response.statusCode,
        'CyberVerse HTTP ${response.statusCode}${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    return response.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Map<String, dynamic>> health() async => Map<String, dynamic>.from(
    _decode(
      await client.get(_uri('/health')).timeout(const Duration(seconds: 8)),
    ),
  );
  Future<dynamic> listCharacters() async => _decode(
    await client.get(_uri('/characters')).timeout(const Duration(seconds: 15)),
  );
  Future<dynamic> components() async => _decode(
    await client.get(_uri('/components')).timeout(const Duration(seconds: 15)),
  );
  Future<dynamic> getCharacter(String id) async => _decode(
    await client
        .get(_uri('/characters/${Uri.encodeComponent(id)}'))
        .timeout(const Duration(seconds: 15)),
  );
  Future<dynamic> conversationMessages(String id) async => _decode(
    await client
        .get(
          _uri('/characters/${Uri.encodeComponent(id)}/conversations/messages'),
        )
        .timeout(const Duration(seconds: 15)),
  );
  Future<dynamic> createCharacter(Map<String, dynamic> form) async => _decode(
    await client
        .post(
          _uri('/characters'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(form),
        )
        .timeout(const Duration(seconds: 30)),
  );
  Future<dynamic> uploadAvatar(
    String id,
    Uint8List bytes,
    String filename,
  ) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/characters/${Uri.encodeComponent(id)}/avatar'),
          )
          ..files.add(
            http.MultipartFile.fromBytes('avatar', bytes, filename: filename),
          );
    return _decode(
      await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      ),
    );
  }

  Future<CyberVerseSession> createSession(
    String characterId, {
    CyberVerseMode? mode,
  }) async => CyberVerseSession.fromJson(
    Map<String, dynamic>.from(
      _decode(
        await client
            .post(
              _uri('/sessions'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'character_id': characterId,
                if (mode != null) 'mode': mode.name,
              }),
            )
            .timeout(const Duration(seconds: 150)),
      ),
    ),
  );
  Future<void> sendMessage(String sessionId, String text) async {
    _decode(
      await client
          .post(
            _uri('/sessions/${Uri.encodeComponent(sessionId)}/message'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 15)),
    );
  }

  Future<void> deleteSession(String sessionId) async {
    _decode(
      await client
          .delete(_uri('/sessions/${Uri.encodeComponent(sessionId)}'))
          .timeout(const Duration(seconds: 15)),
    );
  }

  Uri chatSocket(String sessionId) {
    final uri = Uri.parse(baseUrl);
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '${uri.path}/ws/chat/${Uri.encodeComponent(sessionId)}',
    );
  }

  Future<CyberVerseSocket> connectChat(String sessionId) =>
      CyberVerseSocket.connect(chatSocket(sessionId));

  void close() => client.close();
}
