import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:travel_english/main.dart';
import 'package:travel_english/services/progress_service.dart';
import 'package:travel_english/services/tts_service.dart';

import 'helpers.dart';

/// 手机尺寸下走一遍主要界面：课程切换、单词、角色扮演、测验、速查、标注
void main() {
  late FakeTts tts;

  setUp(() {
    // 手机竖屏尺寸
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3;
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

  testWidgets('首页：三门课，默认基础入门，可以切换', (tester) async {
    await start(tester);
    expect(find.text('实用英语'), findsOneWidget);
    expect(find.text('基础入门 → 日常沟通 → 旅行出行'), findsOneWidget);
    expect(find.text('0/55'), findsOneWidget);
    expect(find.textContaining('继续学习 · 基础入门 第 1 课 字母与拼读'), findsOneWidget);
    expect(find.textContaining('字母与数字  第 1–2 课'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('course-daily')));
    await tester.pumpAndSettle();
    expect(find.textContaining('继续学习 · 日常沟通 第 1 课 寒暄与聊天气'), findsOneWidget);
    expect(find.textContaining('社交寒暄  第 1–4 课'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-basics-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('course-travel')));
    await tester.pumpAndSettle();
    expect(find.textContaining('基础生存  第 1–3 课'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('lesson-travel-12')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('复习第 1–11 课'), findsOneWidget);
    // 选的课程记住了
    expect(ProgressService.to.courseId.value, 'travel');
  });

  testWidgets('单词全部播放，按顺序读，停止后不再继续', (tester) async {
    await start(tester);
    await openLesson(tester, 'basics', 1);
    expect(find.text('字母与拼读'), findsOneWidget);
    expect(find.text('今日目标'), findsOneWidget);

    await tester.tap(find.text('全部播放'));
    // 每个词：读 50ms + 停 800ms
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 800));
    }
    expect(tts.spoken.take(3),
        ['A, H, J, K', 'B, C, D, E, G, P, T, V, Z', 'F, L, M, N, S, X']);
    expect(find.text('停止'), findsOneWidget);

    await tester.tap(find.text('停止'));
    await tester.pump(const Duration(seconds: 2));
    final count = tts.spoken.length;
    await tester.pump(const Duration(seconds: 3));
    expect(tts.spoken.length, count);
    expect(find.text('全部播放'), findsOneWidget);
  });

  testWidgets('角色扮演：轮到我时等我说完，再播放示范', (tester) async {
    await start(tester);
    await openLesson(tester, 'travel', 1);
    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('角色扮演'));
    await tester.pump();
    // 第一句是“我”说的：只显示中文，等我说
    expect(find.text('轮到你说：'), findsOneWidget);
    expect(find.text('Excuse me. Do you speak English?'), findsNothing);
    expect(tts.spoken, isEmpty);

    await tester.tap(find.text('我说完了，听示范'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tts.spoken, ['Excuse me. Do you speak English?']);
    expect(find.text('Excuse me. Do you speak English?'), findsOneWidget);

    // 示范读完 → 停 500ms → 自动读对方的下一句 → 又轮到我
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tts.spoken.last, 'Yes, I do. How can I help you?');
    expect(find.text('轮到你说：'), findsOneWidget);

    await tester.tap(find.byTooltip('停止'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('角色扮演'), findsOneWidget);
    expect(find.text('轮到你说：'), findsNothing);
  });

  testWidgets('长对话角色扮演时自动滚到当前行', (tester) async {
    await start(tester);
    await openLesson(tester, 'travel', 25);
    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('角色扮演'));

    // 一直替“我”说下去，每次轮到我时，“轮到你说”那一行都要在屏幕上
    var turns = 0;
    for (var ms = 0; ms < 60000; ms += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('轮到你说：').evaluate().isNotEmpty) {
        // 等滚动动画走完（滚动中 Scrollable 会忽略点击，hitTestable 也就找不到）
        await tester.pumpAndSettle();
        expect(find.text('轮到你说：').hitTestable(), findsOneWidget,
            reason: '第 ${turns + 1} 次轮到我时看不到当前行');
        turns++;
        await tester.tap(find.text('我说完了，听示范'));
      } else if (find.text('角色扮演').evaluate().isNotEmpty) {
        break; // 演完了
      }
    }
    expect(turns, 8); // 旅行第 25 课的模拟对话里“我”有 8 句
    // 最后一句（我说的）也在屏幕上
    expect(
        find.text("Sure. First, I'll give a short presentation.").hitTestable(),
        findsOneWidget);
  });

  testWidgets('盲听模式遮住文字，点卡片显示', (tester) async {
    await start(tester);
    await openLesson(tester, 'travel', 8);
    await tester.tap(find.text('听说'));
    await tester.pumpAndSettle();
    expect(find.text("What's the purpose of your visit?"), findsOneWidget);

    await tester.tap(find.text('盲听模式'));
    await tester.pump();
    expect(find.text("What's the purpose of your visit?"), findsNothing);

    await tester.tap(find.text('点击卡片显示文字').first);
    await tester.pump();
    expect(find.text("What's the purpose of your visit?"), findsOneWidget);
    expect(find.text('Sightseeing. I\'m here on vacation.'), findsOneWidget);
  });

  testWidgets('做完测验看到结果，答错的进生词本', (tester) async {
    await start(tester);
    await openLesson(tester, 'daily', 8);
    await tester.tap(find.text('测验'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始测验'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 10; i++) {
      expect(find.text('${i + 1} / 10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('option-0')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text(i < 9 ? '下一题' : '查看结果'));
      await tester.pumpAndSettle();
    }
    expect(find.text('再测一次'), findsOneWidget);
    expect(find.textContaining('答对'), findsOneWidget);

    final progress = ProgressService.to;
    final score = progress.bestScores['daily:8'];
    expect(score, isNotNull);
    // 每道答错的题都进了生词本
    expect(progress.notebook.length, 10 - (score! / 10).round());

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最高分'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('单词下面加标注、修改、删除', (tester) async {
    await start(tester);
    await openLesson(tester, 'basics', 3);
    expect(find.text('Nice to meet you.'), findsOneWidget);

    // 第一个单词的 ✎ 按钮
    await tester.tap(find.byTooltip('加标注').first);
    await tester.pumpAndSettle();
    expect(find.text('我的标注'), findsOneWidget);
    expect(find.text('Nice to meet you.  很高兴认识你。'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), '第一次见面说；分别时说 Nice meeting you.');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('第一次见面说；分别时说 Nice meeting you.'), findsOneWidget);
    expect(ProgressService.to.annotationOf('w|Nice to meet you.'),
        '第一次见面说；分别时说 Nice meeting you.');
    expect(find.byTooltip('修改标注'), findsOneWidget);

    // 点标注本身也能改
    await tester.tap(find.text('第一次见面说；分别时说 Nice meeting you.'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '初次见面');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('初次见面'), findsOneWidget);

    // 删除
    await tester.tap(find.byTooltip('修改标注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('初次见面'), findsNothing);
    expect(ProgressService.to.annotations, isEmpty);

    // 遮住中文时，标注也一起遮住
    ProgressService.to.setAnnotation('w|Nice to meet you.', '你好');
    await tester.pump();
    expect(find.text('你好'), findsOneWidget);
    await tester.tap(find.text('遮住中文'));
    await tester.pump();
    expect(find.text('你好'), findsNothing);
  });

  testWidgets('对话的每一句都能加标注（按钮或长按）', (tester) async {
    await start(tester);
    await openLesson(tester, 'daily', 1);
    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();

    // 气泡旁边的 ✎（第一句是邻居说的）
    await tester.tap(find.byTooltip('加标注').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Morning! How\'s it going?'), findsWidgets);
    await tester.enterText(find.byType(TextField), '早上打招呼，回 Not bad 就行');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('早上打招呼，回 Not bad 就行'), findsOneWidget);

    // 长按另一句
    await tester.longPress(find.text('Not bad, thanks. And you?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '反问对方');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('反问对方'), findsOneWidget);
    expect(ProgressService.to.annotations.keys,
        {"l|Morning! How's it going?", 'l|Not bad, thanks. And you?'});
  });

  testWidgets('我的标注：集中查看，一键复制成文本', (tester) async {
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await start(tester);
    ProgressService.to.setAnnotation('w|umbrella', '雨伞，英式也说 brolly');
    ProgressService.to
        .setAnnotation('e|Do you have a reservation?', '餐厅门口最先听到的问题');

    await tester.tap(find.widgetWithText(NavigationDestination, '生词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的标注 2'));
    await tester.pumpAndSettle();
    expect(find.text('共 2 条'), findsOneWidget);
    expect(find.text('雨伞，英式也说 brolly'), findsOneWidget);
    expect(find.text('日常沟通 · 第 1 课 寒暄与聊天气'), findsOneWidget);
    // 问答显示回答
    expect(find.textContaining('↳ No, we don\'t. A table for two, please.'),
        findsOneWidget);

    await tester.tap(find.text('全部复制'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('umbrella\n雨伞\n标注：雨伞，英式也说 brolly'));
    expect(clipboard, contains('标注：餐厅门口最先听到的问题'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('速查：输入中文找到句子，也能搜自己的标注', (tester) async {
    await start(tester);
    await tester.tap(find.text('速查'));
    await tester.pumpAndSettle();
    expect(find.text('常用搜索'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '毛巾');
    await tester.pumpAndSettle();
    expect(find.text('towel'), findsOneWidget);
    expect(find.textContaining('旅行出行 · 第 16 课'), findsWidgets);

    await tester.tap(find.text('towel'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tts.spoken.last, 'towel');
    expect(TtsService.to.speaking.value, isNull);

    // 搜标注里的字
    ProgressService.to.setAnnotation('w|latte', '我每天早上都点燕麦奶的');
    await tester.enterText(find.byType(TextField), '每天早上都点');
    await tester.pumpAndSettle();
    expect(find.text('latte'), findsOneWidget);
    expect(find.text('我每天早上都点燕麦奶的'), findsOneWidget);

    // 只看某一门课（列表是懒加载的，用“共 N 条”比较）
    int count() {
      final text =
          tester.widget<Text>(find.textContaining(RegExp(r'^共 \d+ 条$'))).data!;
      return int.parse(RegExp(r'\d+').firstMatch(text)!.group(0)!);
    }

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pumpAndSettle();
    final all = count();
    await tester.tap(find.widgetWithText(ChoiceChip, '旅行出行'));
    await tester.pumpAndSettle();
    expect(count(), lessThan(all));
    expect(count(), greaterThan(0));
    Get.reset();
  });
}
