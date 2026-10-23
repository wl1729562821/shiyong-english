import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_english/data/lesson_repository.dart';
import 'package:travel_english/models/lesson.dart';
import 'package:travel_english/pages/quiz/quiz_page.dart';
import 'package:travel_english/services/legacy_import.dart';
import 'package:travel_english/services/progress_service.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  legacyImportTests();

  test('测验 80 分以上自动完成，最高分只升不降，各门课分开算', () async {
    await setUpApp();
    final p = ProgressService.to;
    final basics = LessonRepository.to.course('basics');
    final travel = LessonRepository.to.course('travel');
    expect(p.nextLesson(basics).day, 1);

    expect(p.recordQuiz('basics:1', 70), isFalse);
    expect(p.isCompleted('basics:1'), isFalse);
    expect(p.bestScores['basics:1'], 70);

    expect(p.recordQuiz('basics:1', 90), isTrue);
    expect(p.isCompleted('basics:1'), isTrue);
    expect(p.recordQuiz('basics:1', 60), isFalse);
    expect(p.bestScores['basics:1'], 90);
    expect(p.nextLesson(basics).day, 2);
    // 别的课不受影响
    expect(p.isCompleted('travel:1'), isFalse);
    expect(p.nextLesson(travel).day, 1);
    expect(p.completedIn(basics), 1);
    expect(p.completedIn(travel), 0);
  });

  test('进度、生词本、标注、设置保存后能读回来', () async {
    await setUpApp();
    final p = ProgressService.to;
    p.recordQuiz('daily:3', 100);
    p.addWrong('w|passport');
    p.addWrong('w|passport');
    p.toggleNote('e|Chicken or beef?');
    p.setAnnotation('w|visa', '  签证，办之前查清要不要面签  ');
    p.setCourse('daily');
    p.setSpeed(0.7);
    p.setVoice('v2');
    p.setTextScale(1.3);

    // 模拟重启：用同一份 SharedPreferences 新建服务
    final again = ProgressService(await SharedPreferences.getInstance());
    expect(again.isCompleted('daily:3'), isTrue);
    expect(again.bestScores['daily:3'], 100);
    expect(again.notebook['w|passport']!.wrongCount, 2);
    expect(again.inNotebook('e|Chicken or beef?'), isTrue);
    // 首尾空白会去掉
    expect(again.annotationOf('w|visa'), '签证，办之前查清要不要面签');
    expect(again.courseId.value, 'daily');
    expect(again.speed.value, 0.7);
    expect(again.voiceId.value, 'v2');
    expect(again.textScale.value, 1.3);
  });

  test('标注保存空内容 = 删除', () async {
    await setUpApp();
    final p = ProgressService.to;
    p.setAnnotation('l|Here you are.', '递东西时说');
    expect(p.annotations, hasLength(1));
    p.setAnnotation('l|Here you are.', '   ');
    expect(p.annotations, isEmpty);
    final again = ProgressService(await SharedPreferences.getInstance());
    expect(again.annotations, isEmpty);
  });

  test('旧版（只有旅行课）的进度迁移成 travel:N', () async {
    await setUpApp({
      'completed': ['1', '3'],
      'scores': '{"1": 90, "3": 85, "4": 40}',
    });
    final p = ProgressService.to;
    expect(p.completed, {'travel:1', 'travel:3'});
    expect(p.bestScores, {'travel:1': 90, 'travel:3': 85, 'travel:4': 40});
    // 老用户首页先停在旅行课
    expect(p.courseId.value, 'travel');
    expect(p.nextLesson(LessonRepository.to.course('travel')).day, 2);
    // 旧 key 删掉了，再启动不会重复迁移
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('completed'), isFalse);
    expect(prefs.containsKey('scores'), isFalse);
  });

  test('新用户从基础入门开始', () async {
    await setUpApp();
    expect(ProgressService.to.courseId.value, 'basics');
  });

  test('按开始日期算今天是学习的第几天', () async {
    final start = DateTime.now().subtract(const Duration(days: 40));
    await setUpApp({
      'startDate':
          DateTime(start.year, start.month, start.day).toIso8601String(),
    });
    expect(ProgressService.to.studyDay, 41);
    ProgressService.to.restartPlanToday();
    expect(ProgressService.to.studyDay, 1);
  });

  test('重置进度保留生词本和标注', () async {
    await setUpApp();
    final p = ProgressService.to;
    p.recordQuiz('basics:1', 100);
    p.toggleNote('w|visa');
    p.setAnnotation('w|visa', '签证');
    p.resetProgress();
    expect(p.completed, isEmpty);
    expect(p.bestScores, isEmpty);
    expect(p.inNotebook('w|visa'), isTrue);
    expect(p.annotationOf('w|visa'), '签证');
  });

  test('语速：限制在 0.5x–2.0x，按 0.1 取整，调快调慢一档 0.1x', () async {
    await setUpApp();
    final p = ProgressService.to;
    expect(p.speed.value, 0.9); // 默认稍慢
    p.changeSpeed(1);
    expect(p.speed.value, 1.0); // 不是 0.99999…
    p.changeSpeed(3);
    expect(p.speed.value, 1.3);
    p.setSpeed(5);
    expect(p.speed.value, ProgressService.maxSpeed);
    p.changeSpeed(1);
    expect(p.speed.value, 2.0);
    p.setSpeed(0.1);
    expect(p.speed.value, ProgressService.minSpeed);
    p.changeSpeed(-1);
    expect(p.speed.value, 0.5);
    p.setSpeed(0.74);
    expect(p.speed.value, 0.7);
    final again = ProgressService(await SharedPreferences.getInstance());
    expect(again.speed.value, 0.7);
  });

  testWidgets('QuizController：全答对完成这一课，答错进生词本', (tester) async {
    await tester.runAsync(setUpApp);
    final progress = ProgressService.to;
    final c = Get.put(QuizController(
        items: _items('daily', 2), count: 10, lessonId: 'daily:2'));

    // 第一题答错，其余答对 → 90 分
    var first = true;
    while (!c.finished.value) {
      final q = c.current;
      c.choose(first ? (q.answer + 1) % 4 : q.answer);
      first = false;
      c.next();
    }
    expect(c.score, 90);
    expect(c.justCompleted, isTrue);
    expect(progress.isCompleted('daily:2'), isTrue);
    expect(progress.notebook.values.single.wrongCount, 1);

    // 再测一次：全错，不会取消完成，最高分不变
    c.restart();
    while (!c.finished.value) {
      c.choose((c.current.answer + 1) % 4);
      c.next();
    }
    expect(c.score, 0);
    expect(progress.isCompleted('daily:2'), isTrue);
    expect(progress.bestScores['daily:2'], 90);

    Get.delete<QuizController>();
    await tester.pump(const Duration(seconds: 1));
  });
}

List<StudyItem> _items(String course, int day) {
  final l = LessonRepository.to.lesson(course, day);
  return [...l.words, ...l.exchanges];
}

/// 改名前（旅行英语25天）Windows 版的数据文件，搬到新目录后还能用
void legacyImportTests() {
  test('Windows：从旧产品名目录导入进度，旧文件不动', () async {
    final tmp = await Directory.systemTemp.createTemp('legacy_import');
    addTearDown(() => tmp.delete(recursive: true));
    final old = File(
        '${tmp.path}${Platform.pathSeparator}com.travel${Platform.pathSeparator}'
        '旅行英语25天${Platform.pathSeparator}shared_preferences.json');
    await old.create(recursive: true);
    const content = '{"flutter.completed":["1","2"],'
        '"flutter.scores":"{\\"1\\":95,\\"2\\":80}",'
        '"flutter.startDate":"2026-10-20T00:00:00.000",'
        '"flutter.speed":0.8,'
        '"flutter.notebook":"{}"}';
    await old.writeAsString(content);

    SharedPreferences.setMockInitialValues({});
    expect(await importLegacyWindowsData(appDataDir: tmp.path), isTrue);
    final p = ProgressService(await SharedPreferences.getInstance());
    expect(p.completed, {'travel:1', 'travel:2'});
    expect(p.bestScores, {'travel:1': 95, 'travel:2': 80});
    expect(p.speed.value, 0.8);
    expect(p.startDate.value, DateTime(2026, 10, 20));
    expect(await old.readAsString(), content);

    // 新目录已经有数据时不再导入（不会把新进度覆盖掉）
    expect(await importLegacyWindowsData(appDataDir: tmp.path), isFalse);
  }, skip: !Platform.isWindows);

  test('没有旧数据就什么都不做', () async {
    final tmp = await Directory.systemTemp.createTemp('legacy_none');
    addTearDown(() => tmp.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    expect(await importLegacyWindowsData(appDataDir: tmp.path), isFalse);
  });
}
