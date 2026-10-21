import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    state = AppState(prefs);
    await state.initialize();
  });
  test('Consent is mandatory for login and registration', () async {
    await expectLater(
      state.login('demo', 'Demo12345', consent: false),
      throwsStateError,
    );
    await expectLater(
      state.register('alice', 'Hello1234', 'Alice', consent: false),
      throwsStateError,
    );
    expect(state.loggedIn, false);
  });
  test(
    'voice and avatar endpoints persist independently per account',
    () async {
      await state.login('demo', 'Demo12345', consent: true);
      final originalAvatar = state.avatarBackendUrl;
      await state.register('alice', 'Hello1234', 'Alice', consent: true);
      state.backendUrl = 'http://voice.test:18080';
      state.avatarBackendUrl = 'http://avatar.test:18082';
      await state.persist();
      final restored = AppState(prefs);
      await restored.initialize();
      await restored.login('alice', 'Hello1234', consent: true);
      expect(restored.backendUrl, 'http://voice.test:18080');
      expect(restored.avatarBackendUrl, 'http://avatar.test:18082');
      restored.logout();
      await restored.login('demo', 'Demo12345', consent: true);
      expect(restored.avatarBackendUrl, originalAvatar);
    },
  );
  test(
    'Authentication validates credentials, uniqueness, and password changes',
    () async {
      await expectLater(
        state.login('demo', 'wrongpass', consent: true),
        throwsStateError,
      );
      await expectLater(
        state.register('alice', 'weak', 'Alice', consent: true),
        throwsStateError,
      );
      await state.register('Alice', 'Hello1234', 'Alice', consent: true);
      expect(state.username, 'alice');
      expect(state.contacts, isEmpty);
      await expectLater(
        state.register('ALICE', 'Hello1234', 'A', consent: true),
        throwsStateError,
      );
      await expectLater(
        state.changePassword('incorrect', 'Changed123'),
        throwsStateError,
      );
      await state.changePassword('Hello1234', 'Changed123');
      state.logout();
      await expectLater(
        state.login('alice', 'Hello1234', consent: true),
        throwsStateError,
      );
      await state.login('alice', 'Changed123', consent: true);
      final stored = prefs.getString('accounts_v1')!;
      expect(stored.contains('Changed123'), false);
      expect(stored.contains('Hello1234'), false);
      expect(jsonDecode(stored)['alice']['salt'], isNotEmpty);
    },
  );
  test(
    'Created contacts and chat persist and are isolated by account',
    () async {
      await state.register('alice', 'Hello1234', 'Alice', consent: true);
      final person = DigitalHuman(
        id: 'one',
        name: '测试伙伴',
        description: '测试',
        personality: '友好',
        greeting: '你好',
        group: 'C',
        color: 0xFFE0EEE7,
        createdAt: DateTime(2026, 10, 18),
      );
      await state.addContact(person);
      await state.addMessage('one', ChatMessage('hello', true));
      await state.setAppearance('aurora');
      final restored = AppState(prefs);
      await restored.initialize();
      await restored.login('alice', 'Hello1234', consent: true);
      expect(restored.contacts.single.name, '测试伙伴');
      expect(restored.conversations['one']!.single.text, 'hello');
      expect(restored.appearance, 'aurora');
      restored.logout();
      await restored.login('demo', 'Demo12345', consent: true);
      expect(restored.contacts.length, 3);
      expect(restored.conversations.containsKey('one'), false);
      restored.logout();
      await restored.login('alice', 'Hello1234', consent: true);
      await restored.deleteContact(restored.contacts.single);
      expect(restored.contacts, isEmpty);
      expect(restored.conversations, isEmpty);
      await restored.deleteAccount();
      expect(restored.loggedIn, false);
      await expectLater(
        restored.login('alice', 'Hello1234', consent: true),
        throwsStateError,
      );
    },
  );
}
