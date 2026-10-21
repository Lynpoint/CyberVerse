import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'cyberverse_protocol.dart';

/// Web/Android signaling transport, not a media player or RTC peer. Subscribe
/// to events before sending webrtc_ready. Reconnect explicitly with a session
/// policy; automatic retries can duplicate messages or create billable sessions.
class CyberVerseSocket {
  final WebSocketChannel _channel;
  bool _closed = false;
  CyberVerseSocket._(this._channel);

  static Future<CyberVerseSocket> connect(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(timeout);
      return CyberVerseSocket._(channel);
    } catch (_) {
      // Consume transport errors when a connection fails before a caller can
      // attach its event listener. Closing also cancels timed-out handshakes.
      channel.stream.listen((_) {}, onError: (Object _) {});
      try {
        await channel.sink.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      } catch (_) {
        // Preserve the original handshake failure if cleanup also fails.
      }
      rethrow;
    }
  }

  late final Stream<CyberVerseEvent> events = _channel.stream.map(
    CyberVerseEvent.decode,
  );

  void send(Map<String, dynamic> message) {
    if (_closed || _channel.closeCode != null) {
      throw StateError('CyberVerse WebSocket is closed');
    }
    _channel.sink.add(jsonEncode(message));
  }

  void sendText(String text) => send(CyberVerseSignal.textInput(text));
  void interrupt() => send(CyberVerseSignal.interrupt);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.sink.close(1000).timeout(const Duration(seconds: 3));
  }
}
