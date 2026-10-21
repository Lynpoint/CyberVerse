import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/language.dart';
import '../core/life_store.dart';
import '../core/ui.dart';

String postCopy(LifePost p, String text) => p.sample ? tr(text) : text;
String postDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
Future<void> lifeAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
  }
}

class PostPhoto extends StatelessWidget {
  final String source;
  final BoxFit fit;
  const PostPhoto(this.source, {this.fit = BoxFit.cover, super.key});
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext _, Object error, StackTrace? stack) =>
        const Center(child: Icon(Icons.broken_image_outlined, color: muted));
    try {
      return source.startsWith('asset:')
          ? Image.asset(
              source.substring(6),
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: fallback,
            )
          : Image.memory(
              base64Decode(source),
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: fallback,
            );
    } catch (_) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
  }
}

class DiscoverScreen extends StatefulWidget {
  final AppState state;
  const DiscoverScreen({required this.state, super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  int tab = 0;
  String topic = '', query = '';
  bool searching = false;
  final search = TextEditingController();
  LifeStore get store => widget.state.life;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> open(LifePost post) async {
    await lifeAction(context, () => store.view(post.id));
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(state: widget.state, postId: post.id),
      ),
    );
  }

  Future<void> compose() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PostEditorScreen(state: widget.state)),
    );
    if (saved == true && mounted) {
      setState(() {
        tab = 1;
        topic = '';
        query = '';
        search.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      var posts = store.posts.where((p) {
        if (tab == 2 && !store.following.contains(p.authorId)) return false;
        if (tab == 3 && !store.history.contains(p.id)) return false;
        if (topic == '我的记录' && !store.owns(p)) return false;
        if (topic == '收藏' && !store.bookmarks.contains(p.id)) return false;
        if (topic.isNotEmpty &&
            !['我的记录', '收藏'].contains(topic) &&
            p.topic != topic) {
          return false;
        }
        final haystack =
            '${postCopy(p, p.title)} ${postCopy(p, p.body)} ${postCopy(p, p.author)} ${postCopy(p, p.topic)}'
                .toLowerCase();
        return haystack.contains(query.toLowerCase());
      }).toList();
      posts.sort(
        (a, b) => tab == 3
            ? store.history.indexOf(a.id).compareTo(store.history.indexOf(b.id))
            : b.createdAt.compareTo(a.createdAt),
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                const BrandMark(size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('生活记录'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('discover_search'),
                  tooltip: tr('搜索记录'),
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => setState(() {
                    searching = !searching;
                    if (!searching) {
                      query = '';
                      search.clear();
                    }
                  }),
                ),
                IconButton.filled(
                  key: const Key('new_post'),
                  tooltip: tr('发布记录'),
                  icon: const Icon(Icons.edit_square),
                  onPressed: compose,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    tr('本机生活记录 · 示例内容'),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
                if (store.draft != null)
                  TextButton(onPressed: compose, child: Text(tr('继续草稿'))),
              ],
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                key: const Key('post_search_input'),
                controller: search,
                autofocus: true,
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  hintText: tr('搜索标题、内容或作者'),
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: InkWell(
                    key: Key('feed_tab_$i'),
                    onTap: () => setState(() => tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: tab == i ? green : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        tr(['推荐', '动态', '关注', '历史'][i]),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tab == i ? ink : muted,
                          fontWeight: tab == i
                              ? FontWeight.w700
                              : FontWeight.w400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              children: [
                for (final value in ['', '日常', '心情', '旅行', '灵感', '我的记录', '收藏'])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(
                        tr(value.isEmpty ? '全部' : value),
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: topic == value,
                      onSelected: (_) => setState(() => topic = value),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: posts.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 30),
                      const Icon(
                        Icons.auto_stories_outlined,
                        size: 44,
                        color: muted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr(
                          tab == 2
                              ? '还没有关注的记录'
                              : tab == 3
                              ? '还没有浏览记录'
                              : '这里还没有记录',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(tab == 2 ? '关注喜欢的作者后，再来看看。' : '写下今天值得记住的一件事。'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: FilledButton.icon(
                          onPressed: compose,
                          icon: const Icon(Icons.add),
                          label: Text(tr('写一篇记录')),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      if (tab == 3)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              if (await confirm(
                                    context,
                                    tr('清空历史'),
                                    tr('仅清除浏览历史，不会删除记录。'),
                                  ) &&
                                  context.mounted) {
                                await lifeAction(context, store.clearHistory);
                              }
                            },
                            child: Text(tr('清空历史')),
                          ),
                        ),
                      if (tab == 0)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var column = 0; column < 2; column++) ...[
                              if (column == 1) const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  children: [
                                    for (
                                      var i = column;
                                      i < posts.length;
                                      i += 2
                                    )
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _PostCard(
                                          post: posts[i],
                                          store: store,
                                          onOpen: () => open(posts[i]),
                                          compact: true,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        )
                      else
                        for (final post in posts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _PostCard(
                              post: post,
                              store: store,
                              onOpen: () => open(post),
                            ),
                          ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}

class _PostCard extends StatelessWidget {
  final LifePost post;
  final LifeStore store;
  final VoidCallback onOpen;
  final bool compact;
  const _PostCard({
    required this.post,
    required this.store,
    required this.onOpen,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: Key('post_${post.id}'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
              child: _Author(post: post, store: store),
            ),
          if (post.photos.isNotEmpty)
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: compact ? (post.portrait.isEven ? .82 : 1) : 1.5,
                  child: PostPhoto(post.photos.first),
                ),
                if (post.photos.length > 1)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${post.photos.length}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                if (post.sample)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      color: Colors.white.withValues(alpha: .9),
                      child: Text(
                        tr('示例'),
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
          Padding(
            padding: EdgeInsets.all(compact ? 10 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  postCopy(post, post.title),
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                    fontSize: compact ? 14 : 17,
                    height: 1.5,
                  ),
                ),
                if (post.aiGenerated)
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: AiContentLabel(),
                  ),
                if (!compact || post.photos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      postCopy(post, post.body),
                      maxLines: compact ? 5 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.8,
                      ),
                    ),
                  ),
                if (post.topic.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '#${tr(post.topic)}',
                      style: const TextStyle(color: green, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 6),
                if (compact)
                  Row(
                    children: [
                      HumanAvatar(size: 22, variant: post.portrait),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          postCopy(post, post.author),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: tr(
                          store.likes.contains(post.id) ? '取消点赞' : '点赞',
                        ),
                        onPressed: store.saving
                            ? null
                            : () => lifeAction(
                                context,
                                () => store.toggleLike(post.id),
                              ),
                        icon: Icon(
                          store.likes.contains(post.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 18,
                          color: store.likes.contains(post.id)
                              ? Colors.pink
                              : muted,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          postDate(post.createdAt),
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ),
                      _PostActions(post: post, store: store, onComment: onOpen),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Author extends StatelessWidget {
  final LifePost post;
  final LifeStore store;
  const _Author({required this.post, required this.store});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      HumanAvatar(size: 34, variant: post.portrait),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              postCopy(post, post.author),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              tr(post.sample ? '示例作者' : '我的记录'),
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
      ),
      if (!store.owns(post))
        TextButton(
          onPressed: store.saving
              ? null
              : () => lifeAction(
                  context,
                  () => store.toggleFollow(post.authorId),
                ),
          child: Text(
            tr(store.following.contains(post.authorId) ? '已关注' : '+ 关注'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ],
  );
}

class _PostActions extends StatelessWidget {
  final LifePost post;
  final LifeStore store;
  final VoidCallback? onComment;
  const _PostActions({required this.post, required this.store, this.onComment});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: Key('like_${post.id}'),
        tooltip: tr(store.likes.contains(post.id) ? '取消点赞' : '点赞'),
        onPressed: store.saving
            ? null
            : () => lifeAction(context, () => store.toggleLike(post.id)),
        icon: Icon(
          store.likes.contains(post.id)
              ? Icons.favorite
              : Icons.favorite_border,
          color: store.likes.contains(post.id) ? Colors.pink : muted,
          size: 21,
        ),
      ),
      Text(
        store.likes.contains(post.id) ? '1' : '0',
        style: const TextStyle(color: muted, fontSize: 11),
      ),
      IconButton(
        key: Key('bookmark_${post.id}'),
        tooltip: tr(store.bookmarks.contains(post.id) ? '取消收藏' : '收藏'),
        onPressed: store.saving
            ? null
            : () => lifeAction(context, () => store.toggleBookmark(post.id)),
        icon: Icon(
          store.bookmarks.contains(post.id)
              ? Icons.bookmark
              : Icons.bookmark_border,
          size: 21,
          color: green,
        ),
      ),
      if (onComment != null)
        IconButton(
          tooltip: tr('评论'),
          onPressed: onComment,
          icon: const Icon(Icons.chat_bubble_outline, size: 20, color: muted),
        ),
    ],
  );
}

class PostDetailScreen extends StatefulWidget {
  final AppState state;
  final String postId;
  const PostDetailScreen({
    required this.state,
    required this.postId,
    super.key,
  });
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final comment = TextEditingController();
  final commentFocus = FocusNode();
  @override
  void dispose() {
    comment.dispose();
    commentFocus.dispose();
    super.dispose();
  }

  Future<void> sendComment() async {
    try {
      await widget.state.life.comment(
        widget.postId,
        widget.state.nickname,
        comment.text,
      );
      comment.clear();
      commentFocus.unfocus();
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state.life,
    builder: (context, _) {
      final store = widget.state.life,
          post = widget.state.life.find(widget.postId);
      if (post == null) {
        return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(tr('记录已删除'))),
        );
      }
      final replies = store.comments[post.id] ?? [];
      return Scaffold(
        appBar: AppBar(
          title: Text(tr('生活记录')),
          actions: [
            if (store.owns(post))
              PopupMenuButton<String>(
                tooltip: tr('更多'),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PostEditorScreen(state: widget.state, post: post),
                      ),
                    );
                  } else if (await confirm(
                        context,
                        tr('删除记录'),
                        tr('删除后无法恢复，确定继续吗？'),
                      ) &&
                      context.mounted) {
                    try {
                      await store.deletePost(post);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) toast(context, errorText(e));
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('编辑'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('删除'))),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _Author(post: post, store: store),
            const SizedBox(height: 16),
            if (post.photos.isNotEmpty)
              SizedBox(
                height: 330,
                child: PageView(
                  children: [
                    for (final photo in post.photos)
                      GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog.fullscreen(
                            child: Scaffold(
                              appBar: AppBar(),
                              body: InteractiveViewer(
                                minScale: .5,
                                maxScale: 4,
                                child: Center(
                                  child: PostPhoto(photo, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: PostPhoto(photo, fit: BoxFit.contain),
                        ),
                      ),
                  ],
                ),
              ),
            if (post.photos.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr('左右滑动查看 {0} 张照片', [post.photos.length]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              postCopy(post, post.title),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (post.aiGenerated)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: AiContentLabel(),
              ),
            const SizedBox(height: 14),
            SelectableText(
              postCopy(post, post.body),
              style: const TextStyle(height: 1.9),
            ),
            const SizedBox(height: 16),
            if (post.topic.isNotEmpty)
              Text('#${tr(post.topic)}', style: const TextStyle(color: green)),
            const SizedBox(height: 12),
            Text(
              '${postDate(post.createdAt)}${post.location.isEmpty ? '' : ' · ${postCopy(post, post.location)}'}',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
            _PostActions(post: post, store: store),
            const Divider(),
            const SizedBox(height: 18),
            Text(
              tr('评论 ({0})', [replies.length]),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (replies.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  tr('还没有评论，留下你的感受吧。'),
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            for (final reply in replies)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.author,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(reply.body),
                    const SizedBox(height: 4),
                    Text(
                      postDate(reply.date),
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('post_comment'),
                      controller: comment,
                      focusNode: commentFocus,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: tr('写下你的感受…'),
                        counterText: '',
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    key: const Key('send_comment'),
                    tooltip: tr('发送'),
                    onPressed: store.saving ? null : sendComment,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class PostEditorScreen extends StatefulWidget {
  final AppState state;
  final LifePost? post;
  const PostEditorScreen({required this.state, this.post, super.key});
  @override
  State<PostEditorScreen> createState() => _PostEditorScreenState();
}

class _PostEditorScreenState extends State<PostEditorScreen> {
  final title = TextEditingController(),
      body = TextEditingController(),
      location = TextEditingController();
  final form = GlobalKey<FormState>();
  List<String> photos = [];
  String topic = '日常';
  bool busy = false, picking = false, dirty = false, leaving = false;
  bool aiGenerated = false;
  @override
  void initState() {
    super.initState();
    final p = widget.post;
    final d = p == null ? widget.state.life.draft : null;
    aiGenerated = p?.aiGenerated ?? d?['aiGenerated'] == true;
    title.text = p?.title ?? d?['title'] ?? '';
    body.text = p?.body ?? d?['body'] ?? '';
    location.text = p?.location ?? d?['location'] ?? '';
    topic = p?.topic ?? d?['topic'] ?? '日常';
    photos = List<String>.from(p?.photos ?? d?['photos'] ?? []);
    for (final c in [title, body, location]) {
      c.addListener(() {
        dirty = true;
      });
    }
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    location.dispose();
    super.dispose();
  }

  Map<String, dynamic> get draft => {
    'aiGenerated': aiGenerated,
    'title': title.text,
    'body': body.text,
    'location': location.text,
    'topic': topic,
    'photos': photos,
  };
  Future<void> pick() async {
    if (busy || picking || photos.length >= 6) return;
    setState(() => picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || !mounted) return;
      if (photos.length + result.files.length > 6) {
        throw StateError(tr('最多添加 6 张照片'));
      }
      final next = <String>[];
      for (final file in result.files) {
        if (file.size == 0 ||
            file.size > 5 * 1024 * 1024 ||
            file.bytes == null) {
          throw StateError(tr('请选择小于 5 MB 的有效图片'));
        }
        final codec = await ui.instantiateImageCodec(
          file.bytes!,
          targetWidth: 720,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final bytes = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes == null) throw StateError(tr('图片读取失败'));
            next.add(base64Encode(bytes.buffer.asUint8List()));
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      if ([...photos, ...next].fold<int>(0, (sum, p) => sum + p.length) >
          2500000) {
        throw StateError(tr('图片总量过大，请减少照片后重试'));
      }
      if (mounted) {
        setState(() {
          photos.addAll(next);
          dirty = true;
        });
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> publish() async {
    if (busy || picking || !form.currentState!.validate()) return;
    if (body.text.trim().isEmpty && photos.isEmpty) {
      toast(context, tr('请添加正文或照片'));
      return;
    }
    setState(() => busy = true);
    try {
      await widget.state.life.publish(
        LifePost(
          id:
              widget.post?.id ??
              'post_${DateTime.now().microsecondsSinceEpoch}',
          authorId: widget.state.username!,
          author: widget.post?.author ?? widget.state.nickname,
          title: title.text.trim(),
          body: body.text.trim(),
          topic: topic,
          location: location.text.trim(),
          photos: List<String>.from(photos),
          createdAt: widget.post?.createdAt ?? DateTime.now(),
          aiGenerated: aiGenerated,
        ),
      );
      if (!mounted) return;
      setState(() {
        leaving = true;
        dirty = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveDraft() async {
    if (busy || picking) return;
    setState(() => busy = true);
    try {
      await widget.state.life.saveDraft(draft);
      if (mounted) {
        setState(() => dirty = false);
        toast(context, tr('草稿已保存在本机'));
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave() async {
    if (busy || picking) return;
    if (dirty &&
        !await confirm(context, tr('放弃未保存的修改？'), tr('可以返回编辑器保存草稿或发布记录。'))) {
      return;
    }
    if (mounted) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!dirty && !busy && !picking),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('返回'),
          onPressed: leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(tr(widget.post == null ? '记录这一刻' : '编辑记录')),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              tr('仅保存在当前设备，不会上传到社区。'),
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < photos.length; i++)
                  SizedBox(
                    width: 92,
                    height: 112,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: PostPhoto(photos[i]),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton.filled(
                            tooltip: tr('移除照片'),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: ink,
                              minimumSize: const Size(28, 28),
                            ),
                            onPressed: busy || picking
                                ? null
                                : () => setState(() {
                                    photos.removeAt(i);
                                    dirty = true;
                                  }),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (photos.length < 6)
                  SizedBox(
                    width: 92,
                    height: 112,
                    child: OutlinedButton(
                      key: const Key('post_pick_photos'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: busy || picking ? null : pick,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          picking
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 28,
                                ),
                          const SizedBox(height: 8),
                          Text(
                            '${photos.length}/6',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('post_title'),
              controller: title,
              enabled: !busy,
              maxLength: 60,
              decoration: InputDecoration(hintText: tr('给这一刻起个标题')),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? tr('请填写标题') : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('post_body'),
              controller: body,
              enabled: !busy,
              maxLength: 2000,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: tr('今天发生了什么？记下心情、故事和想留住的细节。'),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              key: const Key('post_ai_generated'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('包含AI生成内容'), style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                tr('标记使用AI生成的文字或图片'),
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              value: aiGenerated,
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      aiGenerated = value;
                      dirty = true;
                    }),
            ),
            Text(tr('话题'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                for (final t in ['日常', '心情', '旅行', '灵感'])
                  ChoiceChip(
                    label: Text(tr(t)),
                    selected: topic == t,
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                            topic = t;
                            dirty = true;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: location,
              enabled: !busy,
              maxLength: 40,
              decoration: InputDecoration(
                hintText: tr('地点（选填）'),
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            key: const Key('post_editor_actions'),
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Row(
              children: [
                if (widget.post == null) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('save_draft'),
                      onPressed: busy || picking ? null : saveDraft,
                      child: Text(tr('存草稿')),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    key: const Key('publish_post'),
                    onPressed: busy || picking ? null : publish,
                    child: Text(
                      tr(
                        busy
                            ? '保存中…'
                            : widget.post == null
                            ? '发布到本机'
                            : '保存修改',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
