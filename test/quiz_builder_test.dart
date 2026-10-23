import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_english/data/lesson_repository.dart';
import 'package:travel_english/models/lesson.dart';
import 'package:travel_english/quiz/quiz_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LessonRepository repo;

  setUpAll(() async {
    repo = await LessonRepository.load();
  });

  QuizBuilder builder(int seed) => QuizBuilder(
        allWords: repo.allWords,
        allExchanges: repo.allExchanges,
        allLines: repo.allLines,
        random: Random(seed),
      );

  String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.,!?。，！？、；;：:“”"‘’（）()…-]'), '');

  void checkQuestion(QuizQuestion q) {
    expect(q.options, hasLength(4));
    expect(q.answer, inInclusiveRange(0, 3));
    // 四个选项互相不能太像（一个包含另一个）
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        final a = normalize(q.options[i]);
        final b = normalize(q.options[j]);
        expect(a.contains(b) || b.contains(a), isFalse,
            reason: '${q.options[i]} / ${q.options[j]}');
      }
    }
    switch (q.type) {
      case QuestionType.listenWord:
        expect(q.correctOption, q.item.zh);
        expect(q.audio, q.item.en);
      case QuestionType.zhToEn:
        expect(q.correctOption, q.item.en);
        expect(q.prompt, q.item.zh);
      case QuestionType.listenReply:
        final e = q.item as Exchange;
        expect(e.generic, isFalse);
        expect(q.correctOption, e.reply);
        expect(q.audio, e.hear);
        // 通用回答（Thank you. 之类）不能当干扰项
        final generic = repo.allExchanges
            .where((x) => x.generic)
            .map((x) => x.reply)
            .toSet();
        expect(q.options.where(generic.contains), isEmpty);
      case QuestionType.listenMeaning:
        expect(q.correctOption, q.item.zh);
        expect(q.audio, q.item.en);
    }
  }

  test('每一课的测验都能出满 10 题，题目合法', () {
    for (final lesson in repo.allLessons.where((l) => !l.isReview)) {
      for (var seed = 0; seed < 30; seed++) {
        final qs = builder(seed).build([...lesson.words, ...lesson.exchanges]);
        expect(qs, hasLength(10), reason: '${lesson.id} seed $seed');
        qs.forEach(checkQuestion);
        // 一半单词题一半句子题
        expect(qs.where((q) => q.item is Word), hasLength(5));
      }
    }
  });

  test('复习课 15 题，只出本门课复习范围内的', () {
    for (final lesson in repo.allLessons.where((l) => l.isReview)) {
      final items = [
        ...repo.wordsFor(lesson),
        ...repo.exchangesFor(lesson),
        ...lesson.dialogue.lines.where((l) => !l.isMe),
      ];
      for (var seed = 0; seed < 30; seed++) {
        final qs = builder(seed).build(items, count: 15);
        expect(qs, hasLength(15));
        qs.forEach(checkQuestion);
        for (final q in qs) {
          expect(q.item.course, lesson.course);
          expect(q.item.day, lessThanOrEqualTo(lesson.day));
        }
      }
    }
  });

  test('四种题型都会出现', () {
    final types = <QuestionType>{};
    for (var seed = 0; seed < 20; seed++) {
      final l = repo.lesson('travel', 8);
      types.addAll(
          builder(seed).build([...l.words, ...l.exchanges]).map((q) => q.type));
    }
    expect(types, QuestionType.values.toSet());
  });

  test('生词本只有几条、只有句子时也能出题', () {
    final items = <StudyItem>[repo.allExchanges[3], repo.allLines[10]];
    final qs = builder(1).build(items, count: 2);
    expect(qs, hasLength(2));
    qs.forEach(checkQuestion);

    final one = builder(2).build([repo.allWords.first], count: 1);
    expect(one, hasLength(1));
    checkQuestion(one.single);
  });

  test('通用回答只出“听句子选意思”', () {
    final generic = repo.allExchanges.where((e) => e.generic).toList();
    expect(generic, isNotEmpty);
    for (var seed = 0; seed < 10; seed++) {
      for (final q in builder(seed).build(generic, count: generic.length)) {
        expect(q.type, QuestionType.listenMeaning);
      }
    }
  });
}
