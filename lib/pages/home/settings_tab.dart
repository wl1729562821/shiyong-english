import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../services/progress_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static const _sample = 'Welcome to London. May I see your passport, please?';

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    final tts = TtsService.to;
    final repo = LessonRepository.to;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionTitle('朗读'),
            Obx(() => ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text('语速 ${progress.speed.value.toStringAsFixed(1)}x'),
                  subtitle: Slider(
                    value: progress.speed.value,
                    min: ProgressService.minSpeed,
                    max: ProgressService.maxSpeed,
                    divisions:
                        ((ProgressService.maxSpeed - ProgressService.minSpeed) *
                                10)
                            .round(),
                    label: '${progress.speed.value.toStringAsFixed(1)}x',
                    onChanged: progress.setSpeed,
                    onChangeEnd: (_) => tts.say(_sample),
                  ),
                  trailing: const SpeakButton(_sample, tooltip: '试听'),
                )),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text('刚开始用 0.8x 听清每个词，熟练后调到 1.0x 以上。学习时也能随时调：课程页、测验页右上角的语速按钮。',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ),
            Obx(() {
              final problem = tts.problem.value;
              if (problem != null && tts.voices.isEmpty) {
                return _NoVoiceCard(problem: problem, onRetry: tts.loadVoices);
              }
              final selected = progress.voiceId.value;
              return Column(
                children: [
                  _VoiceTile(
                    title: '自动（推荐）',
                    subtitle: tts.defaultVoice == null
                        ? '美式英语'
                        : '${tts.defaultVoice!.accent} · ${tts.defaultVoice!.shortName}',
                    selected: selected == null,
                    onTap: () => _chooseVoice(null),
                  ),
                  for (final voice in tts.voices)
                    _VoiceTile(
                      title: '${voice.accent} · ${voice.shortName}',
                      subtitle: voice.qualityLabel.isEmpty
                          ? voice.language
                          : '${voice.language} · ${voice.qualityLabel}',
                      selected: selected == voice.id,
                      onTap: () => _chooseVoice(voice.id),
                    ),
                  // iPhone 自带的是压缩版声音，比较生硬；增强版要自己在系统设置里下载
                  if (Platform.isIOS)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(72, 4, 16, 8),
                      child: Text(
                          '想要更自然的发音：iPhone「设置 → 辅助功能 → 朗读内容 → 声音 → 英语」，'
                          '下载带「增强」或「高级」的声音，回到这里就能选。',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ),
                  if (Platform.isWindows &&
                      !tts.voices
                          .any((v) => v.language.toLowerCase() == 'en-gb'))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(72, 4, 16, 8),
                      child: Text(
                          '想练英式口音：Windows「设置 → 时间和语言 → 语音 → 添加语音」，'
                          '选 English (United Kingdom)，装好后重启本软件。',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ),
                ],
              );
            }),
            const SectionTitle('显示'),
            Obx(() => ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('字号'),
                  trailing: SegmentedButton<double>(
                    showSelectedIcon: false,
                    segments: [
                      for (final (scale, label) in ProgressService.textScales)
                        ButtonSegment(value: scale, label: Text(label)),
                    ],
                    selected: {progress.textScale.value},
                    onSelectionChanged: (s) => progress.setTextScale(s.first),
                  ),
                )),
            const SectionTitle('学习计划'),
            Obx(() {
              final start = progress.startDate.value;
              return ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(
                    '开始日期 ${start.year}-${_two(start.month)}-${_two(start.day)}'),
                subtitle: Text('今天是学习的第 ${progress.studyDay} 天'),
                trailing: TextButton(
                  onPressed: progress.restartPlanToday,
                  child: const Text('从今天开始'),
                ),
              );
            }),
            ListTile(
              leading: Icon(Icons.restart_alt, color: scheme.error),
              title: Text('重置学习进度', style: TextStyle(color: scheme.error)),
              subtitle: const Text('清除完成记录和测验成绩（生词本和标注保留）'),
              onTap: () => _confirmReset(context),
            ),
            const SectionTitle('关于'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('实用英语'),
              subtitle:
                  Text('${repo.courses.length} 门课 · ${repo.totalLessons} 课 · '
                      '${repo.allWords.length} 个单词词组 · '
                      '${repo.allExchanges.length} 组听说问答\n'
                      '学习记录和标注只保存在本机'),
              isThreeLine: true,
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  void _chooseVoice(String? id) {
    ProgressService.to.setVoice(id);
    TtsService.to.say(_sample);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置学习进度？'),
        content: const Text('所有课程的完成记录和测验成绩会被清除，开始日期改为今天。生词本和标注不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重置')),
        ],
      ),
    );
    if (ok == true) ProgressService.to.resetProgress();
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
        dense: true,
      );
}

/// 手机上没有英文语音引擎时的提示
class _NoVoiceCard extends StatelessWidget {
  const _NoVoiceCard({required this.problem, required this.onRetry});

  final String problem;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final howTo = Platform.isAndroid
        ? '请打开手机「设置」，搜索“文字转语音”，把首选引擎设为支持英语的引擎'
            '（如 Google 语音服务、讯飞语音），并下载英语语音包。'
        : Platform.isIOS
            ? '请打开 iPhone「设置 → 辅助功能 → 朗读内容 → 声音 → 英语」，下载一个英语声音。'
            : '请打开 Windows「设置 → 时间和语言 → 语音」，添加一个英语语音。';
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.volume_off_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text('无法朗读：$problem',
                    style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(howTo, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                  onPressed: onRetry, child: const Text('重新检测')),
            ),
          ],
        ),
      ),
    );
  }
}
