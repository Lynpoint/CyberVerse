import 'dart:async';
import 'dart:io';
import 'package:cyberverse_app/core/cyberverse_api.dart';
import 'package:cyberverse_app/core/cyberverse_protocol.dart';
import 'package:cyberverse_app/core/cyberverse_socket.dart';

/// Read-only by default. Supplying a character ID explicitly creates a
/// temporary standard session and sends text, which may incur provider costs.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 3 || args.first == '--help') {
    stdout.writeln(
      'Usage: dart run tool/check_backend.dart SERVER_ROOT [CHARACTER_ID [TEXT]]',
    );
    stdout.writeln('Without CHARACTER_ID: health and character list only.');
    stdout.writeln(
      'With CHARACTER_ID: creates a standard session, sends text, then deletes the session.',
    );
    return;
  }
  CyberVerseApi? api;
  CyberVerseSession? session;
  CyberVerseSocket? socket;
  StreamSubscription<CyberVerseEvent>? subscription;
  try {
    api = CyberVerseApi(args[0]);
    final health = await api.health();
    stdout.writeln(
      'API: ${health['status']}; inference_connected: ${health['inference_connected']}',
    );
    final characters = await api.listCharacters();
    if (characters is! List) {
      throw const FormatException('Expected character list');
    }
    for (final character in characters.whereType<Map>()) {
      stdout.writeln('${character['id']}  ${character['name']}');
    }
    if (health['inference_connected'] != true || health['status'] != 'ok') {
      throw StateError('API is reachable but inference is not healthy');
    }
    if (args.length < 2) return;
    if (!characters.whereType<Map>().any((c) => c['id'] == args[1])) {
      throw ArgumentError(
        'Choose a character ID from this server, not a local demo ID',
      );
    }
    final character = characters.whereType<Map>().firstWhere(
      (c) => c['id'] == args[1],
    );
    if (character['avatar_backend'] != null &&
        character['avatar_backend'] != 'local_image') {
      throw UnsupportedError(
        'Choose a local_image character; this probe does not connect provider SDKs',
      );
    }
    final message = args.length == 3 ? args[2] : 'Hello';
    CyberVerseSignal.textInput(message);
    session = await api.createSession(args[1], mode: CyberVerseMode.standard);
    stdout.writeln(
      'Session: ${session.id}; streaming_mode: ${session.streamingMode}; avatar: ${session.avatarEnabled}',
    );
    for (final warning in session.warnings) {
      stderr.writeln('Server warning: $warning');
    }
    if (session.externalAvatarProvider != null) {
      throw UnsupportedError(
        'Use an ordinary local_image character for this text probe; provider SDK sessions need their media handshake',
      );
    }
    socket = await api.connectChat(session.id);
    final done = Completer<void>();
    subscription = socket.events.listen(
      (event) {
        if (event.type == 'error') {
          if (!done.isCompleted) {
            done.completeError(StateError('${event.data['message']}'));
          }
        } else if ((event.type == 'llm_token' ||
                (event.type == 'transcript' &&
                    event.data['speaker'] == 'assistant')) &&
            event.isFinal) {
          stdout.writeln(
            'AI-generated content: ${event.data['accumulated'] ?? event.text ?? ''}',
          );
          if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
      onDone: () {
        if (!done.isCompleted) {
          done.completeError(
            StateError('Socket closed before a final response'),
          );
        }
      },
    );
    // Attach the timeout/error listener before sending to avoid racing replies.
    final reply = done.future.timeout(const Duration(seconds: 90));
    try {
      socket.sendText(message);
    } catch (error) {
      if (!done.isCompleted) done.completeError(error);
    }
    await reply;
  } catch (error) {
    stderr.writeln('Backend check failed: $error');
    exitCode = 1;
  } finally {
    try {
      await subscription?.cancel();
      await socket?.close();
    } catch (error) {
      stderr.writeln('Socket cleanup: $error');
      exitCode = 1;
    }
    try {
      if (session != null) await api!.deleteSession(session.id);
    } catch (error) {
      stderr.writeln(
        'Session cleanup failed; server idle timeout still applies: $error',
      );
      exitCode = 1;
    }
    api?.close();
  }
}
