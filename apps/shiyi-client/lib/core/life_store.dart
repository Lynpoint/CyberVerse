import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language.dart';

class LifePost {
  final String id, authorId, author, title, body, topic, location;
  final DateTime createdAt;
  final List<String> photos;
  final int portrait;
  final bool sample, aiGenerated;
  const LifePost({
    required this.id,
    required this.authorId,
    required this.author,
    required this.title,
    required this.body,
    required this.createdAt,
    this.photos = const [],
    this.topic = '',
    this.location = '',
    this.portrait = 0,
    this.sample = false,
    this.aiGenerated = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'author': author,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'photos': photos,
    'topic': topic,
    'location': location,
    'portrait': portrait,
    'aiGenerated': aiGenerated,
  };
  factory LifePost.fromJson(Map<String, dynamic> v) => LifePost(
    id: v['id'],
    authorId: v['authorId'],
    author: v['author'],
    title: v['title'],
    body: v['body'],
    createdAt: DateTime.parse(v['createdAt']),
    photos: List<String>.from(v['photos'] ?? []),
    topic: v['topic'] ?? '',
    location: v['location'] ?? '',
    portrait: v['portrait'] ?? 0,
    aiGenerated: v['aiGenerated'] == true,
  );
}

class LifeComment {
  final String author, body;
  final DateTime date;
  const LifeComment(this.author, this.body, this.date);
  Map<String, dynamic> toJson() => {
    'author': author,
    'body': body,
    'date': date.toIso8601String(),
  };
  factory LifeComment.fromJson(Map<String, dynamic> v) =>
      LifeComment(v['author'], v['body'], DateTime.parse(v['date']));
}

class LifeStore extends ChangeNotifier {
  final SharedPreferences prefs;
  LifeStore(this.prefs);
  String? _account;
  bool saving = false;
  List<LifePost> _posts = [];
  Set<String> likes = {}, bookmarks = {}, following = {};
  List<String> history = [];
  Map<String, List<LifeComment>> comments = {};
  Map<String, dynamic>? draft;
  List<LifePost> get posts => [..._posts, ...samples];
  String? get account => _account;
  bool owns(LifePost post) => !post.sample && post.authorId == _account;
  LifePost? find(String id) {
    for (final p in posts) {
      if (p.id == id) return p;
    }
    return null;
  }

  void load(String account) {
    _account = account;
    final raw = prefs.getString('life_v1_$account');
    _restore(raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>);
    notifyListeners();
  }

  void clearSession() {
    _account = null;
    _restore({});
    notifyListeners();
  }

  void _restore(Map<String, dynamic> v) {
    _posts = (v['posts'] as List? ?? [])
        .map((p) => LifePost.fromJson(p))
        .toList();
    likes = Set<String>.from(v['likes'] ?? []);
    bookmarks = Set<String>.from(v['bookmarks'] ?? []);
    following = Set<String>.from(v['following'] ?? []);
    history = List<String>.from(v['history'] ?? []);
    comments = (v['comments'] as Map<String, dynamic>? ?? {}).map(
      (k, c) =>
          MapEntry(k, (c as List).map((e) => LifeComment.fromJson(e)).toList()),
    );
    draft = v['draft'] == null ? null : Map<String, dynamic>.from(v['draft']);
  }

  Map<String, dynamic> _snapshot() => {
    'posts': _posts.map((p) => p.toJson()).toList(),
    'likes': likes.toList(),
    'bookmarks': bookmarks.toList(),
    'following': following.toList(),
    'history': List<String>.from(history),
    'comments': comments.map(
      (k, c) => MapEntry(k, c.map((e) => e.toJson()).toList()),
    ),
    'draft': draft == null ? null : Map<String, dynamic>.from(draft!),
  };
  Future<void> _change(VoidCallback change) async {
    final account = _account;
    if (account == null) throw StateError(tr('请先登录'));
    if (saving) throw StateError(tr('正在保存，请稍候'));
    final before = _snapshot();
    saving = true;
    try {
      change();
      final data = jsonEncode(_snapshot());
      if (utf8.encode(data).length > 4 * 1024 * 1024) {
        throw StateError(tr('本地空间不足，请减少图片或删除旧记录'));
      }
      if (!await prefs.setString('life_v1_$account', data)) {
        throw StateError(tr('保存失败，请检查设备存储空间'));
      }
    } catch (_) {
      if (_account == account) _restore(before);
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> publish(LifePost post) => _change(() {
    if (post.authorId != _account || post.sample) {
      throw StateError(tr('无法修改其他人的记录'));
    }
    if (post.title.trim().isEmpty ||
        (post.body.trim().isEmpty && post.photos.isEmpty)) {
      throw StateError(tr('请填写标题，并添加正文或照片'));
    }
    if (post.title.length > 60 ||
        post.body.length > 2000 ||
        post.photos.length > 6) {
      throw StateError(tr('内容超出长度或图片数量限制'));
    }
    final existing = _posts.indexWhere((p) => p.id == post.id);
    if (existing < 0) {
      _posts.insert(0, post);
      draft = null;
    } else {
      _posts[existing] = post;
    }
  });
  Future<void> deletePost(LifePost post) => _change(() {
    if (!owns(post)) throw StateError(tr('无法修改其他人的记录'));
    _posts.removeWhere((p) => p.id == post.id);
    likes.remove(post.id);
    bookmarks.remove(post.id);
    history.remove(post.id);
    comments.remove(post.id);
  });
  Future<void> toggleLike(String id) => _change(() {
    if (!likes.remove(id)) likes.add(id);
  });
  Future<void> toggleBookmark(String id) => _change(() {
    if (!bookmarks.remove(id)) bookmarks.add(id);
  });
  Future<void> toggleFollow(String id) => _change(() {
    if (!following.remove(id)) following.add(id);
  });
  Future<void> view(String id) => _change(() {
    history.remove(id);
    history.insert(0, id);
    if (history.length > 100) history.removeLast();
  });
  Future<void> comment(String id, String author, String text) => _change(() {
    if (text.trim().isEmpty || text.length > 500) {
      throw StateError(tr('评论需为 1–500 字'));
    }
    comments
        .putIfAbsent(id, () => [])
        .add(LifeComment(author, text.trim(), DateTime.now()));
  });
  Future<void> saveDraft(Map<String, dynamic>? value) =>
      _change(() => draft = value);
  Future<void> clearHistory() => _change(history.clear);
  Future<void> deleteAccount() async {
    if (_account != null && !await prefs.remove('life_v1_$_account')) {
      throw StateError(tr('删除失败，请重试'));
    }
    clearSession();
  }

  static final samples = <LifePost>[
    LifePost(
      id: 'life_lin',
      aiGenerated: true,
      authorId: 'sample_lin',
      author: '林屿',
      title: '把普通的一天，认真收藏',
      body: '下午放下手机，和朋友走了很长一段路。没有目的地，也没有赶时间。原来值得记住的，往往就是这些普通的瞬间。',
      topic: '日常',
      location: '街角',
      photos: ['asset:assets/portraits/lin.jpg'],
      createdAt: DateTime(2026, 10, 17, 16, 30),
      sample: true,
    ),
    LifePost(
      id: 'life_su',
      aiGenerated: true,
      authorId: 'sample_su',
      author: '苏晚',
      title: '今天的灵感，是慢一点',
      body: '读完了一章书，写下三句话，给自己泡了一杯茶。不用每一天都很精彩，能感受到生活，就已经很好。',
      topic: '灵感',
      location: '家',
      portrait: 1,
      photos: ['asset:assets/portraits/su.jpg'],
      createdAt: DateTime(2026, 10, 17, 10),
      sample: true,
    ),
    LifePost(
      id: 'life_xia',
      aiGenerated: true,
      authorId: 'sample_xia',
      author: '小夏',
      title: '想留给未来自己的话',
      body: '记得今天的好奇心，也记得一路上遇到的善意。等以后回头看，希望这些小小的记录，能把此刻的心情带回来。',
      topic: '心情',
      portrait: 2,
      photos: ['asset:assets/portraits/xia.jpg'],
      createdAt: DateTime(2026, 10, 16, 18),
      sample: true,
    ),
    LifePost(
      id: 'life_note',
      aiGenerated: true,
      authorId: 'sample_su',
      author: '苏晚',
      title: '一些不需要照片的瞬间',
      body: '晚风、朋友的笑声，还有一句突然收到的问候。今天就用文字把它们留下。',
      topic: '日常',
      portrait: 1,
      createdAt: DateTime(2026, 10, 16, 12),
      sample: true,
    ),
  ];
}
