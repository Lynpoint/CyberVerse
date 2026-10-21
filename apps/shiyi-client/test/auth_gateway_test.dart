import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/auth_gateway.dart';
import 'package:cyberverse_app/core/app_state.dart';
import 'package:cyberverse_app/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SMS validates number, cooldown, phone binding, expiry and single use',
    () async {
      var now = DateTime(2026);
      final gateway = DemoAuthGateway(clock: () => now);
      await expectLater(gateway.sendSms('123'), throwsStateError);
      final first = await gateway.sendSms('13800138000');
      await expectLater(gateway.sendSms('13800138000'), throwsStateError);
      await expectLater(
        gateway.verifySms('13900139000', first.demoCode!, first.id),
        throwsStateError,
      );
      final identity = await gateway.verifySms(
        '13800138000',
        first.demoCode!,
        first.id,
      );
      expect(identity.id, 'phone:13800138000');
      await expectLater(
        gateway.verifySms('13800138000', first.demoCode!, first.id),
        throwsStateError,
      );
      now = now.add(const Duration(seconds: 60));
      final second = await gateway.sendSms('13800138000');
      now = now.add(const Duration(minutes: 5));
      await expectLater(
        gateway.verifySms('13800138000', second.demoCode!, second.id),
        throwsStateError,
      );
    },
  );
  test(
    'SMS invalidates previous code on resend and locks after five wrong tries',
    () async {
      var now = DateTime(2026);
      final gateway = DemoAuthGateway(clock: () => now);
      final first = await gateway.sendSms('13800138000');
      now = now.add(const Duration(seconds: 60));
      final second = await gateway.sendSms('13800138000');
      await expectLater(
        gateway.verifySms('13800138000', first.demoCode!, first.id),
        throwsStateError,
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          gateway.verifySms('13800138000', '000000', second.id),
          throwsStateError,
        );
      }
      await expectLater(
        gateway.verifySms('13800138000', second.demoCode!, second.id),
        throwsStateError,
      );
    },
  );
  test(
    'WeChat requires confirmation; cancellation, expiry and replay fail',
    () async {
      var now = DateTime(2026);
      final gateway = DemoAuthGateway(clock: () => now);
      final ticket = await gateway.startWechat();
      expect(await gateway.checkWechat(ticket), isNull);
      await gateway.cancelWechat(ticket);
      await expectLater(
        gateway.checkWechat(ticket, demoApproved: true),
        throwsStateError,
      );
      final expired = await gateway.startWechat();
      now = now.add(const Duration(minutes: 3));
      await expectLater(
        gateway.checkWechat(expired, demoApproved: true),
        throwsStateError,
      );
      final valid = await gateway.startWechat();
      expect(
        (await gateway.checkWechat(valid, demoApproved: true))!.id,
        'wechat:demo',
      );
      await expectLater(
        gateway.checkWechat(valid, demoApproved: true),
        throwsStateError,
      );
    },
  );
  test(
    'Phone and WeChat accounts persist separately and require consent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var state = AppState(prefs);
      await state.initialize();
      await expectLater(
        state.requestSms('13800138000', consent: false),
        throwsStateError,
      );
      await expectLater(state.beginWechat(consent: false), throwsStateError);
      final sms = await state.requestSms('13800138000', consent: true);
      await expectLater(
        state.loginPhone('13800138000', sms.demoCode!, sms.id, consent: false),
        throwsStateError,
      );
      await state.loginPhone(
        '13800138000',
        sms.demoCode!,
        sms.id,
        consent: true,
      );
      final key = state.username;
      expect(state.canChangePassword, false);
      await expectLater(
        state.changePassword('old', 'Newpass123'),
        throwsStateError,
      );
      await state.addMessage('sample_lin', ChatMessage('phone only', true));
      state.logout();
      state = AppState(prefs);
      await state.initialize();
      final again = await state.requestSms('13800138000', consent: true);
      await state.loginPhone(
        '13800138000',
        again.demoCode!,
        again.id,
        consent: true,
      );
      expect(state.username, key);
      expect(state.conversations['sample_lin']!.single.text, 'phone only');
      state.logout();
      final wx = await state.beginWechat(consent: true);
      await state.finishWechat(wx, consent: true, demoApproved: true);
      expect(state.username, isNot(key));
      expect(state.conversations, isEmpty);
      expect(state.nickname, '微信体验用户');
      expect(prefs.getString('accounts_v1'), isNot(contains(again.demoCode!)));
    },
  );
  test(
    'HTTP contract never returns demo codes and requires server approval',
    () async {
      final calls = <String>[];
      final gateway = HttpAuthGateway(
        'https://login.example.com',
        client: MockClient((request) async {
          calls.add(request.url.path);
          final body = jsonDecode(request.body);
          switch (request.url.path) {
            case '/v1/auth/sms/send':
              expect(body['phone'], '13800138000');
              return http.Response(
                jsonEncode({
                  'challenge_id': 'sms1',
                  'retry_after': 90,
                  'demoCode': '123456',
                }),
                200,
              );
            case '/v1/auth/sms/verify':
              expect(body['challenge_id'], 'sms1');
              return http.Response(
                jsonEncode({
                  'user_id': '42',
                  'nickname': 'User',
                  'access_token': 'test-token',
                }),
                200,
              );
            case '/v1/auth/wechat/start':
              return http.Response(
                jsonEncode({
                  'challenge_id': 'wx1',
                  'authorization_url':
                      'https://login.example.com/wechat/authorize',
                }),
                200,
              );
            default:
              return http.Response('{"status":"pending"}', 200);
          }
        }),
      );
      final sms = await gateway.sendSms('13800138000');
      expect(sms.demoCode, isNull);
      expect(sms.retryAfter, 90);
      expect(
        (await gateway.verifySms('13800138000', '123456', sms.id)).accessToken,
        'test-token',
      );
      final wx = await gateway.startWechat();
      expect(await gateway.checkWechat(wx, demoApproved: true), isNull);
      expect(calls.length, 4);
    },
  );
  test(
    'HTTP rejects invalid HTTPS, foreign authorization URLs and service failures',
    () async {
      expect(() => HttpAuthGateway('http://example.com'), throwsArgumentError);
      final foreign = HttpAuthGateway(
        'https://login.example.com',
        client: MockClient(
          (_) async => http.Response(
            '{"challenge_id":"wx1","authorization_url":"https://other.example.com"}',
            200,
          ),
        ),
      );
      await expectLater(foreign.startWechat(), throwsStateError);
      for (final status in [401, 429, 500]) {
        final gateway = HttpAuthGateway(
          'https://login.example.com',
          client: MockClient((_) async => http.Response('{}', status)),
        );
        await expectLater(gateway.sendSms('13800138000'), throwsStateError);
      }
    },
  );
  test('Remote token is memory-only and clears on logout', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = HttpAuthGateway(
      'https://login.example.com',
      client: MockClient(
        (_) async => http.Response(
          '{"user_id":"remote-1","nickname":"User","access_token":"private-token"}',
          200,
        ),
      ),
    );
    final state = AppState(prefs, authGateway: gateway);
    await state.initialize();
    await state.loginPhone(
      '13800138000',
      '123456',
      'server-challenge',
      consent: true,
    );
    expect(state.accessToken, 'private-token');
    for (final key in prefs.getKeys()) {
      expect(prefs.get(key).toString(), isNot(contains('private-token')));
    }
    expect(state.contacts, isEmpty);
    state.logout();
    expect(state.accessToken, isNull);
  });
}
