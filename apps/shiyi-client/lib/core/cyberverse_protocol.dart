import 'dart:convert';

enum CyberVerseMode { standard, omni }

/// Wire fields verified against upstream commit 13a6a95b. Unknown fields survive
/// parsing so provider-specific transports are never silently treated as Direct.
class CyberVerseSession {
  final Map<String, dynamic> data;
  CyberVerseSession.fromJson(Map<String, dynamic> json)
    : data = Map.unmodifiable(json) {
    if (json['session_id'] is! String ||
        (json['session_id'] as String).isEmpty) {
      throw const FormatException('Missing CyberVerse session_id');
    }
  }

  String get id => data['session_id'] as String;
  String? get mode => data['mode'] as String?;
  String? get streamingMode => data['streaming_mode'] as String?;
  bool get avatarEnabled => data['avatar_enabled'] == true;
  bool get audioInputEnabled =>
      data['audio_input'] is Map &&
      (data['audio_input'] as Map)['enabled'] == true;
  String? get liveKitUrl => data['livekit_url'] as String?;
  String? get liveKitToken => data['livekit_token'] as String?;
  List<String> get warnings =>
      (data['warnings'] as List? ?? const []).whereType<String>().toList();

  // These providers require their own SDK/player, even when streaming_mode
  // reports direct for the microphone transport.
  String? get externalAvatarProvider {
    for (final key in ['vidu', 'xunfei', 'baidu_xiling']) {
      if (data[key] is Map) return key;
    }
    return null;
  }
}

class CyberVerseEvent {
  final String type;
  final Map<String, dynamic> data;
  CyberVerseEvent._(this.type, this.data);

  factory CyberVerseEvent.decode(dynamic payload) {
    final decoded = jsonDecode(
      payload is String ? payload : utf8.decode((payload as List).cast<int>()),
    );
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] is! String ||
        (decoded['type'] as String).isEmpty) {
      throw const FormatException('Invalid CyberVerse WebSocket event');
    }
    return CyberVerseEvent._(
      decoded['type'] as String,
      Map.unmodifiable(decoded),
    );
  }

  bool get isFinal => data['is_final'] == true;
  int? get turnSequence =>
      data['turn_seq'] is num ? (data['turn_seq'] as num).toInt() : null;
  String? get text => data['text'] as String?;
}

/// Exact client-to-server messages; the server is the SDP offerer.
abstract final class CyberVerseSignal {
  static Map<String, dynamic> textInput(String text) {
    if (text.trim().isEmpty) throw ArgumentError.value(text, 'text');
    return {'type': 'text_input', 'text': text};
  }

  static Map<String, dynamic> get ready => {'type': 'webrtc_ready'};
  static Map<String, dynamic> get interrupt => {'type': 'interrupt'};
  static Map<String, dynamic> get mediaReady => {'type': 'client_media_ready'};

  static Map<String, dynamic> answer(String sdp) {
    if (sdp.trim().isEmpty) throw ArgumentError.value(sdp, 'sdp');
    return {'type': 'webrtc_answer', 'sdp': sdp};
  }

  static Map<String, dynamic> iceCandidate(
    String candidate, {
    String? sdpMid,
    int? sdpMLineIndex,
  }) {
    if (candidate.isEmpty) throw ArgumentError.value(candidate, 'candidate');
    if (sdpMLineIndex != null && (sdpMLineIndex < 0 || sdpMLineIndex > 65535)) {
      throw ArgumentError.value(sdpMLineIndex, 'sdpMLineIndex');
    }
    return {
      'type': 'ice_candidate',
      'candidate': candidate,
      if (sdpMid != null) 'sdp_mid': sdpMid,
      if (sdpMLineIndex != null) 'sdp_mline_index': sdpMLineIndex,
    };
  }
}
