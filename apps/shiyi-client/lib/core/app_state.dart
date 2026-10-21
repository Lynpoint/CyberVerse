import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'media_store.dart';
import 'models.dart';
import 'auth_gateway.dart';
import 'language.dart';
import 'life_store.dart';
import 'backend_defaults.dart';

class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  final AuthGateway authGateway;
  AppState(this.prefs, {AuthGateway? authGateway})
    : authGateway = authGateway ?? _configuredAuth();
  static AuthGateway _configuredAuth() {
    const url = String.fromEnvironment('SHIYI_AUTH_BASE_URL');
    return url.isEmpty ? DemoAuthGateway() : HttpAuthGateway(url);
  }

  String? accessToken;
  late final LifeStore life = LifeStore(prefs);
  String get language => AppLanguage.code;
  Future<void> toggleLanguage() async {
    final next = language == 'zh' ? 'en' : 'zh';
    if (!await prefs.setString('language_v1', next)) {
      throw StateError('语言设置保存失败，请重试');
    }
    AppLanguage.code = next;
    notifyListeners();
  }

  bool get canChangePassword => _accounts[username]?['hash'] != null;
  String get accountLabel => _accounts[username]?['provider'] ?? '本地账号';
  static String? phoneError(String value) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(value.trim()) ? null : '请输入正确的 11 位手机号';
  void _requireConsent(bool consent) {
    if (!consent) throw StateError('请先阅读并同意用户协议与隐私政策');
  }

  Future<SmsChallenge> requestSms(String phone, {required bool consent}) async {
    _requireConsent(consent);
    final error = phoneError(phone);
    if (error != null) throw StateError(error);
    return authGateway.sendSms(phone.trim());
  }

  Future<void> loginPhone(
    String phone,
    String code,
    String challengeId, {
    required bool consent,
  }) async {
    _requireConsent(consent);
    final error = phoneError(phone);
    if (error != null) throw StateError(error);
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw StateError('请输入 6 位验证码');
    }
    final identity = await authGateway.verifySms(
      phone.trim(),
      code.trim(),
      challengeId,
    );
    await _acceptIdentity(identity, '手机号登录');
  }

  Future<WechatChallenge> beginWechat({required bool consent}) async {
    _requireConsent(consent);
    return authGateway.startWechat();
  }

  Future<bool> finishWechat(
    WechatChallenge challenge, {
    required bool consent,
    bool demoApproved = false,
  }) async {
    _requireConsent(consent);
    final identity = await authGateway.checkWechat(
      challenge,
      demoApproved: demoApproved,
    );
    if (identity == null) return false;
    await _acceptIdentity(identity, '微信登录');
    return true;
  }

  Future<void> _acceptIdentity(AuthIdentity identity, String provider) async {
    // Demo and server identities cannot collide with password accounts.
    final key =
        '${authGateway.isDemo ? 'demo-auth' : 'remote-auth'}:${base64UrlEncode(utf8.encode(identity.id))}';
    if (!_accounts.containsKey(key)) {
      _accounts[key] = {
        'nickname': identity.nickname,
        'provider': provider,
        'consentVersion': 'demo-2026-10-18',
        'consentAt': DateTime.now().toIso8601String(),
      };
      await _saveAccounts();
    }
    if (prefs.getString('profile_$key') == null) {
      await prefs.setString(
        'profile_$key',
        jsonEncode({
          'nickname': identity.nickname,
          'contacts': authGateway.isDemo
              ? _samples().map((c) => c.toJson()).toList()
              : [],
        }),
      );
    }
    accessToken = identity.accessToken; // Memory only; never SharedPreferences.
    _loadProfile(key, _accounts[key]);
  }

  final Map<String, dynamic> _accounts = {};
  String? username;
  String nickname = '';
  String bio = '';
  String backendUrl = defaultBackendUrl();
  String avatarBackendUrl = defaultAvatarBackendUrl();
  String appearance = 'sky';
  bool notifications = true;
  List<DigitalHuman> contacts = [];
  Map<String, List<ChatMessage>> conversations = {};
  bool get loggedIn => username != null;
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  Future<void> initialize() async {
    AppLanguage.code = prefs.getString('language_v1') == 'en' ? 'en' : 'zh';
    final raw = prefs.getString('accounts_v1');
    if (raw != null) _accounts.addAll(jsonDecode(raw) as Map<String, dynamic>);
    if (!_accounts.containsKey('demo')) {
      _accounts['demo'] = await _credential('Demo12345', '体验用户');
      await _saveAccounts();
      await prefs.setString(
        'profile_demo',
        jsonEncode({
          'nickname': '体验用户',
          'bio': '让每一次相遇，都跨越想象。',
          'contacts': _samples().map((c) => c.toJson()).toList(),
          'conversations': {},
        }),
      );
    }
  }

  static String? usernameError(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value.trim())) {
      return '用户名需为 3–20 位字母、数字或下划线';
    }
    return null;
  }

  static String? passwordError(String value) {
    if (value.length < 8 || value.length > 64) return '密码需为 8–64 位';
    if (!RegExp(r'[a-zA-Z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return '密码需同时包含字母和数字';
    }
    return null;
  }

  Future<String> _hash(String password, String salt) async => base64Encode(
    await (await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Decode(salt),
    )).extractBytes(),
  );
  Future<Map<String, dynamic>> _credential(String password, String name) async {
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    return {
      'salt': salt,
      'hash': await _hash(password, salt),
      'nickname': name,
      'consentVersion': 'demo-2026-10-18',
      'consentAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveAccounts() async {
    if (!await prefs.setString('accounts_v1', jsonEncode(_accounts))) {
      throw StateError('保存失败，请检查设备存储空间');
    }
  }

  Future<void> register(
    String user,
    String password,
    String name, {
    required bool consent,
  }) async {
    if (!consent) throw StateError('请先阅读并同意用户协议与隐私政策');
    final key = user.trim().toLowerCase();
    final error = usernameError(key) ?? passwordError(password);
    if (error != null) throw StateError(error);
    if (_accounts.containsKey(key)) throw StateError('该用户名已注册');
    _accounts[key] = await _credential(
      password,
      name.trim().isEmpty ? user.trim() : name.trim(),
    );
    await _saveAccounts();
    await login(user, password, consent: consent);
  }

  Future<void> login(
    String user,
    String password, {
    required bool consent,
  }) async {
    if (!consent) throw StateError('请先阅读并同意用户协议与隐私政策');
    final key = user.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null ||
        account['hash'] == null ||
        await _hash(password, account['salt']) != account['hash']) {
      throw StateError('用户名或密码不正确');
    }
    accessToken = null;
    _loadProfile(key, account);
  }

  void _loadProfile(String key, Map<String, dynamic> account) {
    username = key;
    life.load(key);
    final raw = prefs.getString('profile_$key');
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    nickname = data['nickname'] ?? account['nickname'];
    bio = data['bio'] ?? '很高兴在时忆与你相遇。';
    backendUrl = data['backendUrl'] ?? defaultBackendUrl();
    avatarBackendUrl = data['avatarBackendUrl'] ?? defaultAvatarBackendUrl();
    appearance = data['appearance'] ?? 'sky';
    notifications = data['notifications'] ?? true;
    contacts = (data['contacts'] as List? ?? [])
        .map((v) => DigitalHuman.fromJson(v))
        .toList();
    conversations = (data['conversations'] as Map<String, dynamic>? ?? {}).map(
      (k, v) =>
          MapEntry(k, (v as List).map((m) => ChatMessage.fromJson(m)).toList()),
    );
    notifyListeners();
  }

  Future<void> persist() async {
    if (username == null) return;
    final json = jsonEncode({
      'nickname': nickname,
      'bio': bio,
      'backendUrl': backendUrl,
      'avatarBackendUrl': avatarBackendUrl,
      'appearance': appearance,
      'notifications': notifications,
      'contacts': contacts.map((c) => c.toJson()).toList(),
      'conversations': conversations.map(
        (k, v) => MapEntry(k, v.map((m) => m.toJson()).toList()),
      ),
    });
    if (!await prefs.setString('profile_$username', json)) {
      throw StateError('本地保存失败，存储空间可能不足');
    }
    notifyListeners();
  }

  Future<void> changePassword(String old, String next) async {
    if (!canChangePassword) throw StateError('当前登录方式无需本地密码');
    final account = _accounts[username];
    if (await _hash(old, account['salt']) != account['hash']) {
      throw StateError('原密码不正确');
    }
    final error = passwordError(next);
    if (error != null) throw StateError(error);
    _accounts[username!] = await _credential(next, nickname);
    await _saveAccounts();
  }

  Future<void> addContact(DigitalHuman contact) async {
    contacts.add(contact);
    try {
      await persist();
    } catch (_) {
      contacts.remove(contact);
      rethrow;
    }
  }

  Future<void> deleteContact(DigitalHuman contact) async {
    contacts.removeWhere((c) => c.id == contact.id);
    conversations.remove(contact.id);
    await persist();
    await removeVoice(contact.voicePath);
  }

  Future<void> addMessage(String contactId, ChatMessage message) async {
    conversations.putIfAbsent(contactId, () => []).add(message);
    await persist();
  }

  Future<void> clearMessages() async {
    conversations.clear();
    await persist();
  }

  Future<void> setAppearance(String value) async {
    appearance = value;
    await persist();
  }

  void logout() {
    life.clearSession();
    accessToken = null;
    username = null;
    contacts = [];
    conversations = {};
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await life.deleteAccount();
    for (final contact in contacts) {
      await removeVoice(contact.voicePath);
    }
    await prefs.remove('profile_$username');
    _accounts.remove(username);
    await _saveAccounts();
    logout();
  }

  List<DigitalHuman> _samples() => [
    DigitalHuman(
      id: 'sample_lin',
      name: '林屿',
      description: '生活搭子 · 一起发现日常的小美好',
      personality: '温暖、耐心，喜欢旅行与摄影',
      greeting: '嗨，我是林屿。今天有什么想分享的吗？',
      group: 'L',
      color: 0xFFE1F0FF,
      createdAt: DateTime(2026, 10, 16),
      sample: true,
    ),
    DigitalHuman(
      id: 'sample_su',
      name: '苏晚',
      description: '灵感伙伴 · 陪你把想法变成可能',
      personality: '有创造力、开朗，擅长倾听',
      greeting: '你好呀，我是苏晚。我们一起聊点有趣的事吧！',
      group: 'S',
      color: 0xFFF0E8FF,
      createdAt: DateTime(2026, 10, 15),
      sample: true,
    ),
    DigitalHuman(
      id: 'sample_xia',
      name: '小夏',
      description: '学习助手 · 好奇心永远在线',
      personality: '认真、幽默，喜欢分享知识',
      greeting: '我是小夏，今天想一起探索什么？',
      group: 'X',
      color: 0xFFE1F8FA,
      createdAt: DateTime(2026, 10, 14),
      sample: true,
    ),
  ];
}
