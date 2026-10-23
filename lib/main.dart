import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import 'data/lesson_repository.dart';
import 'pages/home/home_page.dart';
import 'services/legacy_import.dart';
import 'services/progress_service.dart';
import 'services/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initServices();
  runApp(const TravelEnglishApp());
}

/// 注册全局服务。测试里也调用它（换成假的 SharedPreferences 和语音通道），
/// 测试时 [importLegacyData] 传 false，免得读到这台电脑上真实的旧数据
Future<void> initServices({bool importLegacyData = true}) async {
  if (importLegacyData) await importLegacyWindowsData();
  Get.put(await ProgressService.create(), permanent: true);
  Get.put(await LessonRepository.load(), permanent: true);
  final tts = Get.put(TtsService(), permanent: true);
  // Android 的语音引擎初始化要几百毫秒，不等它，先把界面显示出来
  unawaited(tts.init());
}

class TravelEnglishApp extends StatelessWidget {
  const TravelEnglishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '实用英语',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00897B),
        useMaterial3: true,
      ),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 设置里的字号：整体放大文字（桌面上看着小的时候用）
      builder: (context, child) => Obx(() => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler:
                    TextScaler.linear(ProgressService.to.textScale.value)),
            child: child!,
          )),
      home: const HomePage(),
    );
  }
}
