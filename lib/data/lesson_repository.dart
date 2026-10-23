import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/lesson.dart';

/// 全部课程内容：assets/courses/courses.json 列出几门课，
/// 每门课的每一课是 assets/courses/<课程 id>/dayNN.json。启动时一次读进内存（几百 KB）
class LessonRepository extends GetxService {
  LessonRepository(this.courses) {
    for (final course in courses) {
      for (final lesson in course.lessons) {
        for (final item in [
          ...lesson.words,
          ...lesson.exchanges,
          ...lesson.dialogue.lines,
        ]) {
          // 同一句话在好几课出现时（比如 Thank you.），保留第一次出现的那课
          _byKey.putIfAbsent(item.key, () => item);
        }
      }
    }
  }

  static LessonRepository get to => Get.find();

  static Future<LessonRepository> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    final index =
        jsonDecode(await assets.loadString('assets/courses/courses.json'))
            as List;
    final courses = [
      for (final c in index) Course.fromJson(c as Map<String, dynamic>)
    ];
    for (final course in courses) {
      course.lessons = await Future.wait([
        for (var day = 1; day <= course.totalDays; day++)
          assets
              .loadString(
                  'assets/courses/${course.id}/day${day.toString().padLeft(2, '0')}.json')
              .then((text) => Lesson.fromJson(
                  jsonDecode(text) as Map<String, dynamic>, course.id)),
      ]);
    }
    return LessonRepository(courses);
  }

  final List<Course> courses;
  final Map<String, StudyItem> _byKey = {};

  Course course(String id) => courses.firstWhere((c) => c.id == id);

  Lesson lesson(String courseId, int day) => course(courseId).lessons[day - 1];

  Lesson lessonOf(StudyItem item) => lesson(item.course, item.day);

  List<Lesson> get allLessons => [for (final c in courses) ...c.lessons];

  int get totalLessons => courses.fold(0, (n, c) => n + c.totalDays);

  StudyItem? find(String key) => _byKey[key];

  /// “旅行出行 · 第 8 课 入境检查（一）”，列表里标出处用
  String sourceOf(StudyItem item) {
    final l = lessonOf(item);
    return '${course(l.course).title} · 第 ${l.day} 课 ${l.title}';
  }

  /// 复习课返回复习范围内所有课的单词，普通课返回当课的
  List<Word> wordsFor(Lesson lesson) => lesson.isReview
      ? [for (final l in _range(lesson)) ...l.words]
      : lesson.words;

  List<Exchange> exchangesFor(Lesson lesson) => lesson.isReview
      ? [for (final l in _range(lesson)) ...l.exchanges]
      : lesson.exchanges;

  Iterable<Lesson> _range(Lesson lesson) => course(lesson.course)
      .lessons
      .where((l) => l.day >= lesson.reviewFrom! && l.day <= lesson.reviewTo!);

  List<Word> get allWords => [for (final l in allLessons) ...l.words];

  List<Exchange> get allExchanges =>
      [for (final l in allLessons) ...l.exchanges];

  List<DialogueLine> get allLines =>
      [for (final l in allLessons) ...l.dialogue.lines];
}
