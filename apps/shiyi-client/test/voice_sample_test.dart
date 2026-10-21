import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyberverse_app/core/voice_sample.dart';

class FakeVoiceRecorder implements VoiceRecorder {
  bool permitted = true, failStart = false, failStop = false;
  int starts = 0, stops = 0, cancels = 0, disposals = 0;
  Completer<bool>? permission;
  Completer<void>? starting;
  StreamController<Uint8List>? stream;
  @override
  int sampleRate = 16000;
  @override
  int channels = 1;
  @override
  Future<bool> hasPermission() async =>
      permission == null ? permitted : await permission!.future;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    await starting?.future;
    if (failStart) throw StateError('device unavailable');
    stream = StreamController<Uint8List>(onCancel: () async {});
    return stream!.stream;
  }

  void addSeconds(int seconds) =>
      stream!.add(Uint8List(sampleRate * channels * 2 * seconds));
  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('device lost');
    await stream?.close();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    unawaited(stream?.close());
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class FakeVoicePreview implements VoicePreview {
  int plays = 0, stops = 0, disposals = 0;
  bool fail = false, finishImmediately = false;
  Completer<void>? loading;
  VoidCallback? complete;
  @override
  Future<void> play(VoiceSample sample, VoidCallback onComplete) async {
    plays++;
    complete = onComplete;
    await loading?.future;
    if (fail) throw StateError('invalid media');
    if (finishImmediately) onComplete();
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

Future<void> flushVoiceTasks() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.value();
  }
}

void main() {
  late FakeVoiceRecorder recorder;
  late FakeVoicePreview preview;
  late VoiceSampleController audio;
  final original = VoiceSample(
    Uint8List.fromList([1, 2]),
    'original.wav',
    'wav',
  );
  setUp(() {
    recorder = FakeVoiceRecorder();
    preview = FakeVoicePreview();
    audio = VoiceSampleController(recorder: recorder, preview: preview);
  });
  tearDown(() async {
    audio.dispose();
    await flushVoiceTasks();
  });

  test('does not open microphone before an explicit start', () async {
    audio.select(original);
    await audio.togglePlayback();
    expect(recorder.starts, 0);
    expect(preview.plays, 1);
    preview.complete!();
    expect(audio.playing, isFalse);
  });

  test('permission denied keeps sample and allows retry', () async {
    audio.select(original);
    recorder.permitted = false;
    await audio.startRecording();
    expect(audio.busy, isFalse);
    expect(audio.error, contains('权限'));
    expect(audio.sample, same(original));
    expect(recorder.starts, 0);
    recorder.permitted = true;
    await audio.startRecording();
    expect(audio.recording, isTrue);
    await audio.cancelRecording();
  });

  test('accepts ten seconds as a playable WAV with correct metadata', () async {
    await audio.startRecording();
    recorder.addSeconds(10);
    await flushVoiceTasks();
    await audio.stopRecording();
    final sample = audio.sample!;
    final header = ByteData.sublistView(sample.bytes);
    expect(sample.duration, const Duration(seconds: 10));
    expect(sample.bytes.length, 320044);
    expect(String.fromCharCodes(sample.bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(sample.bytes.sublist(8, 12)), 'WAVE');
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), 320000);
    expect(audio.busy, isFalse);
    expect(audio.error, isNull);
  });

  test('uses hardware-adjusted sample rate in WAV metadata', () async {
    recorder.sampleRate = 48000;
    await audio.startRecording();
    recorder.addSeconds(12);
    await flushVoiceTasks();
    await audio.stopRecording();
    expect(audio.sample!.duration, const Duration(seconds: 12));
    expect(
      ByteData.sublistView(audio.sample!.bytes).getUint32(24, Endian.little),
      48000,
    );
  });

  test('short recordings do not overwrite the accepted sample', () async {
    audio.select(original);
    await audio.startRecording();
    recorder.addSeconds(9);
    await flushVoiceTasks();
    await audio.stopRecording();
    expect(audio.sample, same(original));
    expect(audio.error, contains('不足 10 秒'));
    expect(audio.busy, isFalse);
  });

  test('caps PCM at sixty seconds and stops automatically', () async {
    await audio.startRecording();
    recorder.addSeconds(61);
    await flushVoiceTasks();
    expect(recorder.stops, 1);
    expect(audio.sample!.duration, const Duration(seconds: 60));
    expect(audio.sample!.bytes.length, 1920044);
    expect(audio.sample!.bytes.length, lessThan(2 * 1024 * 1024));
  });

  testWidgets('timer stops even when device stops sending samples', (
    tester,
  ) async {
    final timedAudio = VoiceSampleController(
      recorder: recorder,
      preview: preview,
    );
    await timedAudio.startRecording();
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(recorder.stops, 1);
    expect(timedAudio.busy, isFalse);
    expect(timedAudio.error, contains('不足 10 秒'));
    timedAudio.dispose();
    await tester.pump();
  });

  test('leaving the page cancels microphone and preserves sample', () async {
    audio.select(original);
    await audio.startRecording();
    recorder.addSeconds(12);
    audio.setActive(false);
    await flushVoiceTasks();
    expect(recorder.cancels, greaterThan(0));
    expect(audio.sample, same(original));
    expect(audio.busy, isFalse);
    await audio.startRecording();
    expect(recorder.starts, 1);
    audio.setActive(true);
    await audio.startRecording();
    expect(recorder.starts, 2);
    await audio.cancelRecording();
  });

  test('late permission cannot start recording after leaving', () async {
    recorder.permission = Completer<bool>();
    final starting = audio.startRecording();
    await flushVoiceTasks();
    audio.setActive(false);
    recorder.permission!.complete(true);
    await starting;
    await flushVoiceTasks();
    expect(recorder.starts, 0);
    expect(audio.busy, isFalse);
  });

  test(
    'late device start is cancelled before another session can begin',
    () async {
      recorder.starting = Completer<void>();
      final starting = audio.startRecording();
      await flushVoiceTasks();
      final cancel = audio.cancelRecording();
      await audio.startRecording();
      expect(recorder.starts, 1);
      recorder.starting!.complete();
      await starting;
      await cancel;
      expect(audio.busy, isFalse);
      expect(recorder.cancels, greaterThan(0));
      await audio.startRecording();
      expect(recorder.starts, 2);
      await audio.cancelRecording();
    },
  );

  test('failed starts and stops are recoverable', () async {
    recorder.failStart = true;
    await audio.startRecording();
    expect(audio.error, contains('无法开启'));
    expect(audio.busy, isFalse);
    recorder.failStart = false;
    recorder.failStop = true;
    audio.select(original);
    await audio.startRecording();
    await audio.stopRecording();
    expect(audio.error, contains('处理失败'));
    expect(audio.sample, same(original));
    expect(audio.busy, isFalse);
  });

  test('stream errors cancel microphone and preserve the sample', () async {
    audio.select(original);
    await audio.startRecording();
    recorder.stream!.addError(StateError('device removed'));
    await flushVoiceTasks();
    expect(audio.notice, contains('被中断'));
    expect(recorder.cancels, greaterThan(0));
    expect(audio.sample, same(original));
    expect(audio.busy, isFalse);
  });

  test('late playback is stopped when leaving', () async {
    audio.select(original);
    preview.loading = Completer<void>();
    final loading = audio.togglePlayback();
    await flushVoiceTasks();
    audio.setActive(false);
    preview.loading!.complete();
    await loading;
    await flushVoiceTasks();
    expect(audio.playing, isFalse);
    expect(audio.loadingPlayback, isFalse);
    expect(preview.stops, greaterThan(0));
  });

  test(
    'invalid audio reports playback failure and remains replaceable',
    () async {
      audio.select(original);
      preview.fail = true;
      await audio.togglePlayback();
      expect(audio.error, contains('无法试听'));
      expect(audio.loadingPlayback, isFalse);
      expect(audio.sample, same(original));
    },
  );

  test(
    'very short playback completion does not leave a playing indicator',
    () async {
      audio.select(original);
      preview.finishImmediately = true;
      await audio.togglePlayback();
      expect(audio.playing, isFalse);
    },
  );

  test('WAV keeps complete frames and payload bytes', () {
    final wav = pcmToWav(Uint8List.fromList([1, 2, 3, 4, 5]), 16000, 1);
    expect(wav.length, 48);
    expect(wav.sublist(44), [1, 2, 3, 4]);
  });
}
