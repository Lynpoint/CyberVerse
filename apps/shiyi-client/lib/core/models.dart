import 'dart:convert';
import 'dart:typed_data';

class DigitalHuman {
  final String id, name, description, personality, greeting, group;
  final String? photo, voicePath, voiceName;
  final int color;
  final DateTime createdAt;
  final bool sample;
  const DigitalHuman({
    required this.id,
    required this.name,
    required this.description,
    required this.personality,
    required this.greeting,
    required this.group,
    required this.color,
    required this.createdAt,
    this.photo,
    this.voicePath,
    this.voiceName,
    this.sample = false,
  });
  Uint8List? get photoBytes => photo == null ? null : base64Decode(photo!);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'personality': personality,
    'greeting': greeting,
    'group': group,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'photo': photo,
    'voicePath': voicePath,
    'voiceName': voiceName,
    'sample': sample,
  };
  factory DigitalHuman.fromJson(Map<String, dynamic> j) => DigitalHuman(
    id: j['id'],
    name: j['name'],
    description: j['description'],
    personality: j['personality'],
    greeting: j['greeting'],
    group: j['group'],
    color: j['color'],
    createdAt: DateTime.parse(j['createdAt']),
    photo: j['photo'],
    voicePath: j['voicePath'],
    voiceName: j['voiceName'],
    sample: j['sample'] ?? false,
  );
}

class ChatMessage {
  final String text;
  final bool mine;
  final DateTime time;
  ChatMessage(this.text, this.mine, {DateTime? time})
    : time = time ?? DateTime.now();
  Map<String, dynamic> toJson() => {
    'text': text,
    'mine': mine,
    'time': time.toIso8601String(),
  };
  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(j['text'], j['mine'], time: DateTime.parse(j['time']));
}
