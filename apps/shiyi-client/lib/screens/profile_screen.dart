import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/cyberverse_api.dart';
import '../core/backend_defaults.dart';
import '../core/ui.dart';
import '../core/language.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatelessWidget {
  final AppState state;
  const ProfileScreen({required this.state, super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 8),
      Row(
        children: [
          Text(tr("我的"), style: Theme.of(context).textTheme.headlineMedium),
          const Spacer(),
          LanguageButton(onToggle: state.toggleLanguage),
        ],
      ),
      const SizedBox(height: 26),
      Panel(
        color: const Color(0xFFE8F4FF),
        child: Row(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [cyan, green, violet],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(23),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 41,
              ),
            ),
            const SizedBox(width: 17),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.nickname,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.canChangePassword
                        ? '@${state.username}'
                        : tr(state.accountLabel),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 17),
      Panel(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('${state.contacts.length}', tr("数字伙伴")),
            Container(width: 1, height: 33, color: line),
            _stat(
              '${state.conversations.values.fold(0, (sum, m) => sum + m.where((v) => v.mine).length)}',
              tr("发送消息"),
            ),
            Container(width: 1, height: 33, color: line),
            _stat(tr("本地"), tr("数据空间")),
          ],
        ),
      ),
      const SizedBox(height: 25),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _row(
              Icons.badge_outlined,
              tr("编辑个人资料"),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(state: state),
                ),
              ),
            ),
            const Divider(indent: 54),
            if (state.canChangePassword)
              _row(
                Icons.lock_outline_rounded,
                tr("修改密码"),
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PasswordScreen(state: state),
                  ),
                ),
              ),
            const Divider(indent: 54),
            _row(
              Icons.palette_outlined,
              tr("外观设置"),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppearanceScreen(state: state),
                ),
              ),
            ),
            const Divider(indent: 54),
            _row(
              Icons.settings_outlined,
              tr("设置"),
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 17),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _row(
              Icons.shield_outlined,
              tr("隐私政策"),
              () => showPolicy(context, true),
            ),
            const Divider(indent: 54),
            _row(
              Icons.description_outlined,
              tr("用户协议"),
              () => showPolicy(context, false),
            ),
            const Divider(indent: 54),
            _row(
              Icons.info_outline_rounded,
              tr("关于时忆"),
              () => showAboutDialog(
                context: context,
                applicationName: tr("时忆 · 数字生命记忆空间"),
                applicationVersion: tr("前端 Demo v1.3.1"),
                applicationIcon: const BrandMark(),
                children: [
                  Text(
                    tr(
                      '使用 Flutter 构建的数字陪伴客户端。\n语音通过 CyberVerse 连接云端AI，照片视频由服务器GPU驱动。\n音色为预设，非声音克隆；文字聊天和生活记录仍为本地演示。',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      OutlinedButton(
        onPressed: () async {
          if (await confirm(context, tr("退出登录"), tr("本地资料会保留，下次登录后可以继续查看。"))) {
            state.logout();
          }
        },
        child: Text(tr("退出登录")),
      ),
      const SizedBox(height: 26),
      Center(
        child: Text(
          tr("让记忆延续，让陪伴常在。"),
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ),
    ],
  );
  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: ink,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      ],
    ),
  );
  Widget _row(IconData icon, String label, VoidCallback onTap) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: green, size: 22),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    trailing: const Icon(Icons.chevron_right_rounded, color: muted, size: 19),
  );
}

class EditProfileScreen extends StatefulWidget {
  final AppState state;
  const EditProfileScreen({required this.state, super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final name = TextEditingController(text: widget.state.nickname);
  late final bio = TextEditingController(text: widget.state.bio);
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr("编辑个人资料"))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        FieldLabel(tr("昵称")),
        TextField(
          controller: name,
          maxLength: 20,
          decoration: InputDecoration(hintText: tr("你的昵称")),
        ),
        FieldLabel(tr("个性签名")),
        TextField(
          controller: bio,
          maxLength: 80,
          maxLines: 3,
          decoration: InputDecoration(hintText: tr("用一句话介绍自己")),
        ),
        const SizedBox(height: 25),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (name.text.trim().isEmpty) {
                    toast(context, tr("昵称不能为空"));
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    widget.state.nickname = name.text.trim();
                    widget.state.bio = bio.text.trim();
                    await widget.state.persist();
                    if (context.mounted) {
                      toast(context, tr("个人资料已保存"));
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (context.mounted) toast(context, errorText(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? tr("保存中…") : tr("保存资料")),
        ),
      ],
    ),
  );
}

class PasswordScreen extends StatefulWidget {
  final AppState state;
  const PasswordScreen({required this.state, super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class AppearanceScreen extends StatelessWidget {
  final AppState state;
  const AppearanceScreen({required this.state, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr("外观设置"))),
    body: MemoryBackdrop(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionLabel(
            tr("选择时忆氛围"),
            subtitle: tr("主题会应用到登录后的主要页面，并自动保存在当前账号。"),
          ),
          for (final option in [
            (
              'sky',
              tr("云端时光"),
              tr("通透冰蓝，像把回忆收藏在晴空里"),
              [Color(0xFF31C7F4), Color(0xFF2476FF)],
              Icons.cloud_outlined,
            ),
            (
              'aurora',
              tr("极光记忆"),
              tr("蓝紫流光，适合更梦幻的数字生命氛围"),
              [Color(0xFF5D76F5), Color(0xFFA75BEF)],
              Icons.auto_awesome_outlined,
            ),
            (
              'ocean',
              tr("深海回响"),
              tr("青蓝静谧，像声音在时间里温柔回荡"),
              [Color(0xFF18C5CB), Color(0xFF087FAE)],
              Icons.waves_rounded,
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () async {
                  try {
                    await state.setAppearance(option.$1);
                    if (context.mounted) {
                      toast(context, tr("已切换为{0}", [option.$2]));
                    }
                  } catch (e) {
                    if (context.mounted) toast(context, errorText(e));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: option.$4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: state.appearance == option.$1
                          ? Colors.white
                          : Colors.white54,
                      width: state.appearance == option.$1 ? 2.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: option.$4.last.withValues(alpha: .24),
                        blurRadius: 22,
                        offset: const Offset(0, 9),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(option.$5, color: Colors.white, size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              option.$3,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        state.appearance == option.$1
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandMark(size: 40),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    tr(
                      "Logo 可替换\n将 assets/branding/logo.png 替换为同名 PNG 后重新构建，即可换成正式品牌标志。",
                    ),
                    style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PasswordScreenState extends State<PasswordScreen> {
  final old = TextEditingController(),
      next = TextEditingController(),
      again = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    again.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr("修改密码"))),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Panel(
            child: Text(
              tr("更改当前本地账号的密码。请使用专用于演示的密码。"),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          FieldLabel(tr("原密码")),
          TextFormField(
            controller: old,
            obscureText: true,
            decoration: InputDecoration(hintText: tr("请输入原密码")),
            validator: (v) => v == null || v.isEmpty ? tr("请输入原密码") : null,
          ),
          FieldLabel(tr("新密码")),
          TextFormField(
            controller: next,
            obscureText: true,
            decoration: InputDecoration(hintText: tr("8–64 位，包含字母和数字")),
            validator: (v) => translatedError(AppState.passwordError(v ?? '')),
          ),
          FieldLabel(tr("确认新密码")),
          TextFormField(
            controller: again,
            obscureText: true,
            decoration: InputDecoration(hintText: tr("请再次输入新密码")),
            validator: (v) => v != next.text ? tr("两次新密码不一致") : null,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    try {
                      await widget.state.changePassword(old.text, next.text);
                      if (context.mounted) {
                        toast(context, tr("密码修改成功，下次登录请使用新密码"));
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (context.mounted) toast(context, errorText(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(busy ? tr("修改中…") : tr("确认修改")),
          ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({required this.state, super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final url = TextEditingController(text: widget.state.backendUrl);
  late final avatarUrl = TextEditingController(
    text: widget.state.avatarBackendUrl,
  );
  bool testing = false;
  String? status, avatarStatus;
  @override
  void dispose() {
    url.dispose();
    avatarUrl.dispose();
    super.dispose();
  }

  Future<void> testConnection({bool avatar = false}) async {
    final selected = avatar ? avatarUrl : url;
    final uri = Uri.tryParse(selected.text.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      toast(context, tr("请填写有效的 http(s) 服务地址，不含账号、查询参数或 #"));
      return;
    }
    setState(() {
      testing = true;
      if (avatar) {
        avatarStatus = null;
      } else {
        status = null;
      }
    });
    final api = CyberVerseApi(selected.text.trim());
    try {
      if (avatar) {
        widget.state.avatarBackendUrl = api.baseUrl;
      } else {
        widget.state.backendUrl = api.baseUrl;
      }
      await widget.state.persist();
      final response = await api.health();
      if (!mounted) return;
      final message = tr("服务响应：{0}；推理服务：{1}", [
        response['status'],
        tr(response['inference_connected'] == true ? '已连接' : '未连接'),
      ]);
      setState(() {
        if (avatar) {
          avatarStatus = message;
        } else {
          status = message;
        }
      });
    } catch (e) {
      if (mounted) {
        final message = tr("连接失败。请检查地址、网络和后端服务。\n{0}", [errorText(e)]);
        setState(() {
          if (avatar) {
            avatarStatus = message;
          } else {
            status = message;
          }
        });
      }
    } finally {
      api.close();
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr("设置"))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionLabel(tr("使用偏好")),
        Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            title: Text(tr("消息提醒"), style: TextStyle(fontSize: 14)),
            subtitle: Text(
              tr("演示开关，暂不发送系统通知"),
              style: TextStyle(fontSize: 11, color: muted),
            ),
            value: widget.state.notifications,
            onChanged: (v) async {
              setState(() => widget.state.notifications = v);
              try {
                await widget.state.persist();
              } catch (e) {
                if (context.mounted) toast(context, errorText(e));
              }
            },
          ),
        ),
        SectionLabel(tr("后端连接"), subtitle: tr('此地址用于真实语音通话')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DemoTag(text: tr('真实语音 · GPU照片视频')),
              const SizedBox(height: 16),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr("服务器根地址"),
                  hintText: 'http://127.0.0.1:18080',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  '浏览器联调：127.0.0.1:18080\n安卓模拟器：10.0.2.2:18080\n先启动项目的语音联调入口，再开始通话。仅在同意通话后发送伙伴文字设定与通话内容；不会上传照片和声音样本。',
                ),
                style: TextStyle(color: muted, fontSize: 11, height: 1.8),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                key: const Key('voice_local_backend'),
                onPressed: testing
                    ? null
                    : () {
                        url.text = defaultBackendUrl();
                        testConnection();
                      },
                icon: const Icon(Icons.computer_outlined, size: 18),
                label: Text(tr('使用本机联调地址')),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: testing ? null : testConnection,
                  icon: const Icon(Icons.cable_rounded, size: 18),
                  label: Text(testing ? tr("检测中…") : tr("保存地址并测试连接")),
                ),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    status!,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        SectionLabel(tr('照片视频服务器')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('avatar_backend_url'),
                controller: avatarUrl,
                enabled: !testing,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr('照片视频服务器地址'),
                  hintText: defaultAvatarBackendUrl(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  '使用独立的18082端口，需启动照片视频联调入口。仅同意并开始后上传肖像；真机需可达的服务器地址或USB转发，不能直接使用模拟器地址。',
                ),
                style: const TextStyle(color: muted, fontSize: 11, height: 1.8),
              ),
              TextButton.icon(
                key: const Key('avatar_local_backend'),
                onPressed: testing
                    ? null
                    : () {
                        avatarUrl.text = defaultAvatarBackendUrl();
                        testConnection(avatar: true);
                      },
                icon: const Icon(Icons.computer_outlined, size: 18),
                label: Text(tr('使用本机联调地址')),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('avatar_test_backend'),
                  onPressed: testing
                      ? null
                      : () => testConnection(avatar: true),
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: Text(testing ? tr('检测中…') : tr('保存地址并测试连接')),
                ),
              ),
              if (avatarStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    avatarStatus!,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        SectionLabel(tr("本地数据")),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.cleaning_services_outlined,
                  color: green,
                ),
                title: Text(tr("清空聊天记录"), style: TextStyle(fontSize: 13)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  if (!await confirm(
                    context,
                    tr("清空聊天记录"),
                    tr("将删除当前账号的全部本地聊天记录，联系人仍保留。"),
                  )) {
                    return;
                  }
                  try {
                    await widget.state.clearMessages();
                    if (context.mounted) toast(context, tr("聊天记录已清空"));
                  } catch (e) {
                    if (context.mounted) toast(context, errorText(e));
                  }
                },
              ),
              const Divider(indent: 54),
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: Colors.redAccent,
                ),
                title: Text(
                  tr("删除当前本地账号"),
                  style: TextStyle(fontSize: 13, color: Colors.redAccent),
                ),
                onTap: () async {
                  if (!await confirm(
                    context,
                    tr("删除本地账号"),
                    tr("将删除当前账号、数字人资料、声音文件、聊天记录和生活记录。此操作无法撤销。"),
                  )) {
                    return;
                  }
                  try {
                    await widget.state.deleteAccount();
                    if (context.mounted) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  } catch (e) {
                    if (context.mounted) toast(context, errorText(e));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            tr("时忆 App · Flutter Demo 1.3.1"),
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
