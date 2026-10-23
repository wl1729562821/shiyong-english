import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';

/// 生词本里的一条记录
class NoteEntry {
  const NoteEntry({required this.addedAt, this.wrongCount = 0});

  factory NoteEntry.fromJson(Map<String, dynamic> json) => NoteEntry(
        addedAt: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        wrongCount: json['w'] as int? ?? 0,
      );

  final DateTime addedAt;

  /// 测验里答错的次数，生词本按它排序，错得多的排前面
  final int wrongCount;

  NoteEntry wrongOnceMore() =>
      NoteEntry(addedAt: addedAt, wrongCount: wrongCount + 1);

  Map<String, dynamic> toJson() =>
      {'t': addedAt.millisecondsSinceEpoch, 'w': wrongCount};
}

/// 自己给单词、句子加的标注
class Annotation {
  const Annotation({required this.text, required this.updatedAt});

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        text: json['text'] as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      );

  final String text;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() =>
      {'text': text, 't': updatedAt.millisecondsSinceEpoch};
}

/// 学习进度、生词本、标注、设置，全部存在 shared_preferences
class ProgressService extends GetxService {
  ProgressService(this._prefs) {
    _load();
  }

  static ProgressService get to => Get.find();

  static Future<ProgressService> create() async =>
      ProgressService(await SharedPreferences.getInstance());

  static const passScore = 80;

  static const _kCompleted = 'completedLessons';
  static const _kScores = 'lessonScores';
  static const _kNotebook = 'notebook';
  static const _kAnnotations = 'annotations';
  static const _kCourse = 'course';
  static const _kSpeed = 'speed';
  static const _kVoice = 'voiceId';
  static const _kStart = 'startDate';
  static const _kTextScale = 'textScale';

  // 只有旅行课时（1.0 版）的存法：天数是 int，没有课程 id
  static const _kOldCompleted = 'completed';
  static const _kOldScores = 'scores';

  /// 字号档位：标准 / 大 / 特大
  static const textScales = [(1.0, '标准'), (1.15, '大'), (1.3, '特大')];

  final SharedPreferences _prefs;

  /// 已完成的课（Lesson.id，比如 travel:8），测验达到 80 分或手动标记
  final completed = <String>{}.obs;

  /// 每课测验的最高分（百分制），key 是 Lesson.id
  final bestScores = <String, int>{}.obs;

  /// 生词本：StudyItem.key → 记录
  final notebook = <String, NoteEntry>{}.obs;

  /// 标注：StudyItem.key → 自己写的内容
  final annotations = <String, Annotation>{}.obs;

  /// 首页正在看的课程
  final courseId = 'basics'.obs;

  /// 朗读倍速，1.0 = 正常
  final speed = 0.9.obs;

  /// 选中的发音人，null = 自动选择
  final voiceId = RxnString();

  /// 界面字号缩放
  final textScale = 1.0.obs;

  late final Rx<DateTime> startDate;

  void _load() {
    _migrateFromTravelOnly();
    completed.addAll(_prefs.getStringList(_kCompleted) ?? const []);
    final scores = _prefs.getString(_kScores);
    if (scores != null) {
      bestScores.addAll((jsonDecode(scores) as Map<String, dynamic>)
          .map((id, score) => MapEntry(id, score as int)));
    }
    final notes = _prefs.getString(_kNotebook);
    if (notes != null) {
      (jsonDecode(notes) as Map<String, dynamic>).forEach((key, value) =>
          notebook[key] = NoteEntry.fromJson(value as Map<String, dynamic>));
    }
    final marks = _prefs.getString(_kAnnotations);
    if (marks != null) {
      (jsonDecode(marks) as Map<String, dynamic>).forEach((key, value) =>
          annotations[key] =
              Annotation.fromJson(value as Map<String, dynamic>));
    }
    courseId.value = _prefs.getString(_kCourse) ?? 'basics';
    speed.value = _prefs.getDouble(_kSpeed) ?? 0.9;
    voiceId.value = _prefs.getString(_kVoice);
    textScale.value = _prefs.getDouble(_kTextScale) ?? 1.0;

    final start = _prefs.getString(_kStart);
    startDate = (start == null ? _today() : DateTime.parse(start)).obs;
    if (start == null) {
      _prefs.setString(_kStart, startDate.value.toIso8601String());
    }
  }

  /// 1.0 版只有旅行课，完成记录存的是天数 [1, 3]、成绩是 {"1": 90}。
  /// 转成 travel:1 这样的课 id，然后删掉旧 key
  void _migrateFromTravelOnly() {
    final oldDone = _prefs.getStringList(_kOldCompleted);
    final oldScores = _prefs.getString(_kOldScores);
    if (oldDone == null && oldScores == null) return;
    if (oldDone != null) {
      _prefs.setStringList(
          _kCompleted,
          {
            ...?_prefs.getStringList(_kCompleted),
            for (final d in oldDone) Lesson.lessonId('travel', int.parse(d)),
          }.toList());
      _prefs.remove(_kOldCompleted);
    }
    if (oldScores != null) {
      final current = _prefs.getString(_kScores);
      _prefs.setString(
          _kScores,
          jsonEncode({
            if (current != null) ...jsonDecode(current) as Map<String, dynamic>,
            for (final e
                in (jsonDecode(oldScores) as Map<String, dynamic>).entries)
              Lesson.lessonId('travel', int.parse(e.key)): e.value,
          }));
      _prefs.remove(_kOldScores);
    }
    // 老用户原来在学旅行课，首页先停在旅行课
    _prefs.setString(_kCourse, 'travel');
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // ---------- 进度 ----------

  bool isCompleted(String lessonId) => completed.contains(lessonId);

  int completedIn(Course course) =>
      course.lessons.where((l) => completed.contains(l.id)).length;

  /// 这门课第一个还没完成的课，全部完成后停在最后一课
  Lesson nextLesson(Course course) => course.lessons.firstWhere(
        (l) => !completed.contains(l.id),
        orElse: () => course.lessons.last,
      );

  /// 从开始日期算起，今天是学习的第几天
  int get studyDay => _today().difference(startDate.value).inDays + 1;

  void setCourse(String id) {
    courseId.value = id;
    _prefs.setString(_kCourse, id);
  }

  /// 记录一次测验成绩，达到 [passScore] 自动标记完成。返回是否刚刚完成
  bool recordQuiz(String lessonId, int score) {
    if (score > (bestScores[lessonId] ?? -1)) {
      bestScores[lessonId] = score;
      _prefs.setString(_kScores, jsonEncode(bestScores));
    }
    if (score >= passScore && !completed.contains(lessonId)) {
      setCompleted(lessonId, true);
      return true;
    }
    return false;
  }

  void setCompleted(String lessonId, bool done) {
    done ? completed.add(lessonId) : completed.remove(lessonId);
    _prefs.setStringList(_kCompleted, completed.toList()..sort());
  }

  void restartPlanToday() {
    startDate.value = _today();
    _prefs.setString(_kStart, startDate.value.toIso8601String());
  }

  void resetProgress() {
    completed.clear();
    bestScores.clear();
    _prefs.remove(_kCompleted);
    _prefs.remove(_kScores);
    restartPlanToday();
  }

  // ---------- 生词本 ----------

  bool inNotebook(String key) => notebook.containsKey(key);

  void toggleNote(String key) {
    if (notebook.containsKey(key)) {
      notebook.remove(key);
    } else {
      notebook[key] = NoteEntry(addedAt: DateTime.now());
    }
    _saveNotebook();
  }

  void removeNote(String key) {
    notebook.remove(key);
    _saveNotebook();
  }

  /// 撤销删除：原样放回（保留错误次数和加入时间）
  void restoreNote(String key, NoteEntry entry) {
    notebook[key] = entry;
    _saveNotebook();
  }

  /// 测验答错：自动加入生词本，错误次数 +1
  void addWrong(String key) {
    final entry = notebook[key] ?? NoteEntry(addedAt: DateTime.now());
    notebook[key] = entry.wrongOnceMore();
    _saveNotebook();
  }

  void _saveNotebook() {
    _prefs.setString(
        _kNotebook,
        jsonEncode(
            notebook.map((key, entry) => MapEntry(key, entry.toJson()))));
  }

  // ---------- 标注 ----------

  String? annotationOf(String key) => annotations[key]?.text;

  /// 保存标注；内容为空就删掉
  void setAnnotation(String key, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      annotations.remove(key);
    } else {
      annotations[key] = Annotation(text: trimmed, updatedAt: DateTime.now());
    }
    _prefs.setString(
        _kAnnotations,
        jsonEncode(
            annotations.map((key, value) => MapEntry(key, value.toJson()))));
  }

  // ---------- 设置 ----------

  void setSpeed(double value) {
    speed.value = value;
    _prefs.setDouble(_kSpeed, value);
  }

  void setTextScale(double value) {
    textScale.value = value;
    _prefs.setDouble(_kTextScale, value);
  }

  void setVoice(String? id) {
    voiceId.value = id;
    id == null ? _prefs.remove(_kVoice) : _prefs.setString(_kVoice, id);
  }
}
