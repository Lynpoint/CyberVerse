import 'package:flutter/foundation.dart';

String defaultAvatarBackendUrl({bool? web}) {
  const configured = String.fromEnvironment('SHIYI_AVATAR_BACKEND_URL');
  if (configured.isNotEmpty) return configured;
  if (web ?? kIsWeb) return 'http://127.0.0.1:18082';
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:18082'
      : 'http://127.0.0.1:18082';
}

String defaultBackendUrl({bool? web}) {
  const configured = String.fromEnvironment('SHIYI_BACKEND_URL');
  if (configured.isNotEmpty) return configured;
  if (web ?? kIsWeb) return 'http://127.0.0.1:18080';
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:18080'
      : 'http://127.0.0.1:18080';
}

List<Map<String, dynamic>> voiceIceServers(
  List<dynamic> servers,
  String backendUrl,
) {
  final host = Uri.parse(backendUrl).host;
  return servers.whereType<Map>().map((server) {
    final result = Map<String, dynamic>.from(server);
    String rewrite(String url) {
      // Loopback TURN addresses originate inside the server's WSL network.
      // Use the same reachable host as the API for emulator/USB SSH tunnels.
      return url.replaceFirstMapped(
        RegExp(r'^(turns?:)(127.0.0.1|localhost)(?=:)'),
        (match) => '${match[1]}${host.contains(':') ? '[$host]' : host}',
      );
    }

    final urls = result['urls'];
    result['urls'] = urls is String
        ? rewrite(urls)
        : (urls as List? ?? []).whereType<String>().map(rewrite).toList();
    return result;
  }).toList();
}
