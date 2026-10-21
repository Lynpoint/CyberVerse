import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> saveVoice(String id, String extension, Uint8List bytes) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'voice_$id';
  if (!await prefs.setString(key, base64Encode(bytes))) {
    throw StateError('浏览器存储空间不足，请更换较小的音频');
  }
  return key;
}

Future<void> removeVoice(String? path) async {
  if (path != null) await (await SharedPreferences.getInstance()).remove(path);
}
