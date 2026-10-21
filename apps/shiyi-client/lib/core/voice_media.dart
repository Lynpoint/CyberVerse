import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'backend_defaults.dart';
import 'cyberverse_protocol.dart';

enum VoiceMediaState { connecting, connected, interrupted, failed }

abstract class VoiceMedia {
  void Function(VoiceMediaState)? onState;
  void Function(Map<String, dynamic>)? onSignal;
  bool get microphoneEnabled;
  RTCVideoRenderer? get videoRenderer => null;
  Future<void> initialize();
  Future<void> handleSignal(CyberVerseEvent event);
  Future<void> setMicrophone(bool enabled);
  Future<void> setSpeaker(bool enabled);
  Future<void> close();
}

class RtcVoiceMedia extends VoiceMedia {
  final String backendUrl;
  final bool video;
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _peer;
  RTCRtpTransceiver? _audioTransceiver;
  MediaStream? _microphone;
  MediaStream? _remote;
  List<Map<String, dynamic>> _iceServers = [];
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _closed = false,
      _initialized = false,
      _micEnabled = false,
      _speaker = true;
  RtcVoiceMedia(this.backendUrl, {this.video = false});
  @override
  RTCVideoRenderer? get videoRenderer =>
      video && _initialized ? _renderer : null;
  @override
  bool get microphoneEnabled => _micEnabled;

  @override
  Future<void> initialize() async {
    if (_closed) return;
    await _renderer.initialize();
    _initialized = true;
    if (_closed) {
      _initialized = false;
      await _renderer.dispose();
      return;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Helper.setSpeakerphoneOn(true);
    }
  }

  @override
  Future<void> handleSignal(CyberVerseEvent event) async {
    if (_closed) return;
    final data = event.data;
    if (event.type == 'webrtc_config') {
      _iceServers = voiceIceServers(
        data['ice_servers'] as List? ?? [],
        backendUrl,
      );
    } else if (event.type == 'webrtc_offer') {
      final old = _peer;
      _peer = null;
      await old?.close();
      if (_closed) return;
      final pc = await createPeerConnection({
        'iceServers': _iceServers,
        'iceTransportPolicy':
            _iceServers.any(
              (server) =>
                  server['urls'].toString().contains('turn:') ||
                  server['urls'].toString().contains('turns:'),
            )
            ? 'relay'
            : 'all',
        'sdpSemantics': 'unified-plan',
      });
      if (_closed) {
        await pc.close();
        return;
      }
      _peer = pc;
      if (video) {
        final previous = _remote;
        _remote = await createLocalMediaStream('shiyi-avatar-remote');
        if (previous != null) await _quiet(previous.dispose);
        if (_closed || _peer != pc) return;
      }
      pc.onIceCandidate = (candidate) {
        if (_peer != pc || _closed || candidate.candidate?.isNotEmpty != true) {
          return;
        }
        onSignal?.call(
          CyberVerseSignal.iceCandidate(
            candidate.candidate!,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
          ),
        );
      };
      pc.onConnectionState = (state) {
        if (_closed || _peer != pc) return;
        onState?.call(switch (state) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
            VoiceMediaState.connected,
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
            VoiceMediaState.interrupted,
          RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
            VoiceMediaState.failed,
          _ => VoiceMediaState.connecting,
        });
      };
      pc.onTrack = (event) {
        if (_closed ||
            _peer != pc ||
            (event.track.kind != 'audio' &&
                !(video && event.track.kind == 'video'))) {
          return;
        }
        _attachAudio(event, pc);
      };
      await pc.setRemoteDescription(
        RTCSessionDescription(data['sdp'] as String, 'offer'),
      );
      // Bind to an offered audio m-line. A pre-created, trackless transceiver
      // can remain unmatched and silently disable outgoing audio in the answer.
      final transceivers = await pc.getTransceivers();
      final audio = transceivers.firstWhere(
        (t) => t.receiver.track?.kind == 'audio',
      );
      await audio.setDirection(TransceiverDirection.SendRecv);
      if (video) {
        for (final transceiver in transceivers) {
          if (transceiver.receiver.track?.kind == 'video') {
            await transceiver.setDirection(TransceiverDirection.RecvOnly);
          }
        }
      }
      if (_closed || _peer != pc) return;
      _audioTransceiver = audio;
      if (_microphone?.getAudioTracks().isNotEmpty == true) {
        await audio.sender.replaceTrack(_microphone!.getAudioTracks().first);
      }
      for (final candidate in _pendingCandidates.toList()) {
        await pc.addCandidate(candidate);
      }
      _pendingCandidates.clear();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      if (!_closed && _peer == pc) {
        onSignal?.call(CyberVerseSignal.answer(answer.sdp!));
      }
    } else if (event.type == 'ice_candidate' && data['candidate'] is String) {
      final candidate = RTCIceCandidate(
        data['candidate'] as String,
        data['sdp_mid'] as String?,
        (data['sdp_mline_index'] as num?)?.toInt(),
      );
      final pc = _peer;
      final description = pc == null ? null : await pc.getRemoteDescription();
      if (_closed) return;
      if (pc != _peer || description == null) {
        _pendingCandidates.add(candidate);
      } else {
        await pc!.addCandidate(candidate);
      }
    }
  }

  Future<void> _attachAudio(RTCTrackEvent event, RTCPeerConnection pc) async {
    try {
      final stream = video
          ? _remote!
          : event.streams.isNotEmpty
          ? event.streams.first
          : await createLocalMediaStream('shiyi-remote');
      if (video || event.streams.isEmpty) {
        if (!stream.getTracks().any((track) => track.id == event.track.id)) {
          await stream.addTrack(event.track);
        }
      }
      if (_closed || _peer != pc) return;
      _remote = stream;
      _renderer.srcObject = stream;
      if (kIsWeb) _renderer.muted = !_speaker;
      await _renderer.setVolume(_speaker ? 1 : 0);
    } catch (_) {
      if (!_closed) onState?.call(VoiceMediaState.failed);
    }
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    if (_closed) return;
    if (enabled && _microphone == null) {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      if (_closed) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        await stream.dispose();
        return;
      }
      _microphone = stream;
      _micEnabled = true;
      final sender = _audioTransceiver?.sender;
      if (sender != null && stream.getAudioTracks().isNotEmpty) {
        try {
          await sender.replaceTrack(stream.getAudioTracks().first);
        } catch (_) {
          for (final track in stream.getTracks()) {
            await track.stop();
          }
          await stream.dispose();
          _microphone = null;
          _micEnabled = false;
          rethrow;
        }
      }
    }
    for (final track in _microphone?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
    _micEnabled = enabled && _microphone != null;
  }

  @override
  Future<void> setSpeaker(bool enabled) async {
    _speaker = enabled;
    if (_closed || _remote == null) return;
    if (kIsWeb) _renderer.muted = !enabled;
    await _renderer.setVolume(enabled ? 1 : 0);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onState = null;
    onSignal = null;
    final pc = _peer;
    _peer = null;
    _audioTransceiver = null;
    final mic = _microphone;
    _microphone = null;
    // Stop capture before any network cleanup can wait on the remote server.
    final stops = [
      for (final track in mic?.getTracks() ?? <MediaStreamTrack>[])
        _quiet(track.stop),
    ];
    _micEnabled = false;
    if (_initialized) {
      _initialized = false;
      _renderer.srcObject = null;
      stops.add(_quiet(_renderer.dispose));
    }
    final remote = _remote;
    _remote = null;
    if (remote != null) stops.add(_quiet(remote.dispose));
    if (mic != null) stops.add(_quiet(mic.dispose));
    if (pc != null) stops.add(_quiet(pc.close));
    await Future.wait(stops);
  }

  Future<void> _quiet(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      /* Complete the remaining teardown. */
    }
  }
}
