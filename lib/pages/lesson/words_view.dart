import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';
import 'lesson_controller.dart';

/// 单词标签：今日目标 + 学习提示 + 单词列表
class WordsView extends StatelessWidget {
  const WordsView({super.key, required this.c});

  final LessonController c;

  @override
  Widget build(BuildContext context) {
    final lesson = c.lesson;
    final repo = LessonRepository.to;
    // 复习日按天分组显示
    final rows = <Object>[];
    int? lastDay;
    for (final word in c.words) {
      if (lesson.isReview && word.day != lastDay) {
        rows.add(word.day);
        lastDay = word.day;
      }
      rows.add(word);
    }

    return MaxWidth(
      child: Column(
        children: [
          PlayBar(
            left: Obx(() => FilterChip(
                  avatar: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('遮住中文'),
                  selected: c.hideZh.value,
                  onSelected: (_) => c.toggleHideZh(),
                )),
            onPlay: c.playWords,
            playLabel: '全部播放',
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return GoalCard(lesson: lesson, wordCount: c.words.length);
                }
                final row = rows[i - 1];
                if (row is int) {
                  return SectionTitle(
                      '第 $row 课  ${repo.lesson(c.courseId, row).title}');
                }
                return _WordTile(word: row as Word, c: c);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({required this.word, required this.c});

  final Word word;
  final LessonController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final active = TtsService.to.speaking.value == word.en;
      final hidden = c.hideZh.value && !c.isRevealed(word.key);
      return ListTile(
        tileColor:
            active ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
        leading: SpeakButton(word.en),
        title: Text(word.en,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            hidden ? const HiddenText() : Text(word.zh),
            // 遮住中文时标注也先不显示（标注里常常写着意思）
            if (!hidden)
              AnnotationView(word.key, title: '${word.en}  ${word.zh}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnnotationButton(word.key, title: '${word.en}  ${word.zh}'),
            NoteButton(word.key),
          ],
        ),
        onTap: () {
          c.reveal(word.key);
          TtsService.to.say(word.en);
        },
      );
    });
  }
}

/// 页面顶部的操作条：左边一个开关，右边“全部播放 / 停止”
class PlayBar extends StatelessWidget {
  const PlayBar({
    super.key,
    required this.left,
    required this.onPlay,
    required this.playLabel,
  });

  final Widget left;
  final VoidCallback onPlay;
  final String playLabel;

  @override
  Widget build(BuildContext context) {
    final tts = TtsService.to;
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        // Wrap：大字号的窄屏上放不下时，播放按钮换到下一行。
        // 外面撑满整行，spaceBetween 才能把两边推开（否则 Wrap 只有内容那么宽，被居中）
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              left,
              Obx(() => tts.sequenceRunning.value
                  ? FilledButton.tonalIcon(
                      onPressed: tts.stop,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('停止'),
                    )
                  : FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(isDesktop ? '$playLabel（空格）' : playLabel),
                    )),
            ],
          ),
        ));
  }
}

/// 今日目标和学习提示
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.lesson, required this.wordCount});

  final Lesson lesson;
  final int wordCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: scheme.secondaryContainer.withValues(alpha: 0.6),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.flag_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              const Text('今日目标', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(lesson.en,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(lesson.goal),
            if (lesson.isReview) ...[
              const SizedBox(height: 6),
              Text(
                  '下面是第 ${lesson.reviewFrom}–${lesson.reviewTo} 课的全部 $wordCount 个单词词组。',
                  style: TextStyle(color: scheme.primary)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.lightbulb_outline,
                  size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 6),
              const Text('学习提示', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            for (final tip in lesson.tips)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                        child: Text(tip, style: const TextStyle(height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
