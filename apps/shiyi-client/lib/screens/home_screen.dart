import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/ui.dart';
import 'create_screen.dart';
import 'contact_screen.dart';
import 'profile_screen.dart';
import 'discover_screen.dart';
import '../core/language.dart';
import '../core/voice_character.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({required this.state, super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    // The create flow needs a real layout boundary above the navigation bar
    // so its action controls can be pinned to that boundary.
    extendBody: index == 0 || index == 3,
    body: MemoryBackdrop(
      child: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: index,
          children: [
            ContactsScreen(
              state: widget.state,
              onCreate: () => setState(() => index = 2),
            ),
            DiscoverScreen(state: widget.state),
            CreateScreen(
              state: widget.state,
              active: index == 2,
              onCreated: () => setState(() => index = 0),
            ),
            ProfileScreen(state: widget.state),
          ],
        ),
      ),
    ),
    bottomNavigationBar: Container(
      key: const Key('home_navigation'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: .13),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 73,
        indicatorColor: green.withValues(alpha: .12),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: tr('好友'),
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: tr('发现'),
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box_rounded),
            label: tr('创建'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: tr('我的'),
          ),
        ],
      ),
    ),
  );
}

class ContactsScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onCreate;
  const ContactsScreen({
    required this.state,
    required this.onCreate,
    super.key,
  });
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String query = '';
  bool recent = false;
  final Map<String, GlobalKey> anchors = {};
  @override
  Widget build(BuildContext context) {
    final all = widget.state.contacts;
    final people = all
        .where(
          (c) => ('${c.name} ${c.description}').toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    people.sort(
      (a, b) => recent
          ? b.createdAt.compareTo(a.createdAt)
          : ('${a.group}${a.name}').compareTo('${b.group}${b.name}'),
    );
    final groups = people.map((p) => p.group).toSet().toList()..sort();
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
          children: [
            Row(
              children: [
                const BrandMark(size: 28),
                const SizedBox(width: 9),
                Text(
                  tr("时忆"),
                  style: TextStyle(
                    fontSize: 15,
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const DemoTag(text: 'MEMORY SPACE'),
              ],
            ),
            const SizedBox(height: 27),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr("我的记忆伙伴"),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        tr("{0} 位伙伴，收藏着 {1} 段独特时光", [all.length, all.length]),
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  onPressed: widget.onCreate,
                  tooltip: tr("创建数字人"),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('real_voice_preview'),
                onPressed: () =>
                    openCall(context, widget.state, voiceAssistant(), false),
                icon: const Icon(Icons.graphic_eq_rounded),
                label: Text(tr('AI语音体验')),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('contact_search'),
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: tr("搜索你的数字伙伴"),
                prefixIcon: Icon(Icons.search_rounded, color: muted),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: widget.onCreate,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE7F7FF), Color(0xFFEDEBFF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr("下一段记忆，由你唤醒"),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            tr("用形象、声音与故事重现熟悉陪伴"),
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF738675),
                            ),
                          ),
                          SizedBox(height: 17),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  tr("创建数字人"),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: green,
                                  ),
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Transform.rotate(
                      angle: 0,
                      child: const HumanAvatar(size: 84, variant: 1),
                    ),
                  ],
                ),
              ),
            ),
            SectionLabel(
              tr("联系人"),
              trailing: PopupMenuButton<bool>(
                tooltip: tr("排序方式"),
                initialValue: recent,
                onSelected: (v) => setState(() => recent = v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: false, child: Text(tr("按字母分组"))),
                  PopupMenuItem(value: true, child: Text(tr("按创建时间"))),
                ],
                child: Row(
                  children: [
                    Text(
                      recent ? tr("创建历史") : tr("字母排序"),
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
            if (people.isEmpty)
              Panel(
                child: Column(
                  children: [
                    const SizedBox(height: 15),
                    const Icon(
                      Icons.people_outline_rounded,
                      size: 48,
                      color: muted,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      query.isNotEmpty ? tr("没有找到相关伙伴") : tr("还没有数字伙伴"),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      query.isNotEmpty
                          ? tr("试试其他名字或描述")
                          : tr("从一张照片开始，创建你的第一位伙伴。"),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    if (query.isEmpty)
                      TextButton(
                        onPressed: widget.onCreate,
                        child: Text(tr("开始创建")),
                      ),
                    const SizedBox(height: 15),
                  ],
                ),
              ),
            for (int i = 0; i < people.length; i++) ...[
              if (!recent && (i == 0 || people[i - 1].group != people[i].group))
                Padding(
                  key: anchors.putIfAbsent(people[i].group, () => GlobalKey()),
                  padding: const EdgeInsets.fromLTRB(4, 10, 0, 10),
                  child: Text(
                    people[i].group,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              _ContactTile(
                human: people[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ContactScreen(state: widget.state, human: people[i]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 25),
            Center(
              child: Text(
                tr("—  {0} 位数字伙伴  —", [people.length]),
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 9),
            Center(
              child: Text(
                tr("创建记录即联系人 · 点击头像开始交流"),
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ),
          ],
        ),
        if (!recent && groups.isNotEmpty)
          Positioned(
            right: 4,
            top: 180,
            bottom: 15,
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final group in groups)
                      GestureDetector(
                        onTap: () {
                          final c = anchors[group]?.currentContext;
                          if (c != null) {
                            Scrollable.ensureVisible(
                              c,
                              duration: const Duration(milliseconds: 280),
                              alignment: .2,
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 7,
                          ),
                          child: Text(
                            group,
                            style: const TextStyle(
                              fontSize: 10,
                              color: green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  final DigitalHuman human;
  final VoidCallback onTap;
  const _ContactTile({required this.human, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              HumanAvatar(human: human, size: 55),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            human.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: green,
                          ),
                        ),
                        if (human.sample)
                          Padding(
                            padding: EdgeInsets.only(left: 7),
                            child: Text(
                              tr("示例"),
                              style: TextStyle(fontSize: 9, color: muted),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      human.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}
