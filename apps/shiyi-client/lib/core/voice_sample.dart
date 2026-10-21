import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class VoiceSample {
  final Uint8List bytes;
  final String name, extension;
  final Duration? duration;
  const VoiceSample(this.bytes, this.name, this.extension, {this.duration});
}

abstract interface class VoiceRecorder {
  int get sampleRate;
  int get channels;
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _device;
  AudioRecorder get _recorder => _device ??= AudioRecorder();
  @override
  int sampleRate = 16000;
  @override
  int channels = 1;
  @override
  Future<bool> hasPermission() => _recorder.hasPermission();
  @override
  Future<Stream<Uint8List>> start() async {
    sampleRate = 16000;
    channels = 1;
    await _recorder.setOnConfigChanged((config) {
      sampleRate = config.sampleRate;
      channels = config.numChannels;
    });
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _device?.stop();
  }

  @override
  Future<void> cancel() async {
    await _device?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _device?.dispose();
  }
}

abstract interface class VoicePreview {
  Future<void> play(VoiceSample sample, VoidCallback onComplete);
  Future<void> stop();
  Future<void> dispose();
}

class DeviceVoicePreview implements VoicePreview {
  AudioPlayer? _player;
  StreamSubscription<void>? _complete;
  @override
  Future<void> play(VoiceSample sample, VoidCallback onComplete) async {
    final player = _player ??= AudioPlayer();
    await _complete?.cancel();
    _complete = player.onPlayerComplete.listen((_) => onComplete());
    final mime = switch (sample.extension) {
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      _ => 'audio/mp4',
    };
    await player.play(BytesSource(sample.bytes, mimeType: mime));
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await _complete?.cancel();
    await _player?.dispose();
  }
}

enum VoicePhase { idle, starting, recording, finishing }

class VoiceSampleController extends ChangeNotifier {
  static const minimumSeconds = 10;
  static const maximumSeconds = 60;
  final VoiceRecorder recorder;
  final VoicePreview preview;
  VoiceSampleController({VoiceRecorder? recorder, VoicePreview? preview})
    : recorder = recorder ?? DeviceVoiceRecorder(),
      preview = preview ?? DeviceVoicePreview();

  VoiceSample? sample;
  VoicePhase phase = VoicePhase.idle;
  Duration elapsed = Duration.zero;
  String? error, notice;
  bool playing = false, loadingPlayback = false;
  bool _active = true, _disposed = false;
  int _generation = 0, _playGeneration = 0;
  Timer? _timer;
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _done;
  BytesBuilder _pcm = BytesBuilder(copy: false);
  Future<void>? _startFuture, _stopFuture, _cancelFuture;
  Future<void> _playbackWork = Future<void>.value();

  Future<void> _queuePlayback(Future<void> Function() action) {
    final operation = _playbackWork.then((_) => action());
    _playbackWork = operation.catchError((Object _) {});
    return operation;
  }

  bool get busy => phase != VoicePhase.idle;
  bool get recording => phase == VoicePhase.recording;
  bool _valid(int generation) =>
      !_disposed && _active && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void select(VoiceSample value) {
    if (busy || _disposed) return;
    unawaited(stopPlayback());
    sample = value;
    error = notice = null;
    _emit();
  }

  void clear() {
    sample = null;
    error = notice = null;
    elapsed = Duration.zero;
    unawaited(stopPlayback());
    _emit();
  }

  Future<void> startRecording() {
    if (busy || !_active || _disposed) return Future<void>.value();
    return _startFuture = _startRecording().whenComplete(
      () => _startFuture = null,
    );
  }

  Future<void> _startRecording() async {
    if (busy || !_active || _disposed) return;
    final generation = ++_generation;
    phase = VoicePhase.starting;
    error = notice = null;
    elapsed = Duration.zero;
    _emit();
    try {
      await stopPlayback();
      if (!_valid(generation)) return;
      if (!await recorder.hasPermission()) {
        if (_valid(generation)) error = '未获得麦克风权限，请在浏览器或系统设置中允许，或选择上传声音。';
        return;
      }
      if (!_valid(generation)) return;
      final stream = await recorder.start();
      if (!_valid(generation)) {
        await recorder.cancel();
        return;
      }
      _pcm = BytesBuilder(copy: false);
      final done = _done = Completer<void>();
      phase = VoicePhase.recording;
      _subscription = stream.listen(
        (bytes) {
          if (!_valid(generation)) return;
          final cap =
              recorder.sampleRate * recorder.channels * 2 * maximumSeconds;
          final remaining = cap - _pcm.length;
          if (remaining > 0) {
            _pcm.add(
              bytes.length <= remaining
                  ? bytes
                  : Uint8List.sublistView(bytes, 0, remaining),
            );
          }
          if (_pcm.length >= cap && recording) unawaited(stopRecording());
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
          if (_valid(generation) && recording) unawaited(stopRecording());
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
          if (_valid(generation)) {
            unawaited(cancelRecording(message: '录音被中断，请重新录制；原声音样本仍保留。'));
          }
        },
      );
      _timer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
        elapsed = Duration(
          milliseconds: (timer.tick * 250).clamp(0, maximumSeconds * 1000),
        );
        if (elapsed.inSeconds >= maximumSeconds) {
          unawaited(stopRecording());
        } else {
          _emit();
        }
      });
      _emit();
    } catch (_) {
      try {
        await recorder.cancel();
      } catch (_) {}
      if (_valid(generation)) {
        error = '无法开启录音。请检查麦克风是否被占用；网页版请使用 HTTPS 或 localhost，也可以上传声音。';
      }
    } finally {
      if (!_disposed &&
          generation == _generation &&
          phase == VoicePhase.starting) {
        phase = VoicePhase.idle;
        _emit();
      }
    }
  }

  Future<void> stopRecording() {
    if (!recording) return _stopFuture ?? Future<void>.value();
    return _stopFuture = _stopRecording().whenComplete(
      () => _stopFuture = null,
    );
  }

  Future<void> _stopRecording() async {
    if (!recording) return;
    final generation = _generation;
    phase = VoicePhase.finishing;
    _timer?.cancel();
    _emit();
    try {
      await recorder.stop();
      await _done?.future.timeout(const Duration(seconds: 3));
      if (!_valid(generation)) return;
      final pcm = _pcm.takeBytes();
      final bytesPerSecond = recorder.sampleRate * recorder.channels * 2;
      final duration = Duration(
        microseconds: pcm.length * 1000000 ~/ bytesPerSecond,
      );
      if (duration.inMilliseconds < minimumSeconds * 1000) {
        error = '录音不足 10 秒，请多读几句后重试；原声音样本仍保留。';
        return;
      }
      final wav = pcmToWav(pcm, recorder.sampleRate, recorder.channels);
      if (wav.length > (kIsWeb ? 2 : 20) * 1024 * 1024) {
        error = '录音文件过大，请缩短录音后重试。';
        return;
      }
      sample = VoiceSample(
        wav,
        'voice-${DateTime.now().millisecondsSinceEpoch}.wav',
        'wav',
        duration: duration,
      );
      elapsed = duration;
      notice = '录音已作为声音样本，可试听或重录。';
    } catch (_) {
      try {
        await recorder.cancel();
      } catch (_) {}
      if (_valid(generation)) error = '录音处理失败，请重试；原声音样本仍保留。';
    } finally {
      if (generation == _generation) {
        await _subscription?.cancel();
        _subscription = null;
        _pcm.clear();
        phase = VoicePhase.idle;
        _emit();
      }
    }
  }

  Future<void> cancelRecording({String? message}) {
    if (_cancelFuture != null) return _cancelFuture!;
    if (!busy) return Future<void>.value();
    return _cancelFuture = _cancelRecording(
      message,
    ).whenComplete(() => _cancelFuture = null);
  }

  Future<void> _cancelRecording(String? message) async {
    if (!busy) return;
    final generation = ++_generation;
    _timer?.cancel();
    phase = VoicePhase.finishing;
    notice = message ?? '本次录音已取消，原声音样本仍保留。';
    _emit();
    // Do not allow a new session to start until a pending permission/start
    // operation has returned and released its own microphone stream.
    await _startFuture;
    try {
      await recorder.cancel();
    } catch (_) {}
    await _stopFuture;
    await _subscription?.cancel();
    _subscription = null;
    _pcm.clear();
    if (!_disposed && generation == _generation) {
      phase = VoicePhase.idle;
      _emit();
    }
  }

  void setActive(bool value) {
    _active = value;
    if (!value) {
      unawaited(cancelRecording(message: '已离开录音页面，本次录音已取消，原声音样本仍保留。'));
      unawaited(stopPlayback());
    }
  }

  Future<void> togglePlayback() async {
    if (busy || sample == null || !_active || _disposed || loadingPlayback) {
      return;
    }
    if (playing) return stopPlayback();
    final generation = ++_playGeneration;
    loadingPlayback = true;
    error = null;
    _emit();
    var completed = false;
    try {
      await _queuePlayback(() async {
        if (_disposed || !_active || generation != _playGeneration) return;
        await preview.play(sample!, () {
          completed = true;
          if (!_disposed && generation == _playGeneration) {
            playing = false;
            _emit();
          }
        });
      });
      if (_disposed || !_active || generation != _playGeneration) {
        return;
      }
      playing = !completed;
    } catch (_) {
      if (!_disposed && generation == _playGeneration) {
        error = '无法试听此音频，请检查文件是否有效，或更换为 WAV、MP3、M4A。';
        playing = false;
      }
    } finally {
      if (!_disposed && generation == _playGeneration) {
        loadingPlayback = false;
        _emit();
      }
    }
  }

  Future<void> stopPlayback() async {
    ++_playGeneration;
    playing = loadingPlayback = false;
    try {
      await _queuePlayback(preview.stop);
    } catch (_) {}
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    ++_generation;
    ++_playGeneration;
    _timer?.cancel();
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    await _startFuture;
    try {
      await recorder.cancel();
    } catch (_) {}
    await _stopFuture;
    await _subscription?.cancel();
    try {
      await recorder.dispose();
    } catch (_) {}
    try {
      await _queuePlayback(preview.dispose);
    } catch (_) {}
    _pcm.clear();
  }
}

// Package record supplies PCM samples; this adds only the standard WAV container.
Uint8List pcmToWav(Uint8List pcm, int sampleRate, int channels) {
  final length = pcm.length - pcm.length % (channels * 2);
  final bytes = Uint8List(44 + length);
  final header = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  header.setUint32(4, 36 + length, Endian.little);
  bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  header.setUint32(40, length, Endian.little);
  bytes.setRange(44, bytes.length, pcm);
  return bytes;
}
