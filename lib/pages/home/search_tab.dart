import 'package:flutter/material.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../services/progress_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';

/// 搜索结果里的一句话
class SearchEntry {
  const SearchEntry({
    required this.en,
    required this.zh,
    required this.item,
    required this.label,
    required this.noteKey,
  });

  final String en;
  final String zh;

  /// 出自哪个条目（用来标出处：哪门课第几课）
  final StudyItem item;

  /// 单词 / 对方说 / 我回答 / 对话
  final String label;

  /// 收藏和标注用的键。一组问答的两句共用一个键
  final String noteKey;
}

/// 速查：输入中文或英文（也能搜自己写的标注），找到能直接说的句子，点一下就读出来
class SearchTab extends StatefulWidget {
  const SearchTab({super.key, this.focusNode});

  /// 首页用它在按 Ctrl+F 时把光标放进搜索框
  final FocusNode? focusNode;

  /// 把所有单词、问答、对话拍平成一句句，英文相同的只保留第一次出现的
  static List<SearchEntry> buildIndex(LessonRepository repo) {
    final seen = <String>{};
    final entries = <SearchEntry>[];
    void add(String en, String zh, StudyItem item, String label) {
      if (seen.add(en.toLowerCase())) {
        entries.add(SearchEntry(
            en: en, zh: zh, item: item, label: label, noteKey: item.key));
      }
    }

    for (final lesson in repo.allLessons) {
      for (final w in lesson.words) {
        add(w.en, w.zh, w, '单词');
      }
      for (final e in lesson.exchanges) {
        add(e.hear, e.hearZh, e, '对方说');
        add(e.reply, e.replyZh, e, '我回答');
      }
      for (final l in lesson.dialogue.lines) {
        add(l.en, l.zh, l, l.isMe ? '我说' : '对方说');
      }
    }
    return entries;
  }

  /// [courseId] 为 null 表示全部课程；[annotationOf] 用来顺便搜自己写的标注
  static List<SearchEntry> filter(
    List<SearchEntry> index,
    String query,
    String? courseId, {
    String? Function(String key)? annotationOf,
  }) {
    final q = query.trim().toLowerCase();
    return index
        .where((e) => courseId == null || e.item.course == courseId)
        .where((e) =>
            q.isEmpty ||
            e.en.toLowerCase().contains(q) ||
            e.zh.contains(q) ||
            (annotationOf?.call(e.noteKey)?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  static const _suggestions = [
    '你好',
    '天气',
    '咖啡',
    '超市',
    '看病',
    '打电话',
    '抱歉',
    '帮忙',
    '多少钱',
    '刷卡',
    '护照',
    '酒店',
    '再说一遍',
    '慢一点',
  ];

  final _controller = TextEditingController();
  late final List<SearchEntry> _index =
      SearchTab.buildIndex(LessonRepository.to);

  /// 只看某一门课，null = 全部
  String? _courseId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text;
    final showHint = query.trim().isEmpty && _courseId == null;
    final results = showHint
        ? const <SearchEntry>[]
        : SearchTab.filter(_index, query, _courseId,
            annotationOf: ProgressService.to.annotationOf);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '输入中文、英文或自己的标注，例如：天气、护照、delay',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _search('')),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final course in [null, ...LessonRepository.to.courses])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(course?.title ?? '全部'),
                          selected: _courseId == course?.id,
                          onSelected: (_) =>
                              setState(() => _courseId = course?.id),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: showHint
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('遇到想说的话，搜一下就能找到可以直接说的句子，点一下就读出来。也会搜你写的标注。',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 16),
                          const Text('常用搜索',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in _suggestions)
                                ActionChip(
                                    label: Text(s),
                                    onPressed: () => _search(s)),
                            ],
                          ),
                        ],
                      )
                    : results.isEmpty
                        ? Center(
                            child: Text('没有找到“$query”',
                                style:
                                    TextStyle(color: scheme.onSurfaceVariant)))
                        : ListView.separated(
                            itemCount: results.length + 1,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) => i == 0
                                ? Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                    child: Text('共 ${results.length} 条',
                                        style: TextStyle(
                                            color: scheme.onSurfaceVariant)),
                                  )
                                : _ResultTile(entry: results[i - 1]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.entry});

  final SearchEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = LessonRepository.to.sourceOf(entry.item);
    final title = '${entry.item.en}  ${entry.item.zh}';
    return ListTile(
      title:
          Text(entry.en, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.zh),
          Text('${entry.label} · $source',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
          AnnotationView(entry.noteKey, title: title),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpeakButton(entry.en),
          AnnotationButton(entry.noteKey, title: title),
          NoteButton(entry.noteKey),
        ],
      ),
      onTap: () => TtsService.to.say(entry.en),
    );
  }
}
