import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/app_state.dart';
import '../core/cyberverse_api.dart';
import '../core/language.dart';
import '../core/models.dart';
import '../core/ui.dart';
import '../core/voice_call.dart';
import '../core/voice_character.dart';

class VoiceCallScreen extends StatefulWidget {
  final AppState state;
  final DigitalHuman human;
  final VoiceCallController? controller;
  final bool video;
  const VoiceCallScreen({
    required this.state,
    required this.human,
    this.controller,
    this.video = false,
    super.key,
  });
  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with WidgetsBindingObserver {
  late final VoiceCallController call;
  final input = TextEditingController();
  bool consent = false, useMicrophone = false;
  bool pickingPhoto = false;
  Uint8List? selectedPhoto;

  bool get hasPhoto =>
      selectedPhoto != null ||
      widget.human.photo != null ||
      widget.human.sample;

  Future<DigitalHuman> portraitHuman() async {
    Uint8List? bytes = selectedPhoto ?? widget.human.photoBytes;
    if (bytes == null && widget.human.sample) {
      final name = switch (widget.human.id) {
        'sample_su' => 'su',
        'sample_xia' => 'xia',
        _ => 'lin',
      };
      bytes = (await rootBundle.load(
        'assets/portraits/$name.jpg',
      )).buffer.asUint8List();
    }
    if (bytes == null) throw StateError('请先选择已获授权的人像照片');
    return DigitalHuman.fromJson({
      ...widget.human.toJson(),
      'photo': base64Encode(bytes),
    });
  }

  Future<void> pickPortrait() async {
    if (pickingPhoto || !call.canStart) return;
    setState(() => pickingPhoto = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (picked == null || !mounted) return;
      final file = picked.files.single;
      if (file.bytes == null || file.size == 0 || file.size > 5 * 1024 * 1024) {
        throw StateError('请选择小于5MB的有效人像照片');
      }
      final codec = await ui.instantiateImageCodec(
        file.bytes!,
        targetWidth: 600,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) throw StateError('图片读取失败');
      if (mounted) {
        setState(() {
          selectedPhoto = data.buffer.asUint8List();
          consent = false;
        });
      }
    } catch (_) {
      if (mounted) toast(context, tr('请选择小于5MB的有效人像照片'));
    } finally {
      if (mounted) setState(() => pickingPhoto = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final api =
        widget.controller?.api ??
        CyberVerseApi(
          widget.video
              ? widget.state.avatarBackendUrl
              : widget.state.backendUrl,
        );
    final characters = VoiceCharacterRepository(
      widget.state.prefs,
      api,
      widget.state.username ?? 'local',
      avatar: widget.video,
    );
    call =
        widget.controller ??
        VoiceCallController(
          api: api,
          human: widget.human,
          resolveCharacter: () async => characters.resolve(
            widget.video ? await portraitHuman() : widget.human,
          ),
          english: AppLanguage.code == 'en',
          video: widget.video,
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No background-call service is installed; stop capture when hidden.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      call.end();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    call.dispose();
    input.dispose();
    super.dispose();
  }

  void send() {
    if (input.text.trim().isEmpty || !call.canSend) return;
    call.sendText(input.text);
    input.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: call,
    builder: (context, _) => Scaffold(
      backgroundColor: const Color(0xFF153C33),
      appBar: AppBar(
        backgroundColor: const Color(0xFF153C33),
        foregroundColor: Colors.white,
        title: Text(tr(widget.video ? '照片视频通话' : '语音通话')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(tr('内容由AI生成'), style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
      body: ListView(
        key: const Key('voice_call_body'),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        children: [
          if (widget.video)
            AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: const Color(0xFF102E27),
                child: call.media?.videoRenderer == null
                    ? _portraitPreview()
                    : ValueListenableBuilder<RTCVideoValue>(
                        valueListenable: call.media!.videoRenderer!,
                        builder: (_, value, _) => Stack(
                          fit: StackFit.expand,
                          children: [
                            if (value.width == 0) _portraitPreview(),
                            RTCVideoView(
                              call.media!.videoRenderer!,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitContain,
                            ),
                          ],
                        ),
                      ),
              ),
            )
          else
            Center(child: HumanAvatar(human: widget.human, size: 100)),
          const SizedBox(height: 14),
          Text(
            widget.human.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            call.status,
            key: const Key('voice_call_status'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: call.error != null
                  ? const Color(0xFFFFB5AE)
                  : const Color(0xFFB4CEC0),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (call.elapsed > Duration.zero)
            Text(
              '${call.elapsed.inMinutes.toString().padLeft(2, '0')}:${(call.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          const SizedBox(height: 10),
          Text(
            tr('通义预设音色 · 非声音克隆'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            '${tr('服务器')}  ${call.api.baseUrl}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          const SizedBox(height: 18),
          if (call.canStart) ...[
            if (widget.video) ...[
              TextButton.icon(
                key: const Key('avatar_pick_photo'),
                onPressed: pickingPhoto ? null : pickPortrait,
                icon: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Colors.white,
                ),
                label: Text(
                  tr('选择人像照片'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (widget.human.sample && selectedPhoto == null)
                Text(
                  tr('示例肖像用于技术演示，不代表照片人物本人。'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
            ],
            Text(
              tr(
                widget.video
                    ? '开始后将上传当前肖像及伙伴设定，由服务器GPU生成说话视频，云端AI处理对话。仅使用本人或已获授权的肖像，不冒充真人。不会上传声音样本或开启摄像头；开启麦克风后才采音，挂断即停止。远端素材需联系管理员删除。'
                    : '开始后，伙伴的名称、性格、问候及通话内容会发送到你配置的服务器，由云端AI处理。照片和声音样本不会上传。开启麦克风后才采集声音，挂断或离开即停止。请勿分享敏感信息。',
              ),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.7,
              ),
            ),
            CheckboxListTile(
              key: const Key('voice_consent'),
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: (v) => setState(() => consent = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                tr(widget.video ? '我有肖像使用权，并同意上传及AI驱动' : '我同意本次通话的数据处理'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: useMicrophone,
              onChanged: (v) => setState(() => useMicrophone = v),
              title: Text(
                tr('开始时启用麦克风'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
          if (call.warning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                tr(call.warning!),
                style: const TextStyle(
                  color: Color(0xFFFFD694),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          if (call.transcripts.isEmpty && !call.canStart)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                tr('连接后会自动播放AI问候；也可输入文字听取回复。'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ),
          for (final item in call.transcripts)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.assistant ? tr('AI · 内容由AI生成') : tr('你'),
                    style: const TextStyle(
                      color: Color(0xFFB4CEC0),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    item.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          key: const Key('voice_fixed_controls'),
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (call.canStart)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('voice_start'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE4F0E6),
                      foregroundColor: const Color(0xFF153C33),
                    ),
                    onPressed:
                        consent && (!widget.video || hasPhoto) && !pickingPhoto
                        ? () => call.start(microphone: useMicrophone)
                        : null,
                    icon: const Icon(Icons.call_outlined),
                    label: Text(
                      tr(
                        call.phase == VoiceCallPhase.ready
                            ? (widget.video ? '开始照片视频通话' : '开始真实语音通话')
                            : '重新连接',
                      ),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('voice_text_input'),
                        controller: input,
                        enabled: call.canSend,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => send(),
                        decoration: InputDecoration(
                          hintText: tr('输入文字，听AI回复'),
                          hintStyle: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          fillColor: Colors.white.withValues(alpha: .1),
                          filled: true,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('voice_send'),
                      tooltip: tr('发送'),
                      onPressed: call.canSend ? send : null,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _control(
                    'voice_microphone',
                    call.microphone ? Icons.mic : Icons.mic_off_outlined,
                    call.microphone ? tr('关闭麦克风') : tr('开启麦克风'),
                    call.canChangeMedia && !call.changingMicrophone
                        ? call.toggleMicrophone
                        : null,
                  ),
                  _control(
                    'voice_hangup',
                    Icons.call_end_rounded,
                    tr('挂断'),
                    () {
                      call.end();
                      Navigator.maybePop(context);
                    },
                    hangup: true,
                  ),
                  _control(
                    'voice_speaker',
                    call.speaker
                        ? Icons.volume_up_outlined
                        : Icons.volume_off_outlined,
                    call.speaker ? tr('关闭声音') : tr('播放声音'),
                    call.canChangeMedia ? call.toggleSpeaker : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _portraitPreview() => selectedPhoto == null
      ? Center(child: HumanAvatar(human: widget.human, size: 220))
      : Image.memory(selectedPhoto!, fit: BoxFit.contain);

  Widget _control(
    String key,
    IconData icon,
    String label,
    VoidCallback? action, {
    bool hangup = false,
  }) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key(key),
          tooltip: label,
          onPressed: action,
          style: IconButton.styleFrom(
            backgroundColor: hangup
                ? const Color(0xFFC84F4A)
                : Colors.white.withValues(alpha: .12),
            fixedSize: const Size(48, 48),
          ),
          icon: Icon(
            icon,
            color: action == null ? Colors.white38 : Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    ),
  );
}
