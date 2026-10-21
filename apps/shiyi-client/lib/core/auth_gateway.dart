import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class SmsChallenge {
  final String id;
  final int retryAfter;
  final String? demoCode;
  const SmsChallenge(this.id, {this.retryAfter = 60, this.demoCode});
}

class AuthIdentity {
  final String id, nickname;
  final String? accessToken;
  const AuthIdentity(this.id, this.nickname, {this.accessToken});
}

class WechatChallenge {
  final String id;
  final Uri? authorizationUrl;
  const WechatChallenge(this.id, {this.authorizationUrl});
}

abstract class AuthGateway {
  bool get isDemo;
  Future<SmsChallenge> sendSms(String phone);
  Future<AuthIdentity> verifySms(String phone, String code, String challengeId);
  Future<WechatChallenge> startWechat();
  Future<AuthIdentity?> checkWechat(
    WechatChallenge challenge, {
    bool demoApproved = false,
  });
  Future<void> cancelWechat(WechatChallenge challenge);
}

/// A local simulation. Codes are never sent to a telecom provider.
class DemoAuthGateway implements AuthGateway {
  final DateTime Function() now;
  DemoAuthGateway({DateTime Function()? clock}) : now = clock ?? DateTime.now;
  final _sms =
      <String, ({String phone, String code, DateTime sent, int attempts})>{};
  final _wechat = <String, DateTime>{};
  final _lastSent = <String, DateTime>{};
  final _random = Random.secure();
  @override
  bool get isDemo => true;
  String _id() =>
      List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();
  @override
  Future<SmsChallenge> sendSms(String phone) async {
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      throw StateError('请输入正确的 11 位手机号');
    }
    final last = _lastSent[phone];
    if (last != null && now().difference(last).inSeconds < 60) {
      throw StateError('请稍后再获取验证码');
    }
    _sms.removeWhere(
      (_, v) => v.phone == phone || now().difference(v.sent).inMinutes >= 5,
    );
    final id = _id();
    final code = (100000 + _random.nextInt(900000)).toString();
    _sms[id] = (phone: phone, code: code, sent: now(), attempts: 0);
    _lastSent[phone] = now();
    return SmsChallenge(id, demoCode: code);
  }

  @override
  Future<AuthIdentity> verifySms(
    String phone,
    String code,
    String challengeId,
  ) async {
    final value = _sms[challengeId];
    if (value == null) throw StateError('请重新获取验证码');
    if (now().difference(value.sent).inMinutes >= 5) {
      _sms.remove(challengeId);
      throw StateError('验证码已过期，请重新获取');
    }
    if (value.phone != phone || value.code != code) {
      final attempts = value.attempts + 1;
      if (attempts >= 5) {
        _sms.remove(challengeId);
      } else {
        _sms[challengeId] = (
          phone: value.phone,
          code: value.code,
          sent: value.sent,
          attempts: attempts,
        );
      }
      throw StateError(attempts >= 5 ? '错误次数过多，请重新获取验证码' : '手机号或验证码不正确');
    }
    _sms.remove(challengeId);
    return AuthIdentity('phone:$phone', '时忆用户${phone.substring(7)}');
  }

  @override
  Future<WechatChallenge> startWechat() async {
    final id = _id();
    _wechat.removeWhere((_, value) => now().difference(value).inMinutes >= 3);
    _wechat[id] = now();
    return WechatChallenge(id);
  }

  @override
  Future<AuthIdentity?> checkWechat(
    WechatChallenge challenge, {
    bool demoApproved = false,
  }) async {
    final created = _wechat[challenge.id];
    if (created == null || now().difference(created).inMinutes >= 3) {
      _wechat.remove(challenge.id);
      throw StateError('授权已失效，请重试');
    }
    if (!demoApproved) return null;
    _wechat.remove(challenge.id);
    return const AuthIdentity('wechat:demo', '微信体验用户');
  }

  @override
  Future<void> cancelWechat(WechatChallenge challenge) async =>
      _wechat.remove(challenge.id);
}

/// Proposed business-service contract; these are NOT upstream CyberVerse APIs.
/// The server owns SMS validation, OAuth state, credentials and token exchange.
class HttpAuthGateway implements AuthGateway {
  final Uri baseUrl;
  final http.Client client;
  HttpAuthGateway(String url, {http.Client? client})
    : baseUrl = Uri.parse(url),
      client = client ?? http.Client() {
    if (baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw ArgumentError('登录服务必须使用不含凭据、查询或片段的 HTTPS 地址');
    }
  }
  @override
  bool get isDemo => false;
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse(
      '${baseUrl.toString().replaceFirst(RegExp(r'/+$'), '')}/v1/auth/$path',
    );
    try {
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 429) throw StateError('操作太频繁，请稍后重试');
      if (response.statusCode == 400 || response.statusCode == 401) {
        throw StateError('验证失败或已过期，请重试');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('登录服务暂时不可用');
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on TimeoutException {
      throw StateError('连接超时，请检查网络后重试');
    } on http.ClientException {
      throw StateError('无法连接登录服务，请检查网络');
    } on FormatException {
      throw StateError('登录服务返回格式有误');
    }
  }

  String _required(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) throw StateError('登录服务缺少必要字段');
    return value;
  }

  AuthIdentity _identity(Map<String, dynamic> json) => AuthIdentity(
    _required(json, 'user_id'),
    _required(json, 'nickname'),
    accessToken: _required(json, 'access_token'),
  );
  @override
  Future<SmsChallenge> sendSms(String phone) async {
    final json = await _post('sms/send', {'phone': phone, 'purpose': 'login'});
    final retry = json['retry_after'];
    return SmsChallenge(
      _required(json, 'challenge_id'),
      retryAfter: retry is int ? retry.clamp(1, 300) : 60,
    );
  }

  @override
  Future<AuthIdentity> verifySms(
    String phone,
    String code,
    String challengeId,
  ) async => _identity(
    await _post('sms/verify', {
      'phone': phone,
      'code': code,
      'challenge_id': challengeId,
    }),
  );
  @override
  Future<WechatChallenge> startWechat() async {
    final json = await _post('wechat/start', {});
    final uri = Uri.parse(_required(json, 'authorization_url'));
    // Only a page hosted by the configured business service may be opened.
    // That page performs the WeChat redirect / QR code flow server-side.
    if (uri.scheme != 'https' ||
        uri.origin != baseUrl.origin ||
        uri.userInfo.isNotEmpty) {
      throw StateError('微信授权地址不属于已配置的登录服务');
    }
    return WechatChallenge(
      _required(json, 'challenge_id'),
      authorizationUrl: uri,
    );
  }

  @override
  Future<AuthIdentity?> checkWechat(
    WechatChallenge challenge, {
    bool demoApproved = false,
  }) async {
    final json = await _post('wechat/status', {'challenge_id': challenge.id});
    switch (json['status']) {
      case 'pending':
        return null;
      case 'approved':
        return _identity(json);
      case 'cancelled':
        throw StateError('微信授权已取消');
      case 'expired':
        throw StateError('微信授权已过期，请重试');
      default:
        throw StateError('微信授权状态异常');
    }
  }

  @override
  Future<void> cancelWechat(WechatChallenge challenge) async {
    await _post('wechat/cancel', {'challenge_id': challenge.id});
  }
}
