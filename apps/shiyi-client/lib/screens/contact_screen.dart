import '../core/language.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/ui.dart';
import 'voice_call_screen.dart';

class ContactScreen extends StatelessWidget {
  final AppState state;
  final DigitalHuman human;
  const ContactScreen({required this.state, required this.human, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr("伙伴资料")),
      actions: [
        PopupMenuButton<String>(
          onSelected: (_) async {
            if (!await confirm(
              context,
              tr("删除数字人"),
              tr("删除 {0} 的本地资料、声音文件和聊天记录？", [human.name]),
            )) {
              return;
            }
            try {
              await state.deleteContact(human);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) toast(context, errorText(e));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'delete',
              child: Text(tr("删除数字人"), style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Panel(
          color: const Color(0xFFEDF2E9),
          child: Column(
            children: [
              const SizedBox(height: 15),
              HumanAvatar(human: human, size: 125),
              const SizedBox(height: 20),
              Text(
                human.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                human.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              DemoTag(text: human.sample ? tr("示例数字伙伴") : tr("我的数字伙伴")),
              const SizedBox(height: 12),
            ],
          ),
        ),
        SectionLabel(tr("开始一段对话"), subtitle: tr("文字、声音，或面对面")),
        Row(
          children: [
            _ModeTile(
              icon: Icons.chat_bubble_outline_rounded,
              text: tr("文字聊天"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(state: state, human: human),
                ),
              ),
            ),
            const SizedBox(width: 9),
            _ModeTile(
              icon: Icons.call_outlined,
              text: tr("语音通话"),
              onTap: () => openCall(context, state, human, false),
            ),
            const SizedBox(width: 9),
            _ModeTile(
              icon: Icons.videocam_outlined,
              text: tr("视频聊天"),
              onTap: () => openCall(context, state, human, true),
            ),
          ],
        ),
        SectionLabel(tr("关于 TA")),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr("性格与背景"), style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                human.personality,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Text(tr("第一句问候"), style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                human.greeting,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                tr("创建于 {0}.{1}.{2}", [
                  human.createdAt.year,
                  human.createdAt.month.toString().padLeft(2, '0'),
                  human.createdAt.day.toString().padLeft(2, '0'),
                ]),
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              if (human.voiceName != null)
                Text(
                  tr("声音文件：{0}", [human.voiceName]),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tr('语音与照片视频连接 CyberVerse；视频由服务器GPU驱动，文字聊天仍为本地演示。'),
          style: TextStyle(color: muted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _ModeTile({
    required this.icon,
    required this.text,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 23),
          child: Column(
            children: [
              Icon(icon, color: green, size: 29),
              const SizedBox(height: 12),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void openCall(
  BuildContext context,
  AppState state,
  DigitalHuman human,
  bool video,
) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => VoiceCallScreen(state: state, human: human, video: video),
  ),
);

class ChatScreen extends StatefulWidget {
  final AppState state;
  final DigitalHuman human;
  const ChatScreen({required this.state, required this.human, super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });
  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    input.clear();
    try {
      await widget.state.addMessage(widget.human.id, ChatMessage(text, true));
      if (!mounted) return;
      setState(() {});
      scrollDown();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final reply = text.contains('你好')
          ? widget.human.greeting
          : text.contains('你是谁')
          ? tr("我是{0}，{1}。现在是本地演示模式，很高兴与你相遇。", [
              widget.human.name,
              widget.human.description,
            ])
          : text.contains('创建')
          ? tr("在底部「创建」中，依次选择形象照片、声音样本并填写信息，就能添加新的数字伙伴。")
          : tr("收到你的分享：“{0}”。我会认真倾听。接入 CyberVerse 后，这里将由真实 AI 生成回复。", [
              text.length > 60 ? '${text.substring(0, 60)}…' : text,
            ]);
      await widget.state.addMessage(widget.human.id, ChatMessage(reply, false));
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) {
        setState(() => sending = false);
        scrollDown();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = [
      ChatMessage(widget.human.greeting, false, time: widget.human.createdAt),
      ...?widget.state.conversations[widget.human.id],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              widget.human.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Text(
              tr("数字伙伴 · 本地演示"),
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr("语音通话"),
            onPressed: () =>
                openCall(context, widget.state, widget.human, false),
            icon: const Icon(Icons.call_outlined, size: 21),
          ),
          IconButton(
            tooltip: tr("视频聊天"),
            onPressed: () =>
                openCall(context, widget.state, widget.human, true),
            icon: const Icon(Icons.videocam_outlined, size: 23),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFEAF0E6),
            padding: const EdgeInsets.all(9),
            child: Text(
              tr("内容由AI生成 · 当前为本地示例回复"),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: green),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              itemCount: messages.length + (sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == messages.length) {
                  return Padding(
                    padding: EdgeInsets.only(left: 48),
                    child: Text(
                      tr("正在回复…"),
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  );
                }
                final m = messages[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: m.mine
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (!m.mine) ...[
                        HumanAvatar(human: widget.human, size: 35),
                        const SizedBox(width: 9),
                      ],
                      Flexible(
                        child: Column(
                          crossAxisAlignment: m.mine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: m.mine ? green : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SelectableText(
                                m.text,
                                style: TextStyle(
                                  color: m.mine ? Colors.white : ink,
                                  height: 1.7,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: muted, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                      if (m.mine) ...[
                        const SizedBox(width: 9),
                        const CircleAvatar(
                          radius: 17,
                          backgroundColor: Color(0xFFE0E9E3),
                          child: Icon(
                            Icons.person_rounded,
                            color: green,
                            size: 22,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chat_input'),
                        controller: input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => send(),
                        decoration: InputDecoration(
                          hintText: tr("说点什么吧…"),
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      key: const Key('send_message'),
                      onPressed: sending ? null : send,
                      tooltip: tr("发送消息"),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CallScreen extends StatefulWidget {
  final DigitalHuman human;
  final bool video;
  const CallScreen({required this.human, required this.video, super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? timer;
  int seconds = 0;
  bool mic = true, speaker = true, camera = true;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => seconds++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF153C33),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      DemoTag(text: widget.video ? tr("模拟视频通话") : tr("模拟语音通话")),
                    ],
                  ),
                  const SizedBox(height: 45),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .12),
                        width: 2,
                      ),
                    ),
                    child: HumanAvatar(
                      human: widget.human,
                      size: widget.video ? 190 : 124,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    widget.human.name,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    seconds < 2
                        ? tr("正在建立演示连接…")
                        : tr("演示中  {0}:{1}", [
                            ((seconds - 2) ~/ 60).toString().padLeft(2, '0'),
                            ((seconds - 2) % 60).toString().padLeft(2, '0'),
                          ]),
                    style: const TextStyle(
                      color: Color(0xFFB4CEC0),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    tr("未采集麦克风或摄像头\n真实通话需对接 WebRTC 媒体链路"),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8EB1A2),
                      fontSize: 11,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 45),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _control(
                        mic ? Icons.mic_none_rounded : Icons.mic_off_outlined,
                        mic ? tr("静音") : tr("取消静音"),
                        () => setState(() => mic = !mic),
                        active: mic,
                      ),
                      _control(
                        speaker
                            ? Icons.volume_up_outlined
                            : Icons.volume_off_outlined,
                        speaker ? tr("扬声器") : tr("听筒"),
                        () => setState(() => speaker = !speaker),
                        active: speaker,
                      ),
                      if (widget.video)
                        _control(
                          camera
                              ? Icons.videocam_outlined
                              : Icons.videocam_off_outlined,
                          camera ? tr("关闭画面") : tr("开启画面"),
                          () => setState(() => camera = !camera),
                          active: camera,
                        ),
                    ],
                  ),
                  if (widget.video && !camera)
                    Padding(
                      padding: EdgeInsets.only(top: 15),
                      child: Text(
                        tr("本地画面已关闭（模拟）"),
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  const SizedBox(height: 35),
                  _control(
                    Icons.call_end_rounded,
                    tr("挂断"),
                    () => Navigator.pop(context),
                    hangup: true,
                  ),
                  const SizedBox(height: 25),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _control(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = true,
    bool hangup = false,
  }) => Column(
    children: [
      IconButton(
        onPressed: onTap,
        tooltip: label,
        style: IconButton.styleFrom(
          backgroundColor: hangup
              ? const Color(0xFFD86C67)
              : active
              ? Colors.white.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .3),
          fixedSize: const Size(62, 62),
        ),
        icon: Icon(icon, color: Colors.white, size: 28),
      ),
      const SizedBox(height: 10),
      Text(
        label,
        style: const TextStyle(color: Color(0xFFD0E0D7), fontSize: 11),
      ),
    ],
  );
}
