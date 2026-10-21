import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cyberverse_api.dart';
import 'models.dart';

DigitalHuman voiceAssistant() => DigitalHuman(
  id: 'shiyi_voice_assistant',
  name: '时忆语音助手',
  description: 'AI语音伙伴',
  personality: '温暖、自然、简洁地陪伴用户聊天。',
  greeting: '你好，我是时忆的AI语音助手。今天过得怎么样？',
  group: 'AI',
  color: 0xFF215C4C,
  createdAt: DateTime(2026, 10, 20),
);

class VoiceCharacterRepository {
  final SharedPreferences prefs;
  final CyberVerseApi api;
  final String account;
  final bool avatar;
  VoiceCharacterRepository(
    this.prefs,
    this.api,
    this.account, {
    this.avatar = false,
  });

  Future<String> resolve(DigitalHuman human) async {
    if (avatar && (human.photoBytes == null || human.photoBytes!.isEmpty)) {
      throw StateError('请先选择已获授权的人像照片');
    }
    final encoded = base64UrlEncode(
      utf8.encode('$account|${api.baseUrl}|${human.id}'),
    );
    final key = '${avatar ? 'avatar' : 'voice'}_character_v1_$encoded';
    final raw = prefs.getString(key);
    final link = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw));
    final existingId = link['id'] as String?;
    if (existingId != null) {
      var found = true;
      try {
        await api.getCharacter(existingId);
      } on CyberVerseHttpException catch (error) {
        if (error.statusCode != 404) rethrow;
        found = false;
      }
      if (found) {
        if (avatar) await _uploadPhoto(human, existingId, key);
        return existingId;
      }
    }
    final token =
        link['token'] as String? ??
        base64UrlEncode(
          List<int>.generate(18, (_) => Random.secure().nextInt(256)),
        );
    final tag = 'shiyi-client-$token';
    if (!await prefs.setString(key, jsonEncode({'token': token}))) {
      throw StateError('本地保存失败，存储空间可能不足');
    }
    // Persist the opaque tag before POST so a timed-out create can be found
    // on retry instead of duplicating a remote character. No username is sent.
    final characters = (await api.listCharacters() as List).whereType<Map>();
    Map? match;
    for (final item in characters) {
      if ((item['tags'] as List? ?? []).contains(tag)) {
        match = item;
        break;
      }
    }
    if (!avatar && match == null && human.id == 'shiyi_voice_assistant') {
      for (final item in characters) {
        if (item['name'] == human.name &&
            item['voice_provider'] == 'qwen_omni') {
          match = item;
          break;
        }
      }
    }
    match ??= Map<String, dynamic>.from(
      await api.createCharacter({
        'name': human.name,
        'description': human.description,
        'personality': human.personality,
        'welcome_message': human.greeting,
        'system_prompt':
            '你是名为“${human.name}”的AI数字伙伴，不是真人，也不是任何真实人物本人。'
            '自然、简短地回答，绝不声称已克隆真人声音。背景设定：${human.personality}',
        'avatar_backend': 'local_image',
        'mode': 'omni',
        'voice_provider': 'qwen_omni',
        'voice_type': 'Tina',
        'components': {'llm': 'qwen', 'asr': 'qwen', 'tts': 'qwen'},
        'tags': [tag, 'AI-generated'],
      }),
    );
    final id = match['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Missing character id');
    }
    if (!await prefs.setString(key, jsonEncode({'token': token, 'id': id}))) {
      throw StateError('本地保存失败，存储空间可能不足');
    }
    if (avatar) await _uploadPhoto(human, id, key);
    return id;
  }

  Future<void> _uploadPhoto(DigitalHuman human, String id, String key) async {
    final bytes = human.photoBytes!;
    final fingerprint = sha256.convert(bytes).toString();
    final link = Map<String, dynamic>.from(jsonDecode(prefs.getString(key)!));
    if (link['photo_sha256'] == fingerprint) return;
    await api.uploadAvatar(id, bytes, 'portrait.png');
    link['photo_sha256'] = fingerprint;
    if (!await prefs.setString(key, jsonEncode(link))) {
      throw StateError('本地保存失败，存储空间可能不足');
    }
  }
}
