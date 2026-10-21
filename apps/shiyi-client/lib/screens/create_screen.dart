import '../core/language.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/media_store.dart';
import '../core/models.dart';
import '../core/ui.dart';
import '../core/voice_sample.dart';
import 'voice_sample_step.dart';

class CreateScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onCreated;
  final bool active;
  final VoiceSampleController? voiceController;
  const CreateScreen({
    required this.state,
    required this.onCreated,
    this.active = true,
    this.voiceController,
    super.key,
  });
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen>
    with WidgetsBindingObserver {
  int step = 0;
  bool rights = false, busy = false, picking = false;
  double progress = 0;
  Uint8List? photo;
  String? photoName;
  late final VoiceSampleController audio;
  String? _lastVoiceError;
  Uint8List? get voice => audio.sample?.bytes;
  String? get voiceName => audio.sample?.name;
  String? get voiceExt => audio.sample?.extension;
  final name = TextEditingController(),
      description = TextEditingController(),
      personality = TextEditingController(),
      greeting = TextEditingController();
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  String group = '#';
  @override
  void initState() {
    super.initState();
    audio = widget.voiceController ?? VoiceSampleController();
    audio.addListener(_audioChanged);
    audio.setActive(widget.active && step == 1);
    WidgetsBinding.instance.addObserver(this);
  }

  void _audioChanged() {
    if (!mounted) return;
    final error = audio.error;
    if (error != null && error != _lastVoiceError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && step == 1) toast(context, tr(error));
      });
    }
    _lastVoiceError = error;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant CreateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      audio.setActive(widget.active && step == 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      audio.setActive(widget.active && step == 1);
    } else if (state != AppLifecycleState.inactive || audio.recording) {
      // Permission dialogs can make Android inactive before recording begins.
      audio.setActive(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    audio.removeListener(_audioChanged);
    audio.dispose();
    scroll.dispose();
    for (final c in [name, description, personality, greeting]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(bool image) async {
    if (picking || busy || audio.busy) return;
    setState(() => picking = true);
    try {
      await audio.stopPlayback();
      if (!mounted) return;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: image
            ? ['jpg', 'jpeg', 'png', 'webp']
            : ['wav', 'mp3', 'm4a'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      final maxSize = image ? 5 : (kIsWeb ? 2 : 20);
      if (file.size > maxSize * 1024 * 1024 ||
          file.size == 0 ||
          file.bytes == null) {
        throw StateError(
          tr("请选择非空且小于 {0} MB 的{1}", [maxSize, tr(image ? "图片" : "音频")]),
        );
      }
      var bytes = file.bytes!;
      if (image) {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 600,
          allowUpscaling: false,
        );
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        frame.image.dispose();
        codec.dispose();
        if (data == null) throw StateError(tr("图片读取失败"));
        bytes = data.buffer.asUint8List();
      }
      if (!mounted) return;
      setState(() {
        if (image) {
          photo = bytes;
          photoName = file.name;
        } else {
          audio.select(
            VoiceSample(bytes, file.name, file.extension!.toLowerCase()),
          );
        }
      });
    } catch (e) {
      if (mounted) toast(context, tr("文件选择失败：{0}", [errorText(e)]));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void next() {
    if (audio.busy) return;
    if (step == 0 && photo == null) {
      toast(context, tr("请先上传一张形象图片"));
      return;
    }
    if (step == 1 && voice == null) {
      toast(context, tr("请先上传声音或完成一段录音"));
      return;
    }
    if (step == 2 && !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    changeStep(step + 1);
  }

  void changeStep(int value) {
    audio.setActive(widget.active && value == 1);
    setState(() => step = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  Future<void> create() async {
    if (!rights ||
        busy ||
        photo == null ||
        voice == null ||
        name.text.trim().isEmpty) {
      return;
    }
    setState(() {
      busy = true;
      progress = .15;
    });
    String? voicePath;
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      voicePath = await saveVoice(
        '${widget.state.username}_$id',
        voiceExt!,
        voice!,
      );
      if (!mounted) return;
      setState(() => progress = .6);
      final human = DigitalHuman(
        id: id,
        name: name.text.trim(),
        description: description.text.trim(),
        personality: personality.text.trim(),
        greeting: greeting.text.trim().isEmpty
            ? tr("你好，我是{0}，很高兴认识你！", [name.text.trim()])
            : greeting.text.trim(),
        group: group,
        color: 0xFFE1F0FF,
        createdAt: DateTime.now(),
        photo: base64Encode(photo!),
        voicePath: voicePath,
        voiceName: voiceName,
      );
      await widget.state.addContact(human);
      if (!mounted) return;
      setState(() => progress = 1);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: green, size: 48),
          title: Text(tr("新的伙伴，新的故事")),
          content: Text(
            tr("{0} 已加入你的联系人。\n可进入伙伴资料开始语音或照片视频通话；声音样本未用于克隆。", [human.name]),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr("去看看 TA")),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        step = 0;
        photo = null;
        audio.clear();
        photoName = null;
        rights = false;
        group = '#';
        for (final c in [name, description, personality, greeting]) {
          c.clear();
        }
      });
      widget.onCreated();
    } catch (e) {
      await removeVoice(voicePath);
      if (mounted) toast(context, tr("创建失败：{0}", [errorText(e)]));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          key: const Key('create_content'),
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: const DemoTag(text: 'CREATE A MEMORY COMPANION'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.auto_awesome_outlined, color: green),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              tr("让记忆中的 TA 来到身边"),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              tr("四个小步骤，唤醒一位承载故事的数字伙伴。"),
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 27),
            Row(
              children: [
                for (int i = 0; i < 4; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 35,
                          height: 35,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= step ? green : const Color(0xFFE4EEFB),
                          ),
                          child: Center(
                            child: i < step
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : Text(
                                    '0${i + 1}',
                                    style: TextStyle(
                                      color: i <= step ? Colors.white : muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          [tr("形象图片"), tr("声音样本"), tr("基础信息"), tr("创建数字人")][i],
                          style: TextStyle(
                            fontSize: 10,
                            color: i == step ? green : muted,
                            fontWeight: i == step
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (step == 0) ...[
              SectionLabel(tr("01 / 上传形象图片"), subtitle: tr("从一张清晰的正面照片开始")),
              GestureDetector(
                key: const Key('pick_photo'),
                onTap: picking ? null : () => pick(true),
                child: Container(
                  height: 240,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF5FF),
                    border: Border.all(color: const Color(0xFFC9E3FF)),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photo != null
                      ? Image.memory(photo!, fit: BoxFit.contain)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: green,
                              size: 48,
                            ),
                            SizedBox(height: 17),
                            Text(
                              tr("点击上传形象照片"),
                              style: TextStyle(
                                color: green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              tr("JPG / PNG / WebP · 最大 5 MB"),
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ),
                ),
              ),
              if (photoName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: green,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          photoName!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: green),
                        ),
                      ),
                      TextButton(
                        onPressed: () => pick(true),
                        child: Text(tr("更换")),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Panel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: green,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr("小贴士\n选择光线均匀、五官清晰的单人正面照片，避免遮挡和过度滤镜。"),
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (step == 1)
              VoiceSampleStep(
                controller: audio,
                picking: picking,
                onUpload: () => pick(false),
              ),
            if (step == 2)
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(
                      tr("03 / 完善基础信息"),
                      subtitle: tr("一个名字，一种性格，一次相遇"),
                    ),
                    FieldLabel(tr("TA 的名字 *")),
                    TextFormField(
                      key: const Key('human_name'),
                      controller: name,
                      maxLength: 20,
                      decoration: InputDecoration(hintText: tr("例如：林屿")),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? tr("请输入数字人的名字")
                          : null,
                    ),
                    FieldLabel(tr("一句话介绍 *")),
                    TextFormField(
                      controller: description,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: tr("例如：陪你发现生活之美的旅行搭子"),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? tr("请填写一句话介绍") : null,
                    ),
                    FieldLabel(tr("性格与背景 *")),
                    TextFormField(
                      controller: personality,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: tr("描述 TA 的性格、兴趣和说话方式…"),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? tr("请填写性格与背景") : null,
                    ),
                    FieldLabel(tr("第一句问候")),
                    TextFormField(
                      controller: greeting,
                      maxLength: 100,
                      decoration: InputDecoration(hintText: tr("你好，很高兴认识你！")),
                    ),
                    FieldLabel(tr("联系人字母分组")),
                    DropdownButtonFormField<String>(
                      initialValue: group,
                      decoration: InputDecoration(
                        helperText: tr("可手选姓名拼音首字母；未选择时归入 #"),
                      ),
                      items:
                          [
                                '#',
                                ...List.generate(
                                  26,
                                  (i) => String.fromCharCode(65 + i),
                                ),
                              ]
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => group = v!),
                    ),
                  ],
                ),
              ),
            if (step == 3) ...[
              SectionLabel(
                tr("04 / 准备好相遇了吗？"),
                subtitle: tr("确认资料，为 TA 开启新故事"),
              ),
              Panel(
                child: Column(
                  children: [
                    if (photo != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.memory(
                          photo!,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      name.text,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 22),
                    const Divider(),
                    const SizedBox(height: 18),
                    for (final row in [
                      (tr("形象图片"), photoName ?? ''),
                      (tr("声音样本"), voiceName ?? ''),
                      (tr("性格设定"), personality.text),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: green,
                              size: 16,
                            ),
                            const SizedBox(width: 9),
                            Text(row.$1, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                row.$2,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: rights,
                onChanged: busy ? null : (v) => setState(() => rights = v!),
                title: Text(
                  tr("我确认拥有所选肖像与声音的使用授权"),
                  style: TextStyle(fontSize: 12),
                ),
              ),
              Text(
                tr("演示模式：保存资料并加入联系人，不进行模型训练或声音克隆。"),
                style: TextStyle(color: muted, fontSize: 11, height: 1.8),
              ),
              if (busy)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: LinearProgressIndicator(
                    value: progress,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _CreateActionBar(
          key: const Key('create_actions'),
          step: step,
          busy: busy,
          picking: picking,
          rights: rights,
          recording: audio.recording,
          audioWorking: audio.busy && !audio.recording,
          onBack: () => changeStep(step - 1),
          onNext: audio.recording
              ? audio.stopRecording
              : step == 3
              ? create
              : next,
        ),
      ),
    ],
  );
}

class _CreateActionBar extends StatelessWidget {
  final int step;
  final bool busy, picking, rights, recording, audioWorking;
  final VoidCallback onBack, onNext;

  const _CreateActionBar({
    super.key,
    required this.step,
    required this.busy,
    required this.picking,
    required this.rights,
    required this.recording,
    required this.audioWorking,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: .16),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          if (step > 0) ...[
            OutlinedButton(
              key: const Key('create_back'),
              onPressed: busy || picking ? null : onBack,
              child: Text(tr("上一步")),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton(
              key: const Key('create_next'),
              onPressed:
                  busy || picking || audioWorking || (step == 3 && !rights)
                  ? null
                  : onNext,
              child: Text(
                recording
                    ? tr("停止并使用录音")
                    : audioWorking
                    ? tr("正在处理录音…")
                    : busy
                    ? tr("正在保存…")
                    : picking
                    ? tr("读取文件中…")
                    : step == 3
                    ? tr("创建我的数字人")
                    : tr("下一步"),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
