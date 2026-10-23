import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../quiz/quiz_builder.dart';
import '../../services/progress_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';

class QuizController extends GetxController {
  QuizController({required this.items, required this.count, this.lessonId});

  final List<StudyItem> items;
  final int count;

  /// 课程测验时是哪一课（Lesson.id），达标后标记完成；生词本复习时为 null
  final String? lessonId;

  final _tts = TtsService.to;
  final _progress = ProgressService.to;

  final questions = <QuizQuestion>[].obs;
  final index = 0.obs;

  /// 当前题选了哪个选项，null = 还没答
  final selected = RxnInt();
  final correctCount = 0.obs;
  final wrong = <QuizQuestion>[].obs;
  final finished = false.obs;
  int score = 0;
  bool justCompleted = false;

  QuizQuestion get current => questions[index.value];

  @override
  void onInit() {
    super.onInit();
    restart();
  }

  @override
  void onClose() {
    // onClose 是在页面 dispose 里调的，这时 widget 树是锁住的；stop() 会改
    // speaking 等 Rx，触发别的页面上的 Obx 重建就会报 “widget tree was locked”。
    // 放到微任务里，等这一帧结束再停
    Future.microtask(_tts.stop);
    super.onClose();
  }

  void restart() {
    final repo = LessonRepository.to;
    questions.assignAll(QuizBuilder(
      allWords: repo.allWords,
      allExchanges: repo.allExchanges,
      allLines: repo.allLines,
    ).build(items, count: count));
    index.value = 0;
    selected.value = null;
    correctCount.value = 0;
    wrong.clear();
    finished.value = false;
    justCompleted = false;
    _autoPlay();
  }

  void _autoPlay() {
    if (questions.isEmpty) return;
    final audio = current.audio;
    if (audio != null) {
      // 等页面切换动画结束再读，不然开头会被吞掉
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!isClosed &&
            questions.isNotEmpty &&
            current.audio == audio &&
            selected.value == null) {
          _tts.say(audio);
        }
      });
    }
  }

  void play({double? speed}) {
    final audio = current.audio;
    if (audio != null) _tts.say(audio, speed: speed);
  }

  void choose(int option) {
    if (selected.value != null) return;
    selected.value = option;
    final q = current;
    if (option == q.answer) {
      correctCount.value++;
    } else {
      wrong.add(q);
      _progress.addWrong(q.item.key);
    }
    // 答完读一遍正确的英文，加深印象
    _tts.say(switch (q.type) {
      QuestionType.listenReply || QuestionType.zhToEn => q.correctOption,
      _ => q.audio!,
    });
  }

  void next() {
    _tts.stop();
    if (index.value + 1 < questions.length) {
      selected.value = null;
      index.value++;
      _autoPlay();
      return;
    }
    score = (correctCount.value * 100 / questions.length).round();
    if (lessonId != null) {
      justCompleted = _progress.recordQuiz(lessonId!, score);
    }
    finished.value = true;
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.title,
    required this.items,
    required this.count,
    this.lessonId,
  });

  final String title;
  final List<StudyItem> items;
  final int count;
  final String? lessonId;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final String _tag = 'quiz-${identityHashCode(this)}';
  late final QuizController _c = Get.put(
    QuizController(
        items: widget.items, count: widget.count, lessonId: widget.lessonId),
    tag: _tag,
  );

  @override
  void dispose() {
    Get.delete<QuizController>(tag: _tag);
    super.dispose();
  }

  bool get _answering => _c.questions.isNotEmpty && !_c.finished.value;

  void _choose(int i) {
    if (_answering && i < _c.current.options.length) _c.choose(i);
  }

  void _enter() {
    if (_answering && _c.selected.value != null) _c.next();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        for (var i = 0; i < 4; i++) ...{
          SingleActivator(
                  LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)):
              () => _choose(i),
          SingleActivator(
                  LogicalKeyboardKey(LogicalKeyboardKey.numpad1.keyId + i)):
              () => _choose(i),
        },
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (_answering) _c.play();
        },
        const SingleActivator(LogicalKeyboardKey.keyS): () {
          if (_answering) _c.play(speed: 0.6);
        },
        const SingleActivator(LogicalKeyboardKey.enter): _enter,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _enter,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      };

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(autofocus: true, child: _buildPage(context)),
    );
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Obx(() => _c.finished.value || _c.questions.isEmpty
              ? const SizedBox()
              : Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                      child: Text(
                          '${_c.index.value + 1} / ${_c.questions.length}')),
                )),
        ],
      ),
      body: MaxWidth(
        child: Obx(() {
          if (_c.questions.isEmpty) {
            return const Center(child: Text('内容太少，出不了题'));
          }
          if (_c.finished.value) return _ResultView(c: _c);
          return _QuestionView(key: ValueKey(_c.index.value), c: _c);
        }),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({super.key, required this.c});

  final QuizController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = c.current;
    return Obx(() {
      final selected = c.selected.value;
      final answered = selected != null;
      return Column(
        children: [
          LinearProgressIndicator(
              value: (c.index.value + (answered ? 1 : 0)) / c.questions.length),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(q.type.instruction,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                _PromptCard(c: c, question: q, answered: answered),
                const SizedBox(height: 16),
                for (var i = 0; i < q.options.length; i++)
                  _OptionTile(
                    key: ValueKey('option-$i'),
                    number: i + 1,
                    text: q.options[i],
                    state: !answered
                        ? _OptionState.idle
                        : i == q.answer
                            ? _OptionState.correct
                            : i == selected
                                ? _OptionState.wrong
                                : _OptionState.dim,
                    onTap: () => c.choose(i),
                  ),
                if (answered)
                  _Explanation(question: q, correct: selected == q.answer),
                if (isDesktop)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      answered
                          ? '快捷键：Enter 下一题'
                          : '快捷键：1–4 选择 · 空格 再听一遍 · S 慢速',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
              ],
            ),
          ),
          if (answered)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: c.next,
                    child: Text(c.index.value + 1 < c.questions.length
                        ? '下一题'
                        : '查看结果'),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard(
      {required this.c, required this.question, required this.answered});

  final QuizController c;
  final QuizQuestion question;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audio = question.audio;
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            if (audio != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Obx(() {
                    final playing = TtsService.to.speaking.value == audio;
                    return IconButton.filled(
                      iconSize: 40,
                      padding: const EdgeInsets.all(16),
                      tooltip: '再听一遍',
                      onPressed: () => c.play(),
                      icon: Icon(
                          playing ? Icons.graphic_eq : Icons.volume_up_rounded),
                    );
                  }),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => c.play(speed: 0.6),
                    icon: const Icon(Icons.slow_motion_video, size: 18),
                    label: const Text('慢速'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 听力题答完才显示原文
              answered
                  ? Text(audio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600))
                  : const HiddenText(label: '答完后显示原文'),
            ] else
              Text(question.prompt ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

enum _OptionState { idle, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.number,
    required this.text,
    required this.state,
    required this.onTap,
  });

  /// 选项编号，桌面上显示出来，对应快捷键 1–4
  final int number;
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (border, bg, icon) = switch (state) {
      _OptionState.correct => (
          Colors.green.shade600,
          Colors.green.shade50,
          Icons.check_circle
        ),
      _OptionState.wrong => (scheme.error, scheme.errorContainer, Icons.cancel),
      _ => (scheme.outlineVariant, null, null),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: bg ?? scheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
              color: border, width: state == _OptionState.idle ? 1 : 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: state == _OptionState.idle ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (isDesktop)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('$number',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scheme.outline)),
                  ),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            state == _OptionState.dim ? scheme.outline : null,
                      )),
                ),
                if (icon != null) Icon(icon, color: border),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 答完后的讲解：把这道题对应的英文和中文都给出来
class _Explanation extends StatelessWidget {
  const _Explanation({required this.question, required this.correct});

  final QuizQuestion question;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = question.item;
    final rows = <(String, String, String)>[
      if (item is Exchange) ...[
        ('对方说', item.hear, item.hearZh),
        ('你回答', item.reply, item.replyZh),
      ] else
        ('', item.en, item.zh),
    ];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(correct ? '答对了！' : '答错了，已加入生词本',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: correct ? Colors.green.shade700 : scheme.error)),
            for (final (label, en, zh) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (label.isNotEmpty)
                            Text(label,
                                style: TextStyle(
                                    fontSize: 12, color: scheme.primary)),
                          Text(en,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(zh,
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    SpeakButton(en),
                  ],
                ),
              ),
            AnnotationView(item.key, title: '${item.en}  ${item.zh}'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => editAnnotation(context, item.key,
                    title: '${item.en}  ${item.zh}'),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Obx(() => Text(
                    ProgressService.to.annotations.containsKey(item.key)
                        ? '修改标注'
                        : '加标注')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.c});

  final QuizController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = c.score >= ProgressService.passScore;
    final message = c.lessonId == null
        ? (passed ? '复习得不错！' : '错的题已经记在生词本里，多听几遍再来')
        : c.justCompleted
            ? '太棒了！这一课完成 ✓'
            : passed
                ? '通过！这一课已完成'
                : '再练练，${ProgressService.passScore} 分以上算完成';
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: c.score / 100,
                      strokeWidth: 10,
                      color: passed ? Colors.green.shade600 : scheme.error,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    Center(
                      child: Text('${c.score}',
                          style: const TextStyle(
                              fontSize: 44, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            Text('答对 ${c.correctCount.value} / ${c.questions.length} 题',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (c.wrong.isNotEmpty) ...[
              const SectionTitle('答错的（已加入生词本）'),
              for (final q in c.wrong)
                ListTile(
                  title: Text(q.item.en,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(q.item is Exchange
                      ? '${q.item.zh}\n↳ ${(q.item as Exchange).reply}'
                      : q.item.zh),
                  trailing: SpeakButton(q.item.en),
                ),
            ],
          ],
        ),
      ),
      // 按钮固定在底部，答错的题很多时也不用滚到最后
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: c.restart, child: const Text('再测一次')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: Get.back, child: const Text('返回')),
            ),
          ]),
        ),
      ),
    ]);
  }
}
