import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cyberverse_app/core/life_store.dart';
import 'package:cyberverse_app/core/language.dart';

LifePost post({
  String id = 'mine',
  String author = 'a',
  String body = 'A real memory',
  List<String> photos = const [],
  bool aiGenerated = false,
}) => LifePost(
  id: id,
  authorId: author,
  author: 'Jamie',
  title: 'Today',
  body: body,
  photos: photos,
  aiGenerated: aiGenerated,
  createdAt: DateTime(2026, 10, 19),
);
void main() {
  late SharedPreferences prefs;
  late LifeStore store;
  setUp(() async {
    AppLanguage.code = 'zh';
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = LifeStore(prefs)..load('a');
  });
  test('posts, interactions, draft and history survive reload', () async {
    await store.publish(post());
    await store.toggleLike('mine');
    await store.toggleBookmark('mine');
    await store.toggleFollow('sample_su');
    await store.view('mine');
    await store.comment('mine', 'Jamie', 'Remember this');
    await store.saveDraft({
      'title': 'Tomorrow',
      'body': 'Unfinished',
      'photos': [],
    });
    final loaded = LifeStore(prefs)..load('a');
    expect(loaded.find('mine')!.body, 'A real memory');
    expect(loaded.likes, contains('mine'));
    expect(loaded.bookmarks, contains('mine'));
    expect(loaded.following, contains('sample_su'));
    expect(loaded.history, ['mine']);
    expect(loaded.comments['mine']!.single.body, 'Remember this');
    expect(loaded.draft!['title'], 'Tomorrow');
  });
  test(
    'accounts isolate records and deleting removes associated data',
    () async {
      await store.publish(post());
      await store.saveDraft({'title': 'Private'});
      store.load('b');
      expect(store.find('mine'), isNull);
      expect(store.draft, isNull);
      await expectLater(store.publish(post()), throwsStateError);
      store.load('a');
      expect(store.find('mine'), isNotNull);
      await store.deleteAccount();
      store.load('a');
      expect(store.find('mine'), isNull);
    },
  );
  test('post removal clears likes, bookmarks, comments and history', () async {
    await store.publish(post());
    await store.toggleLike('mine');
    await store.toggleBookmark('mine');
    await store.view('mine');
    await store.comment('mine', 'Jamie', 'Comment');
    await store.deletePost(store.find('mine')!);
    expect(store.likes, isEmpty);
    expect(store.bookmarks, isEmpty);
    expect(store.comments, isEmpty);
    expect(store.history, isEmpty);
    await expectLater(
      store.deletePost(LifeStore.samples.first),
      throwsStateError,
    );
  });
  test(
    'invalid and oversized writes roll back instead of losing records',
    () async {
      await store.publish(post());
      await expectLater(
        store.publish(post(id: 'bad', body: '')),
        throwsStateError,
      );
      await expectLater(
        store.publish(post(id: 'large', photos: ['a' * (5 * 1024 * 1024)])),
        throwsStateError,
      );
      expect(store.find('large'), isNull);
      expect(store.find('mine'), isNotNull);
      expect(store.saving, isFalse);
      expect((LifeStore(prefs)..load('a')).find('mine'), isNotNull);
    },
  );
  test('history is unique, latest-first, and likes toggle', () async {
    await store.view('life_lin');
    await store.view('life_su');
    await store.view('life_lin');
    expect(store.history, ['life_lin', 'life_su']);
    await store.toggleLike('life_lin');
    await store.toggleLike('life_lin');
    expect(store.likes, isEmpty);
    await store.clearHistory();
    expect(store.history, isEmpty);
  });
  test(
    'AI disclosure persists and older user posts default to unlabelled',
    () async {
      await store.publish(post(aiGenerated: true));
      expect((LifeStore(prefs)..load('a')).find('mine')!.aiGenerated, isTrue);
      await store.publish(post(aiGenerated: false));
      expect((LifeStore(prefs)..load('a')).find('mine')!.aiGenerated, isFalse);
      final legacy = post().toJson()..remove('aiGenerated');
      expect(LifePost.fromJson(legacy).aiGenerated, isFalse);
      expect(LifeStore.samples.every((p) => p.aiGenerated), isTrue);
    },
  );
}
