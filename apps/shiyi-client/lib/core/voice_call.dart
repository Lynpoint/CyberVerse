import 'dart:async';
import 'package:flutter/foundation.dart';
import 'cyberverse_api.dart';
import 'cyberverse_protocol.dart';
import 'cyberverse_socket.dart';
import 'language.dart';
import 'models.dart';
import 'voice_media.dart';

enum VoiceCallPhase {
  ready,
  connecting,
  connected,
  reconnecting,
  failed,
  ended,
}

abstract class VoiceSignaling {
  Stream<CyberVerseEvent> get events;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

class _SocketSignaling implements VoiceSignaling {
  final CyberVerseSocket socket;
  _SocketSignaling(this.socket);
  @override
  Stream<CyberVerseEvent> get events => socket.events;
  @override
  void send(Map<String, dynamic> message) => socket.send(message);
  @override
  Future<void> close() => socket.close();
}

class VoiceTranscript {
  final String key;
  final bool assistant;
  String text;
  bool complete;
  VoiceTranscript(this.key, this.assistant, this.text, this.complete);
}

class VoiceCallController extends ChangeNotifier {
  final CyberVerseApi api;
  final DigitalHuman human;
  final Future<String> Function() resolveCharacter;
  final VoiceMedia Function() mediaFactory;
  final Future<VoiceSignaling> Function(String) socketFactory;
  final bool english;
  final bool video;
  VoiceCallController({
    required this.api,
    required this.human,
    required this.resolveCharacter,
    VoiceMedia Function()? mediaFactory,
    Future<VoiceSignaling> Function(String)? socketFactory,
    this.english = false,
    this.video = false,
  }) : mediaFactory =
           mediaFactory ?? (() => RtcVoiceMedia(api.baseUrl, video: video)),
       socketFactory =
           socketFactory ??
           ((id) async => _SocketSignaling(await api.connectChat(id)));

  VoiceCallPhase phase = VoiceCallPhase.ready;
  String? error, warning;
  String stage = '正在检查服务…';
  String activity = '';
  bool microphone = false, speaker = true, changingMicrophone = false;
  final List<VoiceTranscript> transcripts = [];
  Duration elapsed = Duration.zero;
  VoiceMedia? _media;
  VoiceSignaling? _socket;
  StreamSubscription<CyberVerseEvent>? _subscription;
  String? _sessionId;
  Timer? _timer, _connectionTimer;
  DateTime? _connectedAt;
  int _generation = 0;
  int _releasing = 0;
  bool _disposed = false, _pending = false, _greeted = false;
  Future<void>? _startWork;
  Future<void> _signals = Future.value();
  Future<void> _cleanup = Future.value();

  bool get canStart =>
      !_pending &&
      _releasing == 0 &&
      [
        VoiceCallPhase.ready,
        VoiceCallPhase.failed,
        VoiceCallPhase.ended,
      ].contains(phase);
  bool get canSend => phase == VoiceCallPhase.connected;
  VoiceMedia? get media => _media;
  bool get canChangeMedia =>
      _media != null &&
      [VoiceCallPhase.connected, VoiceCallPhase.reconnecting].contains(phase);
  bool _current(int generation) => !_disposed && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start({bool microphone = false}) {
    if (!canStart || _disposed) return Future.value();
    _pending = true;
    return _startWork = _start(microphone);
  }

  Future<void> _start(bool useMicrophone) async {
    final generation = ++_generation;
    phase = VoiceCallPhase.connecting;
    error = warning = null;
    stage = '正在检查服务…';
    activity = '';
    elapsed = Duration.zero;
    _connectedAt = null;
    _greeted = false;
    transcripts.clear();
    _signals = Future.value();
    _emit();
    try {
      final health = await api.health();
      if (!_current(generation)) return;
      if (health['inference_connected'] != true) {
        throw StateError('Inference unavailable');
      }
      stage = '正在准备语音伙伴…';
      _emit();
      final character = await resolveCharacter();
      if (!_current(generation)) return;
      stage = '正在创建语音会话…';
      _emit();
      final session = await api.createSession(
        character,
        mode: CyberVerseMode.omni,
      );
      if (!_current(generation)) {
        await _deleteSession(session.id);
        return;
      }
      _sessionId = session.id;
      if (session.externalAvatarProvider != null ||
          (session.streamingMode != null &&
              session.streamingMode != 'direct')) {
        await _fail(generation, '该服务器未启用 Direct 纯语音模式');
        return;
      }
      if (video && !session.avatarEnabled) {
        await _fail(generation, '服务器尚未启用照片视频驱动');
        return;
      }
      final media = _media = mediaFactory();
      media.onSignal = (message) {
        if (!_current(generation)) return;
        try {
          _socket?.send(message);
        } catch (_) {
          unawaited(_fail(generation));
        }
      };
      media.onState = (state) => _mediaState(state, generation);
      await media.initialize();
      if (!_current(generation)) return;
      if (useMicrophone) {
        try {
          await media.setMicrophone(true);
        } catch (_) {
          warning = '麦克风不可用，仍可输入文字并听取AI回复';
        }
        if (!_current(generation)) return;
      }
      microphone = media.microphoneEnabled;
      await media.setSpeaker(speaker);
      final socket = await socketFactory(session.id);
      if (!_current(generation)) {
        await _quiet(socket.close);
        return;
      }
      _socket = socket;
      _subscription = socket.events.listen(
        (event) {
          if (!_current(generation)) return;
          if ([
            'webrtc_config',
            'webrtc_offer',
            'ice_candidate',
          ].contains(event.type)) {
            _signals = _signals
                .then((_) async {
                  if (_current(generation)) await media.handleSignal(event);
                })
                .catchError((Object _) {
                  unawaited(_fail(generation));
                });
          } else {
            _event(event, generation);
          }
        },
        onError: (Object _) => unawaited(_fail(generation)),
        onDone: () => unawaited(_fail(generation)),
      );
      stage = '正在建立语音连接…';
      socket.send(CyberVerseSignal.ready);
      _armTimeout(generation);
      _emit();
    } catch (_) {
      await _fail(generation, '语音连接失败，请检查服务器和联调隧道后重试');
    } finally {
      _pending = false;
      _emit();
    }
  }

  void _armTimeout(int generation) {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(
      const Duration(seconds: 40),
      () => unawaited(_fail(generation, '语音连接超时，请重试')),
    );
  }

  void _mediaState(VoiceMediaState state, int generation) {
    if (!_current(generation)) return;
    if (state == VoiceMediaState.failed) {
      unawaited(_fail(generation));
      return;
    }
    if (state == VoiceMediaState.connected) {
      _connectionTimer?.cancel();
      phase = VoiceCallPhase.connected;
      _connectedAt ??= DateTime.now();
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed = DateTime.now().difference(_connectedAt!);
        _emit();
      });
      if (!_greeted) {
        _greeted = true;
        try {
          _socket?.send(
            CyberVerseSignal.textInput(
              english
                  ? 'Greet me briefly in English as the AI companion named ${human.name}. Do not claim to be a real person. Ask how my day is going.'
                  : '请作为名为“${human.name}”的AI数字伙伴，用一句简短自然的普通话向我问好，问我今天过得怎么样。不冒充真人。',
            ),
          );
        } catch (_) {
          unawaited(_fail(generation));
          return;
        }
      }
    } else {
      phase = _connectedAt == null
          ? VoiceCallPhase.connecting
          : VoiceCallPhase.reconnecting;
      activity = '';
      _armTimeout(generation);
    }
    _emit();
  }

  void _event(CyberVerseEvent event, int generation) {
    if (event.type == 'transcript' && event.text?.isNotEmpty == true) {
      final assistant = event.data['speaker'] == 'assistant';
      final key =
          '${assistant ? 'assistant' : 'user'}-${event.turnSequence ?? 'current'}';
      final index = transcripts.indexWhere((item) => item.key == key);
      if (index < 0) {
        transcripts.add(
          VoiceTranscript(key, assistant, event.text!, event.isFinal),
        );
      } else {
        final item = transcripts[index];
        item.text = !assistant || event.isFinal
            ? event.text!
            : item.text + event.text!;
        item.complete = event.isFinal;
      }
      _emit();
    } else if (event.type == 'avatar_status') {
      activity = event.data['status'] as String? ?? '';
      _emit();
    } else if (event.type == 'error') {
      unawaited(_fail(generation, 'AI语音服务发生错误，请重试'));
    }
  }

  void sendText(String value) {
    if (!canSend || value.trim().isEmpty) return;
    try {
      _socket!.send(CyberVerseSignal.textInput(value.trim()));
    } catch (_) {
      unawaited(_fail(_generation));
    }
  }

  Future<void> toggleMicrophone() async {
    if (!canChangeMedia || changingMicrophone) return;
    final generation = _generation, media = _media!;
    changingMicrophone = true;
    warning = null;
    _emit();
    try {
      await media.setMicrophone(!microphone);
    } catch (_) {
      if (_current(generation)) warning = '麦克风不可用，仍可输入文字并听取AI回复';
    } finally {
      if (_current(generation)) {
        microphone = media.microphoneEnabled;
        changingMicrophone = false;
        _emit();
      }
    }
  }

  Future<void> toggleSpeaker() async {
    if (!canChangeMedia) return;
    final generation = _generation, enabled = !speaker;
    try {
      await _media!.setSpeaker(enabled);
      if (_current(generation)) {
        speaker = enabled;
        _emit();
      }
    } catch (_) {
      if (_current(generation)) {
        warning = '声音播放受限，请检查浏览器声音权限';
        _emit();
      }
    }
  }

  Future<void> _fail(int generation, [String? message]) async {
    if (!_current(generation)) return;
    ++_generation;
    phase = VoiceCallPhase.failed;
    error = message ?? '语音连接中断，请重试';
    _emit();
    await _release();
    _emit();
  }

  Future<void> end() async {
    ++_generation;
    phase = VoiceCallPhase.ended;
    _emit();
    await _release();
    _emit();
  }

  Future<void> _quiet(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      /* Cleanup must not leave capture active. */
    }
  }

  Future<void> _deleteSession(String id) => _quiet(() => api.deleteSession(id));

  Future<void> _release() async {
    _releasing++;
    _timer?.cancel();
    _timer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    final media = _media,
        socket = _socket,
        subscription = _subscription,
        sessionId = _sessionId;
    _media = null;
    _socket = null;
    _subscription = null;
    _sessionId = null;
    microphone = false;
    changingMicrophone = false;
    final previous = _cleanup;
    final cleanup = Future.wait([
      previous,
      if (media != null) _quiet(media.close),
      if (subscription != null) _quiet(subscription.cancel),
      if (socket != null) _quiet(socket.close),
      if (sessionId != null) _deleteSession(sessionId),
    ]);
    _cleanup = cleanup.then((_) {});
    try {
      await _cleanup;
    } finally {
      _releasing--;
    }
  }

  String get status => switch (phase) {
    VoiceCallPhase.ready => tr(video ? '准备开始照片视频通话' : '准备开始真实语音通话'),
    VoiceCallPhase.connecting => tr(stage),
    VoiceCallPhase.reconnecting => tr('语音暂时中断，正在恢复…'),
    VoiceCallPhase.failed => tr(error ?? '语音连接中断，请重试'),
    VoiceCallPhase.ended => tr('通话已结束'),
    VoiceCallPhase.connected =>
      activity == 'speaking'
          ? tr('AI正在说话…')
          : activity == 'processing'
          ? tr('AI正在思考…')
          : tr('已连接'),
  };

  @override
  void dispose() {
    _disposed = true;
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await end();
    // A session may arrive after navigation away; let start delete that ID.
    await _startWork;
    await _cleanup;
    api.close();
  }
}
