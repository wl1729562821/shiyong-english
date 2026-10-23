import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_english/main.dart';

const ttsChannel = MethodChannel('travel_english/tts');

/// 假的原生语音通道：记录读了什么，50ms 后回调 onEnd，模拟“读完了”
class FakeTts {
  final spoken = <String>[];

  /// 每次朗读时传给原生的倍速，和 [spoken] 一一对应
  final speeds = <double>[];
  bool stopped = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      switch (call.method) {
        case 'getVoices':
          return [
            {'id': 'v1', 'name': 'Microsoft Zira Desktop', 'language': 'en-US'},
            {'id': 'v2', 'name': 'en-gb-x-rjs-local', 'language': 'en-GB'},
          ];
        case 'speak':
          final args = call.arguments as Map;
          spoken.add(args['text'] as String);
          speeds.add(args['speed'] as double);
          final id = args['id'] as int;
          Future.delayed(
              const Duration(milliseconds: 50), () => _sendOnEnd(id));
          return null;
        case 'stop':
          stopped = true;
          return null;
      }
      return null;
    });
  }

  static void _sendOnEnd(int id) {
    final data = const StandardMethodCodec()
        .encodeMethodCall(MethodCall('onEnd', {'id': id, 'ok': true}));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(ttsChannel.name, data, (_) {});
  }
}

/// 清空 GetX 和 SharedPreferences，重新注册全部服务
Future<FakeTts> setUpApp([Map<String, Object> prefs = const {}]) async {
  Get.reset();
  SharedPreferences.setMockInitialValues(prefs);
  final tts = FakeTts()..install();
  await initServices(importLegacyData: false);
  return tts;
}

/// 在首页切到某门课，滚到那一课并点开
Future<void> openLesson(WidgetTester tester, String course, int day) async {
  // 从课程页返回后列表还停在下面，课程卡片可能已经滚出去了，先往上滚回来
  final card = find.byKey(ValueKey('course-$course'));
  await tester.scrollUntilVisible(card, -300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
  final tile = find.byKey(ValueKey('lesson-$course-$day'));
  await tester.scrollUntilVisible(tile, 300,
      scrollable: find.byType(Scrollable).first);
  // scrollUntilVisible 停下时可能只露出一半（被底部导航栏挡住），再确保整块可见
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}
