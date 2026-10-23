import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../services/progress_service.dart';
import '../../widgets/common.dart';
import '../lesson/lesson_page.dart';

/// 课程页：顶部总进度 + 课程切换（基础入门 / 日常沟通 / 旅行出行）+ 学习方法 + 当前课程按阶段分组的每一课
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  /// 把阶段分到左右两栏，每次放进课数少的那栏，两栏高度差不多
  static (List<Phase>, List<Phase>) splitColumns(List<Phase> phases) {
    final left = <Phase>[], right = <Phase>[];
    var l = 0, r = 0;
    for (final p in phases) {
      final n = p.to - p.from + 1;
      if (l <= r) {
        left.add(p);
        l += n;
      } else {
        right.add(p);
        r += n;
      }
    }
    return (left, right);
  }

  @override
  Widget build(BuildContext context) {
    final repo = LessonRepository.to;
    final progress = ProgressService.to;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          // 读一下这几个 Rx，进度变化或切换课程时整页刷新
          progress.completed.length;
          progress.bestScores.length;
          progress.annotations.length;
          progress.startDate.value;
          final course = repo.course(progress.courseId.value);
          Widget section(Phase p) => _PhaseSection(
                phase: p,
                lessons: [
                  for (var d = p.from; d <= p.to; d++) repo.lesson(course.id, d)
                ],
                progress: progress,
              );

          return LayoutBuilder(builder: (context, box) {
            if (box.maxWidth >= kTwoColumnWidth) {
              // 桌面宽窗口：进度卡片 + 学习方法并排，课程切换一整行，阶段分左右两栏
              final (left, right) = splitColumns(course.phases);
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  MaxWidth(
                    width: 1160,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                              flex: 5,
                              child: _Header(
                                  repo: repo,
                                  progress: progress,
                                  course: course)),
                          const Expanded(
                              flex: 4,
                              child: _RoutineCard(expanded: true, top: 12)),
                        ],
                      ),
                    ),
                  ),
                  MaxWidth(
                      width: 1160,
                      child: _CourseSwitcher(repo: repo, progress: progress)),
                  MaxWidth(
                    width: 1160,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Column(
                                children: [for (final p in left) section(p)])),
                        Expanded(
                            child: Column(
                                children: [for (final p in right) section(p)])),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                MaxWidth(
                    child: _Header(
                        repo: repo, progress: progress, course: course)),
                MaxWidth(
                    child: _CourseSwitcher(repo: repo, progress: progress)),
                const MaxWidth(child: _RoutineCard()),
                for (final phase in course.phases)
                  MaxWidth(child: section(phase)),
              ],
            );
          });
        }),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.repo, required this.progress, required this.course});

  final LessonRepository repo;
  final ProgressService progress;
  final Course course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = progress.completed.length;
    final total = repo.totalLessons;
    final next = progress.nextLesson(course);
    final courseDone = progress.completedIn(course) == course.totalDays;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF26A69A), Color(0xFF4DB6AC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // 桌面宽屏时卡片被拉高到和右边一样高，内容上下撑开
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          // 分三组（标题 / 进度 / 按钮），拉高时只在组之间留空
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('实用英语',
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text([for (final c in repo.courses) c.title].join(' → '),
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                Row(
                  children: [
                    _Stat(value: '$done/$total', label: '已完成'),
                    _Stat(value: '第 ${progress.studyDay} 天', label: '学习天数'),
                    _Stat(value: '${progress.notebook.length}', label: '生词本'),
                    _Stat(value: '${progress.annotations.length}', label: '标注'),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: done / total,
                    minHeight: 6,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF00695C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Get.to(
                    () => LessonPage(courseId: course.id, day: next.day)),
                icon:
                    Icon(courseDone ? Icons.replay : Icons.play_arrow_rounded),
                label: Text(
                  courseDone
                      ? '${course.title}已全部完成！复习第 ${next.day} 课'
                      : '继续学习 · ${course.title} 第 ${next.day} 课 ${next.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 几门课的切换卡片：图标、名称、完成进度
class _CourseSwitcher extends StatelessWidget {
  const _CourseSwitcher({required this.repo, required this.progress});

  final LessonRepository repo;
  final ProgressService progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      // IntrinsicHeight + stretch：几张卡片一样高（副标题行数不同也对齐）
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, course) in repo.courses.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _CourseCard(
                    key: ValueKey('course-${course.id}'),
                    index: i + 1,
                    course: course,
                    done: progress.completedIn(course),
                    selected: progress.courseId.value == course.id,
                    onTap: () => progress.setCourse(course.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    super.key,
    required this.index,
    required this.course,
    required this.done,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final Course course;
  final int done;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(lessonIcon(course.icon),
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const Spacer(),
                Text('$done/${course.totalDays}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary)),
              ]),
              const SizedBox(height: 6),
              Text('$index. ${course.title}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selected ? scheme.onPrimaryContainer : null)),
              Expanded(
                child: Text(course.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: done / course.totalDays,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
}

/// 每天的学习流程
class _RoutineCard extends StatelessWidget {
  const _RoutineCard({this.expanded = false, this.top = 8});

  /// 桌面宽屏时默认展开，和进度卡片并排
  final bool expanded;
  final double top;

  static const _steps = [
    ('单词', '先点播放听发音，猜意思，再看中文；每个词跟读 2 遍', '10 分钟'),
    ('听说', '打开“盲听模式”：先听对方的话，自己大声说出回答，再看答案', '15 分钟'),
    ('对话', '先听完整对话，再用“角色扮演”：轮到你时看中文说英文', '10 分钟'),
    ('测验', '正确率 ≥ 80% 自动完成这一课；答错的自动进生词本', '5 分钟'),
    ('复习', '学新课前，把生词本和自己的标注过一遍', '5 分钟'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      for (final (i, step) in _steps.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primaryContainer,
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${step.$1}  ',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: step.$2),
                ])),
              ),
              const SizedBox(width: 8),
              Text(step.$3,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
    ];
    const title = Text('每课怎么学（约 45 分钟）');
    const subtitle = Text('目标：听懂对方，并用简单的话回答');
    final icon = Icon(Icons.tips_and_updates_outlined, color: scheme.primary);

    return Card(
      margin: EdgeInsets.fromLTRB(16, top, 16, 8),
      clipBehavior: Clip.antiAlias,
      // 桌面宽屏：一直展开，用普通 Column。外面套了 IntrinsicHeight，
      // ExpansionTile 里的 ListTile 算出的固有高度在字号放大时偏小，会溢出
      child: expanded
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    icon,
                    const SizedBox(width: 16),
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.titleMedium,
                        child: title,
                      ),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      child: subtitle,
                    ),
                  ),
                  ...steps,
                ],
              ),
            )
          : ExpansionTile(
              leading: icon,
              title: title,
              subtitle: subtitle,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: steps,
            ),
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({
    required this.phase,
    required this.lessons,
    required this.progress,
  });

  final Phase phase;
  final List<Lesson> lessons;
  final ProgressService progress;

  @override
  Widget build(BuildContext context) {
    final color = Color(phase.colorValue);
    final done = lessons.where((l) => progress.isCompleted(l.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Row(
            children: [
              Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              // 放在 Expanded 里：大字号的手机上一行放不下时换行，不溢出
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${phase.name}  ',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  TextSpan(
                      text: '第 ${phase.from}–${phase.to} 课',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13)),
                ])),
              ),
              Text('$done/${lessons.length}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, lesson) in lessons.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 72),
                _DayTile(lesson: lesson, color: color, progress: progress),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile(
      {required this.lesson, required this.color, required this.progress});

  final Lesson lesson;
  final Color color;
  final ProgressService progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completed = progress.isCompleted(lesson.id);
    final course = LessonRepository.to.course(lesson.course);
    final isNext = !completed && progress.nextLesson(course) == lesson;
    final score = progress.bestScores[lesson.id];
    final subtitle = lesson.isReview
        ? '复习第 ${lesson.reviewFrom}–${lesson.reviewTo} 课 · 全流程模拟'
        : '${lesson.words.length} 词 · ${lesson.exchanges.length} 组问答 · 对话';

    return ListTile(
      key: ValueKey('lesson-${lesson.course}-${lesson.day}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: completed ? color : color.withValues(alpha: 0.12),
        foregroundColor: completed ? Colors.white : color,
        child: completed
            ? const Icon(Icons.check_rounded)
            : Icon(lessonIcon(lesson.icon), size: 22),
      ),
      title: Text('第 ${lesson.day} 课  ${lesson.title}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${lesson.en}\n$subtitle',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      isThreeLine: true,
      trailing: isNext
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('下一课',
                  style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
            )
          : score != null
              ? Text('$score分',
                  style: TextStyle(
                      color: score >= ProgressService.passScore
                          ? color
                          : scheme.error,
                      fontWeight: FontWeight.bold))
              : const Icon(Icons.chevron_right),
      onTap: () =>
          Get.to(() => LessonPage(courseId: lesson.course, day: lesson.day)),
    );
  }
}
