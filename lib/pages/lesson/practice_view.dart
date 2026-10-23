import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/lesson.dart';
import '../../services/progress_service.dart';
import '../../widgets/common.dart';
import '../quiz/quiz_page.dart';
import 'lesson_controller.dart';
import 'lesson_page.dart';

/// 测验标签：完成状态、开始测验、当天任务清单
class PracticeView extends StatelessWidget {
  const PracticeView({super.key, required this.c});

  final LessonController c;

  /// 当天测验的出题范围。复习日再加上模拟对话里对方说的话
  static List<StudyItem> quizItems(LessonController c) => [
        ...c.words,
        ...c.exchanges,
        if (c.lesson.isReview) ...c.lines.where((l) => !l.isMe),
      ];

  /// 打开当天的测验（按钮和桌面快捷键 Enter 共用）
  static void startQuiz(LessonController c) {
    final lesson = c.lesson;
    Get.to(() => QuizPage(
          title: '${c.course.title} 第 ${lesson.day} 课 测验',
          items: quizItems(c),
          count: lesson.isReview ? 15 : 10,
          lessonId: lesson.id,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ProgressService.to;
    final lesson = c.lesson;
    final count = lesson.isReview ? 15 : 10;

    return MaxWidth(
      child: Obx(() {
        final done = progress.isCompleted(lesson.id);
        final best = progress.bestScores[lesson.id];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color:
                  done ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(done ? Icons.verified_rounded : Icons.quiz_outlined,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(done ? '第 ${lesson.day} 课已完成' : '测验 $count 题',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      best == null
                          ? '正确率达到 ${ProgressService.passScore}% 自动完成今天的学习'
                          : '最高分 $best 分',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => startQuiz(c),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(best == null ? '开始测验' : '再测一次'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SectionTitle('今天的任务'),
            ..._tasks(lesson).map((t) => ListTile(
                  dense: true,
                  leading:
                      Icon(Icons.check_circle_outline, color: scheme.primary),
                  title: Text(t),
                )),
            const SizedBox(height: 8),
            if (done && lesson.day < c.course.totalDays)
              FilledButton.tonalIcon(
                onPressed: () => Get.off(() =>
                    LessonPage(courseId: lesson.course, day: lesson.day + 1)),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text('进入第 ${lesson.day + 1} 课'),
              ),
            TextButton(
              onPressed: () => progress.setCompleted(lesson.id, !done),
              child: Text(done ? '取消完成标记' : '不测验，直接标记为已完成'),
            ),
          ],
        );
      }),
    );
  }

  static List<String> _tasks(Lesson lesson) => lesson.isReview
      ? [
          '生词本：全部播放一遍，再做“复习测验”',
          '单词 / 听说：打开遮挡，过一遍第 ${lesson.reviewFrom}–${lesson.reviewTo} 课的内容',
          '对话：全流程模拟，用角色扮演完整走一遍',
          '复习测验 15 题，正确率 ≥ 80%',
        ]
      : [
          '单词：听发音 → 猜意思 → 看中文，每个词跟读 2 遍',
          '听说：打开盲听模式，听到问题后大声说出回答',
          '对话：先听完整对话，再角色扮演一遍',
          '测验 10 题，正确率 ≥ 80%',
        ];
}
