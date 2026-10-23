import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_english/data/lesson_repository.dart';
import 'package:travel_english/models/lesson.dart';
import 'package:travel_english/widgets/common.dart';

/// 检查 assets/courses 里所有课程 JSON 的内容是否完整、一致
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LessonRepository repo;

  setUpAll(() async {
    repo = await LessonRepository.load();
  });

  test('三门课按顺序：基础入门 10 课、日常沟通 20 课、旅行出行 25 课', () {
    expect([
      for (final c in repo.courses) (c.id, c.lessons.length)
    ], [
      ('basics', 10),
      ('daily', 20),
      ('travel', 25),
    ]);
    expect(repo.totalLessons, 55);
    for (final c in repo.courses) {
      expect(c.lessons.map((l) => l.day),
          [for (var d = 1; d <= c.totalDays; d++) d],
          reason: c.id);
      expect(c.lessons.every((l) => l.course == c.id), isTrue);
    }
  });

  test('每门课的阶段覆盖所有课，没有重叠', () {
    for (final c in repo.courses) {
      for (var d = 1; d <= c.totalDays; d++) {
        expect(c.phases.where((p) => p.contains(d)), hasLength(1),
            reason: '${c.id} 第 $d 课');
      }
    }
  });

  test('普通课有足够的单词、问答、对话；复习课范围正确', () {
    for (final l in repo.allLessons) {
      final name = l.id;
      expect(l.tips, isNotEmpty, reason: '$name tips');
      expect(l.dialogue.lines.length, greaterThanOrEqualTo(8),
          reason: '$name dialogue');
      expect(l.dialogue.lines.where((x) => x.isMe), isNotEmpty,
          reason: '$name 没有“我”的台词');
      if (l.isReview) {
        expect(l.reviewTo, lessThan(l.day));
        expect(repo.wordsFor(l).length, greaterThan(100), reason: name);
        expect(repo.wordsFor(l).every((w) => w.course == l.course), isTrue);
      } else {
        expect(l.words.length, inInclusiveRange(12, 20), reason: '$name words');
        expect(l.exchanges.length, inInclusiveRange(8, 10),
            reason: '$name exchanges');
      }
    }
    expect([for (final l in repo.allLessons.where((l) => l.isReview)) l.id],
        ['basics:10', 'daily:20', 'travel:12', 'travel:25']);
  });

  test('同一课里单词和问答不重复', () {
    for (final l in repo.allLessons) {
      final words = l.words.map((w) => w.en.toLowerCase()).toList();
      expect(words.toSet().length, words.length, reason: l.id);
      final hears = l.exchanges.map((e) => e.hear).toList();
      expect(hears.toSet().length, hears.length, reason: l.id);
    }
  });

  test('没有空字段，英文里不夹中文，中文里有中文', () {
    final cjk = RegExp(r'[一-鿿]');
    // 中文翻译里要有汉字；纯数字的（比如价格 25.99、电话号码）也可以
    final zhOk = RegExp(r'[一-鿿0-9]');
    for (final item in [
      ...repo.allWords,
      ...repo.allExchanges,
      ...repo.allLines
    ]) {
      expect(item.en.trim(), isNotEmpty);
      expect(cjk.hasMatch(item.en), isFalse, reason: item.en);
      expect(zhOk.hasMatch(item.zh), isTrue, reason: '${item.en} → ${item.zh}');
    }
    for (final e in repo.allExchanges) {
      expect(cjk.hasMatch(e.reply), isFalse, reason: e.reply);
      expect(zhOk.hasMatch(e.replyZh), isTrue, reason: e.replyZh);
    }
  });

  test('每个条目都能通过 key 找回来（生词本和标注靠它）', () {
    for (final item in [
      ...repo.allWords,
      ...repo.allExchanges,
      ...repo.allLines
    ]) {
      final found = repo.find(item.key);
      expect(found, isNotNull);
      expect(found!.en, item.en);
    }
  });

  test('课程和每一课的图标都有对应的 Material 图标', () {
    for (final c in repo.courses) {
      expect(lessonIcon(c.icon), isNot(Icons.menu_book_outlined), reason: c.id);
    }
    for (final l in repo.allLessons) {
      expect(lessonIcon(l.icon), isNot(Icons.menu_book_outlined),
          reason: '${l.id} ${l.icon}');
    }
  });

  test('要读出来的句子里没有阿拉伯数字（TTS 读房间号、电话会读错）', () {
    final digits = RegExp(r'\d');
    for (final item in <StudyItem>[...repo.allExchanges, ...repo.allLines]) {
      expect(digits.hasMatch(item.en), isFalse, reason: item.en);
    }
    for (final e in repo.allExchanges) {
      expect(digits.hasMatch(e.reply), isFalse, reason: e.reply);
    }
  });

  test('出处文字带课程名和第几课', () {
    final item = repo.lesson('daily', 8).words.first;
    expect(repo.sourceOf(item), '日常沟通 · 第 8 课 咖啡店与外卖');
  });
}
