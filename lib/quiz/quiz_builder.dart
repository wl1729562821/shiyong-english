import 'dart:math';

import '../models/lesson.dart';

enum QuestionType {
  /// 听单词，选中文意思
  listenWord('听发音，选出中文意思'),

  /// 看中文，选英文
  zhToEn('看中文，选出对应的英文'),

  /// 听对方说的话，选合适的回答——最接近真实场景的题型
  listenReply('听对方说的话，选出最合适的回答'),

  /// 听一句话，选中文意思
  listenMeaning('听这句话，选出中文意思');

  const QuestionType(this.instruction);

  final String instruction;

  bool get hasAudio => this != zhToEn;
}

class QuizQuestion {
  const QuizQuestion({
    required this.type,
    required this.item,
    required this.options,
    required this.answer,
    this.audio,
    this.prompt,
  });

  final QuestionType type;

  /// 这道题考的条目，答错时加入生词本
  final StudyItem item;

  /// 要播放的英文
  final String? audio;

  /// 题面上显示的文字（看中文选英文时是中文）
  final String? prompt;
  final List<String> options;
  final int answer;

  String get correctOption => options[answer];
}

/// 生成测验题。干扰项优先从和题目同一课的内容里挑：
/// 同一场景的选项更像，才能真正考出“听懂了没有”
class QuizBuilder {
  QuizBuilder({
    required List<Word> allWords,
    required List<Exchange> allExchanges,
    required List<DialogueLine> allLines,
    Random? random,
  })  : _random = random ?? Random(),
        _wordsByLesson = _groupByLesson(allWords),
        _exchangesByLesson = _groupByLesson(allExchanges),
        _linesByLesson = _groupByLesson(allLines),
        _allWords = allWords,
        _allExchanges = allExchanges,
        _allLines = allLines,
        _genericReplies = {
          for (final e in allExchanges)
            if (e.generic) _normalize(e.reply),
        };

  final Random _random;
  final Map<String, List<Word>> _wordsByLesson;
  final Map<String, List<Exchange>> _exchangesByLesson;
  final Map<String, List<DialogueLine>> _linesByLesson;
  final List<Word> _allWords;
  final List<Exchange> _allExchanges;
  final List<DialogueLine> _allLines;

  /// 标了 generic 的回答。别的天有一模一样的回答（比如两处 Thank you.）也按通用处理
  final Set<String> _genericReplies;

  bool _isGeneric(Exchange e) =>
      e.generic || _genericReplies.contains(_normalize(e.reply));

  static Map<String, List<T>> _groupByLesson<T extends StudyItem>(
      List<T> items) {
    final map = <String, List<T>>{};
    for (final item in items) {
      map.putIfAbsent(item.lessonId, () => []).add(item);
    }
    return map;
  }

  /// 从 [items] 里出 [count] 道题，大约一半单词题、一半句子题
  List<QuizQuestion> build(List<StudyItem> items, {int count = 10}) {
    final words = items.whereType<Word>().toList()..shuffle(_random);
    final sentences = items.where((i) => i is! Word).toList()..shuffle(_random);

    var wordCount = min(words.length, (count / 2).round());
    var sentenceCount = min(sentences.length, count - wordCount);
    // 某一类不够时，用另一类补满
    wordCount = min(words.length, count - sentenceCount);

    final questions = <QuizQuestion>[];
    for (var i = 0; i < wordCount; i++) {
      final q = _wordQuestion(words[i], listen: i.isEven);
      if (q != null) questions.add(q);
    }
    for (var i = 0; i < sentenceCount; i++) {
      final item = sentences[i];
      final q = switch (item) {
        // 六成“听问题选回答”，四成“听句子选意思”
        Exchange e when !_isGeneric(e) && i % 5 != 1 && i % 5 != 3 =>
          _replyQuestion(e) ?? _meaningQuestion(e),
        _ => _meaningQuestion(item),
      };
      if (q != null) questions.add(q);
    }
    return questions..shuffle(_random);
  }

  QuizQuestion? _wordQuestion(Word word, {required bool listen}) {
    final pool = [...?_wordsByLesson[word.lessonId], ..._allWords];
    if (listen) {
      return _make(
        type: QuestionType.listenWord,
        item: word,
        audio: word.en,
        correct: word.zh,
        candidates: pool.map((w) => w.zh),
      );
    }
    return _make(
      type: QuestionType.zhToEn,
      item: word,
      prompt: word.zh,
      correct: word.en,
      candidates: pool.map((w) => w.en),
    );
  }

  QuizQuestion? _replyQuestion(Exchange exchange) {
    final pool = [...?_exchangesByLesson[exchange.lessonId], ..._allExchanges]
        .where((e) => !_isGeneric(e));
    return _make(
      type: QuestionType.listenReply,
      item: exchange,
      audio: exchange.hear,
      correct: exchange.reply,
      candidates: pool.map((e) => e.reply),
    );
  }

  QuizQuestion? _meaningQuestion(StudyItem item) {
    final sameDay = [
      ...?_exchangesByLesson[item.lessonId]?.map((e) => e.hearZh),
      ...?_linesByLesson[item.lessonId]?.map((l) => l.zh),
    ];
    final everywhere = [
      ..._allExchanges.map((e) => e.hearZh),
      ..._allLines.map((l) => l.zh),
    ];
    return _make(
      type: QuestionType.listenMeaning,
      item: item,
      audio: item.en,
      correct: item.zh,
      candidates: [...sameDay, ...everywhere],
    );
  }

  /// [candidates] 前面是同一天的，后面是全部的。先在同一天里随机挑 3 个不重复的，
  /// 不够再从全部里挑
  QuizQuestion? _make({
    required QuestionType type,
    required StudyItem item,
    required String correct,
    required Iterable<String> candidates,
    String? audio,
    String? prompt,
  }) {
    final list = candidates.toList();
    final sameDayCount = _countSameDay(type, item);
    final near = list.take(sameDayCount).toList()..shuffle(_random);
    final far = list.skip(sameDayCount).toList()..shuffle(_random);

    final distractors = <String>[];
    for (final option in [...near, ...far]) {
      if (distractors.length == 3) break;
      if (_similar(option, correct) ||
          distractors.any((d) => _similar(d, option))) {
        continue;
      }
      distractors.add(option);
    }
    if (distractors.length < 3) return null;

    final options = [...distractors, correct]..shuffle(_random);
    return QuizQuestion(
      type: type,
      item: item,
      audio: audio,
      prompt: prompt,
      options: options,
      answer: options.indexOf(correct),
    );
  }

  int _countSameDay(QuestionType type, StudyItem item) => switch (type) {
        QuestionType.listenWord ||
        QuestionType.zhToEn =>
          _wordsByLesson[item.lessonId]?.length ?? 0,
        QuestionType.listenReply => _exchangesByLesson[item.lessonId]
                ?.where((e) => !_isGeneric(e))
                .length ??
            0,
        QuestionType.listenMeaning =>
          (_exchangesByLesson[item.lessonId]?.length ?? 0) +
              (_linesByLesson[item.lessonId]?.length ?? 0),
      };

  // 去掉标点后一个包含另一个就算太像，不能同时当选项：
  // “给您。”和“好的，给您。”都能当 Sure, here you are. 的意思；
  // check in 和 check-in counter 也容易让人觉得两个都对
  static bool _similar(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    return na.contains(nb) || nb.contains(na);
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.,!?。，！？、；;：:“”"‘’（）()…-]'), '');
}
