import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_english/main.dart';
import 'package:travel_english/pages/lesson/words_view.dart';
import 'package:travel_english/services/progress_service.dart';

import 'helpers.dart';

/// Windows 桌面：宽窗口布局 + 键盘快捷键
void main() {
  late FakeTts tts;
  // 按 Windows 平台跑（显示快捷键提示等）
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1200, 820);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> start(WidgetTester tester) async {
    tts = (await tester.runAsync(setUpApp))!;
    await tester.pumpWidget(const TravelEnglishApp());
    await tester.pumpAndSettle();
  }

  testWidgets('宽窗口：左侧导航栏，课程卡片一行，阶段分两栏', (tester) async {
    await start(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // 学习方法卡片展开着
    expect(find.textContaining('打开“盲听模式”'), findsOneWidget);
    // 三张课程卡片在同一行
    final a = tester.getTopLeft(find.byKey(const ValueKey('course-basics')));
    final c = tester.getTopLeft(find.byKey(const ValueKey('course-travel')));
    expect((a.dy - c.dy).abs(), lessThan(1));
    // 基础入门：第 1 阶段在左栏，第 2 阶段在右栏，同一高度
    final p1 = tester.getTopLeft(find.textContaining('字母与数字  第'));
    final p2 = tester.getTopLeft(find.textContaining('基本句型  第'));
    expect((p1.dy - p2.dy).abs(), lessThan(1));
    expect(p2.dx, greaterThan(p1.dx + 400));

    // 旅行出行 6 个阶段，左右各 3 个
    await tester.tap(find.byKey(const ValueKey('course-travel')));
    await tester.pumpAndSettle();
    final t1 = tester.getTopLeft(find.textContaining('基础生存  第'));
    final t2 = tester.getTopLeft(find.textContaining('机场与飞行  第'));
    expect((t1.dy - t2.dy).abs(), lessThan(1));
    expect(t2.dx, greaterThan(t1.dx + 400));
  }, variant: windows);

  testWidgets('Ctrl+F 跳到速查并聚焦搜索框', (tester) async {
    await start(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('常用搜索'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), '护照');
    await tester.pumpAndSettle();
    expect(find.text('passport'), findsOneWidget);
  }, variant: windows);

  testWidgets('课程页：空格全部播放 / 停止，Esc 返回', (tester) async {
    await start(tester);
    await openLesson(tester, 'basics', 1);
    expect(find.text('全部播放（空格）'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tts.spoken, ['A, H, J, K']);
    expect(find.text('停止'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(seconds: 2));
    expect(tts.spoken, hasLength(1));
    expect(find.text('全部播放（空格）'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
  }, variant: windows);

  testWidgets('对话：R 开始角色扮演，空格代替“我说完了”', (tester) async {
    await start(tester);
    await openLesson(tester, 'travel', 1);
    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(find.text('轮到你说：'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tts.spoken, ['Excuse me. Do you speak English?']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('角色扮演（R）'), findsOneWidget);
  }, variant: windows);

  // 最大字号下，手机竖屏和桌面窗口的主要页面都不能溢出
  for (final (name, size, ratio) in [
    ('桌面', const Size(1200, 820), 1.0),
    ('桌面窄窗口', const Size(700, 600), 1.0),
    ('手机', const Size(1080, 2340), 3.0),
  ]) {
    testWidgets('特大字号不溢出：$name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      await start(tester);
      ProgressService.to.setTextScale(1.3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '计划页');

      // 有几条标注，生词本的“我的标注”页和课程里的标注框都要能显示
      ProgressService.to
          .setAnnotation('w|A, H, J, K', '这几个字母都含“诶”的音，拼名字的时候最容易和 E 混，要特别注意听');
      ProgressService.to.setAnnotation('l|Lily Zhao.', '自己的名字先报全名，再一个个字母拼');

      for (final tab in ['速查', '生词本', '设置']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.tap(find.text('生词本').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('我的标注'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '我的标注');
      await tester.tap(find.text('课程').last);
      await tester.pumpAndSettle();

      for (final (course, day) in [
        ('basics', 1),
        ('daily', 20),
        ('travel', 12)
      ]) {
        await openLesson(tester, course, day);
        expect(tester.takeException(), isNull, reason: '$course $day 单词');
        for (final tab in ['听说', '对话', '测验']) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$course $day $tab');
        }
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }

      // 标注编辑框
      await openLesson(tester, 'basics', 2);
      // 大字号时“今日目标”卡片占满一屏，单词行还没构建，先往下滚
      await tester.drag(
          find
              .descendant(
                  of: find.byType(WordsView), matching: find.byType(Scrollable))
              .first,
          const Offset(0, -400));
      await tester.pumpAndSettle();
      // 只点屏幕上看得见的那个（拖动后最上面几行可能已经滚出屏幕，但还没被回收）
      await tester.tap(find.byTooltip('加标注').hitTestable().first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '标注编辑框');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    }, variant: windows);
  }

  testWidgets('正在朗读时关掉测验页和课程页不报错', (tester) async {
    await start(tester);
    await openLesson(tester, 'travel', 2);
    await tester.tap(find.text('测验'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // 答完题会读正确答案；还没读完（假引擎 50ms）就按 Esc 关掉测验页
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('开始测验'), findsOneWidget);

    // 课程页在全部播放时按返回键关掉
    await tester.tap(find.text('单词'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  }, variant: windows);

  testWidgets('测验：Enter 开始，数字键答题，Enter 下一题', (tester) async {
    await start(tester);
    await openLesson(tester, 'daily', 3);
    await tester.tap(find.text('测验'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('1 / 10'), findsOneWidget);
    expect(find.textContaining('快捷键：1–4 选择'), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump(const Duration(milliseconds: 100));
      // 底部按钮出现 = 已经答了（快捷键提示在列表底部，长题目时还没构建出来，不能用它判断）
      expect(find.text(i < 9 ? '下一题' : '查看结果'), findsOneWidget,
          reason: '第 ${i + 1} 题按 2 没反应');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(find.text('再测一次'), findsOneWidget);
    expect(ProgressService.to.bestScores['daily:3'], isNotNull);
    await tester.pump(const Duration(seconds: 1));
  }, variant: windows);

  testWidgets('写标注时按空格、R 不会触发课程页的快捷键', (tester) async {
    await start(tester);
    await openLesson(tester, 'daily', 2);
    await tester.tap(find.byTooltip('加标注').first);
    await tester.pumpAndSettle();
    expect(find.text('我的标注'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tts.spoken, isEmpty);
    // Esc 只关掉编辑框，不退出课程页
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('我的标注'), findsNothing);
    expect(find.text('全部播放（空格）'), findsOneWidget);
  }, variant: windows);
}
