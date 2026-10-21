import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/language.dart';
import '../core/ui.dart';
import '../core/voice_sample.dart';

const voiceReadingPassage =
    '你好，很高兴在这里留下我的声音。今天的阳光很温暖，窗外的风轻轻吹过。我想记住生活里那些平凡又珍贵的瞬间：一次散步，一顿晚餐，还有和家人朋友的每一次相聚。无论未来走到哪里，希望这段熟悉的声音，都能带来一点温暖和陪伴。让我们慢慢说话，认真生活，把美好的回忆留在时光里。';

class VoiceSampleStep extends StatefulWidget {
  final VoiceSampleController controller;
  final VoidCallback onUpload;
  final bool picking;
  const VoiceSampleStep({
    required this.controller,
    required this.onUpload,
    required this.picking,
    super.key,
  });
  @override
  State<VoiceSampleStep> createState() => _VoiceSampleStepState();
}

class _VoiceSampleStepState extends State<VoiceSampleStep> {
  bool recordMode = false;
  @override
  Widget build(BuildContext context) {
    final audio = widget.controller;
    final locked = widget.picking || audio.busy;
    final totalSeconds = audio.elapsed.inSeconds.clamp(0, 60);
    final clock =
        '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(tr('02 / 录入声音样本'), subtitle: tr('让熟悉的声音，成为 TA 的一部分')),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.upload_file_outlined, size: 19),
              label: Text(tr('上传声音')),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.mic_none_rounded, size: 19),
              label: Text(tr('直接录音')),
            ),
          ],
          selected: {recordMode},
          onSelectionChanged: locked
              ? null
              : (values) {
                  audio.stopPlayback();
                  setState(() => recordMode = values.single);
                },
        ),
        const SizedBox(height: 20),
        if (!recordMode)
          Panel(
            color: const Color(0xFFEAF5FF),
            child: Column(
              children: [
                const Icon(Icons.graphic_eq_rounded, size: 54, color: green),
                const SizedBox(height: 12),
                Text(
                  tr('上传一段清晰的声音'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('WAV / MP3 / M4A · 最大 {0} MB', [kIsWeb ? 2 : 20]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('pick_voice'),
                  onPressed: locked ? null : widget.onUpload,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(
                    audio.sample == null ? tr('选择声音文件') : tr('更换声音文件'),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Text(
            tr('建议录制 30 秒 · 最少 10 秒 · 最长 60 秒'),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                audio.recording ? Icons.mic : Icons.mic_none_rounded,
                color: audio.recording ? Colors.red.shade700 : green,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$clock / 01:00',
                  key: const Key('voice_timer'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            container: true,
            child: LinearProgressIndicator(
              value: audio.elapsed.inMilliseconds.clamp(0, 60000) / 60000,
              semanticsLabel: tr('录音进度'),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('record_voice'),
            onPressed: widget.picking || (audio.busy && !audio.recording)
                ? null
                : audio.recording
                ? audio.stopRecording
                : audio.startRecording,
            icon: Icon(
              audio.recording ? Icons.stop_rounded : Icons.mic_rounded,
            ),
            label: Text(
              tr(switch (audio.phase) {
                VoicePhase.starting => '正在开启麦克风…',
                VoicePhase.finishing => '正在处理录音…',
                VoicePhase.recording => '停止并使用录音',
                VoicePhase.idle =>
                  audio.sample?.duration == null ? '开始录音' : '重新录音',
              }),
            ),
          ),
          if (audio.phase == VoicePhase.starting || audio.recording)
            TextButton(
              onPressed: audio.cancelRecording,
              child: Text(tr('取消本次录音')),
            ),
          const SizedBox(height: 18),
          Text(
            tr('朗读下面这段文字'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr('保持自然语速，在安静环境下朗读；满 60 秒会自动停止。'),
            style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr(voiceReadingPassage),
              key: const Key('voice_reading_passage'),
              style: const TextStyle(fontSize: 15, height: 1.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('朗读参考文本 · 内容由AI生成'),
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
        if (audio.error != null || audio.notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                tr(audio.error ?? audio.notice!),
                key: const Key('voice_status'),
                style: TextStyle(
                  color: audio.error != null ? Colors.red.shade700 : green,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          ),
        if (audio.sample != null) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            tr('当前声音样本'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            audio.sample!.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            audio.sample!.duration == null
                ? tr('已选择 · 将随创建流程保存在本机')
                : tr('已录制 {0} 秒 · 将随创建流程保存在本机', [
                    (audio.sample!.duration!.inMilliseconds / 1000)
                        .toStringAsFixed(1),
                  ]),
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('preview_voice'),
            onPressed: locked || audio.loadingPlayback
                ? null
                : audio.togglePlayback,
            icon: Icon(
              audio.playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              tr(
                audio.loadingPlayback
                    ? '正在加载音频…'
                    : audio.playing
                    ? '停止试听'
                    : '试听声音',
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          tr(
            '仅在点击录音并授权后使用麦克风；离开页面即停止。声音样本在创建时保存在本机，不会自动上传或用于训练。请仅录入本人或已获授权的声音。',
          ),
          style: const TextStyle(color: muted, fontSize: 11, height: 1.8),
        ),
      ],
    );
  }
}
