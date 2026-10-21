import 'package:flutter_test/flutter_test.dart';
import 'package:cyberverse_app/core/voice_preview.dart';

void main() {
  test('local web uses the isolated voice entrypoint', () {
    final uri = voicePreviewUri(
      web: true,
      page: Uri.parse('http://localhost:7358/'),
      configured: '',
    );
    expect(uri?.host, '127.0.0.1');
    expect(uri?.port, 15173);
    expect(uri?.path, '/shiyi-voice.html');
  });
  test('native and hosted clients never assume PC loopback access', () {
    expect(voicePreviewUri(web: false, page: Uri(), configured: ''), isNull);
    expect(
      voicePreviewUri(
        web: true,
        page: Uri.parse('https://example.org'),
        configured: '',
      ),
      isNull,
    );
  });
  test('configured deployment preserves character selection', () {
    final uri = voicePreviewUri(
      web: false,
      page: Uri(),
      configured: 'https://voice.example.org/shiyi-voice.html?character=abc',
    );
    expect(uri?.queryParameters['character'], 'abc');
    expect(uri?.queryParameters['lang'], isNotEmpty);
  });
  test('rejects unsafe URL schemes and embedded credentials', () {
    for (final url in [
      'javascript:alert(1)',
      'https://user:password@example.org/',
    ]) {
      expect(voicePreviewUri(web: false, page: Uri(), configured: url), isNull);
    }
  });
}
