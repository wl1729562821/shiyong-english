import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_english/main.dart';

/// 在真正的 Windows 窗口里走一遍主要界面并截图（真实语音引擎）。
///
/// flutter test integration_test/desktop_screens_test.dart -d windows --dart-define=SHOT_DIR=E:\shots
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const shotDir = String.fromEnvironment('SHOT_DIR');
  final shotKey = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    if (shotDir.isEmpty) return;
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$shotDir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  }

  testWidgets('桌面版主要界面', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initServices(importLegacyData: false);
    await tester.pumpWidget(
        RepaintBoundary(key: shotKey, child: const TravelEnglishApp()));
    await tester.pumpAndSettle();
    // 等语音引擎加载完发音人
    await Future<void>.delayed(const Duration(seconds: 1));
    await shot(tester, '1_home');

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // ignore: avoid_print
    print('window logical size: $size');
    expect(find.byType(NavigationRail), findsOneWidget);

    // 日常沟通第 1 课：给第一个单词加一条标注，截图看标注显示
    await tester.tap(find.byKey(const ValueKey('course-daily')));
    await tester.pumpAndSettle();
    await shot(tester, '1b_home_daily');
    await tester.tap(find.byKey(const ValueKey('lesson-daily-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('加标注').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), '见面打招呼，回 Not bad / Pretty good 就行');
    await shot(tester, '2_annotation_dialog');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('见面打招呼，回 Not bad / Pretty good 就行'), findsOneWidget);
    await shot(tester, '2b_lesson_words_with_note');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('course-travel')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('lesson-travel-8')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-travel-8')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    // 真实等待：移民官的第一句由 SAPI 读完后，应该自动轮到“我”
    for (var i = 0; i < 50 && find.text('轮到你说：').evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    expect(find.text('轮到你说：'), findsOneWidget);
    await shot(tester, '3_roleplay');
    // 空格 = 我说完了 → 读示范 → 自动读移民官下一句 → 再轮到我
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      if (find.text('轮到你说：').evaluate().isNotEmpty &&
          find.text('Here you are.').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('Here you are.'), findsOneWidget); // 我说过的那句显示英文了
    expect(find.text('轮到你说：'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('测验'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump(const Duration(seconds: 2));
    await shot(tester, '4_quiz');

    // Esc 返回：课程页上如果还在读，第一下 Esc 只是停止朗读，所以多按几下直到回到首页
    for (var i = 0;
        i < 4 && find.byType(NavigationRail).evaluate().isEmpty;
        i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('生词本').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('我的标注'));
    await tester.pumpAndSettle();
    await shot(tester, '5_my_annotations');

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();
    await shot(tester, '6_settings_large_text');
    await tester.tap(find.text('课程').last);
    await tester.pumpAndSettle();
    await shot(tester, '7_home_large_text');
    Get.reset();
  });
}
