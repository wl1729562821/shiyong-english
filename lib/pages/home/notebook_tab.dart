import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../services/progress_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';
import '../quiz/quiz_page.dart';

/// 生词本 + 我的标注，顶部切换
class NotebookTab extends StatefulWidget {
  const NotebookTab({super.key});

  @override
  State<NotebookTab> createState() => _NotebookTabState();
}

class _NotebookTabState extends State<NotebookTab> {
  bool _annotations = false;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.star_outline_rounded),
                    label: Text('生词本 ${progress.notebook.length}')),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.edit_note),
                    label: Text('我的标注 ${progress.annotations.length}')),
              ],
              selected: {_annotations},
              onSelectionChanged: (s) => setState(() => _annotations = s.first),
            )),
      ),
      body: _annotations ? const _AnnotationList() : const _VocabList(),
    );
  }
}

/// 生词本：手动收藏的 + 测验答错的。答错次数多的排在前面
class _VocabList extends StatelessWidget {
  const _VocabList();

  static List<(StudyItem, NoteEntry)> sortedItems() {
    final repo = LessonRepository.to;
    final items = <(StudyItem, NoteEntry)>[];
    ProgressService.to.notebook.forEach((key, entry) {
      final item = repo.find(key);
      if (item != null) items.add((item, entry));
    });
    items.sort((a, b) {
      final byWrong = b.$2.wrongCount.compareTo(a.$2.wrongCount);
      return byWrong != 0 ? byWrong : b.$2.addedAt.compareTo(a.$2.addedAt);
    });
    return items;
  }

  static Future<void> _playAll(List<(StudyItem, NoteEntry)> items) async {
    final tts = TtsService.to;
    final seq = tts.beginSequence();
    for (final (item, _) in items) {
      if (!await tts.sayInSequence(seq, item.en)) break;
      if (item is Exchange) {
        if (!await tts.pause(seq, const Duration(milliseconds: 500))) break;
        if (!await tts.sayInSequence(seq, item.reply)) break;
      }
      if (!await tts.pause(seq, const Duration(milliseconds: 900))) break;
    }
    tts.endSequence(seq);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tts = TtsService.to;
    return Obx(() {
      final items = sortedItems();
      if (items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline_rounded,
                    size: 64, color: scheme.outline),
                const SizedBox(height: 12),
                Text('还没有生词', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('学习时点 ☆ 收藏单词和句子；\n测验答错的会自动加进来。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      }
      return MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text('共 ${items.length} 条',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  tts.sequenceRunning.value
                      ? OutlinedButton.icon(
                          onPressed: tts.stop,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('停止'))
                      : OutlinedButton.icon(
                          onPressed: () => _playAll(items),
                          icon: const Icon(Icons.playlist_play_rounded),
                          label: const Text('全部播放')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Get.to(() => QuizPage(
                          title: '生词本复习',
                          items: [for (final (item, _) in items) item],
                          count: items.length.clamp(1, 15),
                        )),
                    icon: const Icon(Icons.quiz_outlined),
                    label: const Text('复习测验'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final (item, entry) = items[i];
                  return _NoteTile(item: item, entry: entry);
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.item, required this.entry});

  final StudyItem item;
  final NoteEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ProgressService.to;
    final exchange = item is Exchange ? item as Exchange : null;
    return Dismissible(
      key: ValueKey(item.key),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        progress.removeNote(item.key);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('已移出：${item.en}'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => progress.restoreNote(item.key, entry),
            ),
          ));
      },
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(item.en,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (entry.wrongCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('错 ${entry.wrongCount} 次',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onErrorContainer)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.zh),
            if (exchange != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => TtsService.to.say(exchange.reply),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('↳ ${exchange.reply}',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w500)),
                    ),
                    Icon(Icons.volume_up_outlined,
                        size: 18, color: scheme.primary),
                  ],
                ),
              ),
              Text('   ${exchange.replyZh}'),
            ],
            Text(LessonRepository.to.sourceOf(item),
                style: TextStyle(fontSize: 12, color: scheme.outline)),
            AnnotationView(item.key, title: '${item.en}  ${item.zh}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnnotationButton(item.key, title: '${item.en}  ${item.zh}'),
            SpeakButton(item.en),
          ],
        ),
        onTap: () => TtsService.to.say(item.en),
      ),
    );
  }
}

/// 我的标注：所有加过标注的单词和句子，最近改的在前面；可以一键复制成文本
class _AnnotationList extends StatelessWidget {
  const _AnnotationList();

  static List<(StudyItem, Annotation)> sortedItems() {
    final repo = LessonRepository.to;
    final items = <(StudyItem, Annotation)>[];
    ProgressService.to.annotations.forEach((key, annotation) {
      final item = repo.find(key);
      if (item != null) items.add((item, annotation));
    });
    items.sort((a, b) => b.$2.updatedAt.compareTo(a.$2.updatedAt));
    return items;
  }

  /// 复制出来的格式：英文 / 中文 / 标注，每条之间空一行，方便贴到笔记软件
  static String asText(List<(StudyItem, Annotation)> items) => [
        for (final (item, annotation) in items)
          [
            item.en,
            item.zh,
            if (item is Exchange) '↳ ${item.reply}  ${item.replyZh}',
            '标注：${annotation.text}',
          ].join('\n'),
      ].join('\n\n');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final items = sortedItems();
      if (items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note, size: 64, color: scheme.outline),
                const SizedBox(height: 12),
                Text('还没有标注', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('学习时点单词、问答、对话旁边的 ✎ 图标，\n就能写下自己的标注，比如谐音、例句、什么时候用。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      }
      return MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text('共 ${items.length} 条',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: asText(items)));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                            content: Text('已复制 ${items.length} 条标注，可以粘贴到笔记里')));
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('全部复制'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final (item, _) = items[i];
                  final title = '${item.en}  ${item.zh}';
                  return ListTile(
                    title: Text(item.en,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.zh),
                        if (item is Exchange)
                          Text('↳ ${item.reply}  ${item.replyZh}',
                              style: TextStyle(color: scheme.primary)),
                        Text(LessonRepository.to.sourceOf(item),
                            style:
                                TextStyle(fontSize: 12, color: scheme.outline)),
                        AnnotationView(item.key, title: title),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnnotationButton(item.key, title: title),
                        SpeakButton(item.en),
                      ],
                    ),
                    onTap: () => TtsService.to.say(item.en),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}
