import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows 上 shared_preferences 的文件放在 %APPDATA%\公司名\产品名\ 下，
/// 产品名来自 windows/runner/Runner.rc。App 从“旅行英语25天”改名成“实用英语”后
/// 目录变了，第一次启动时把旧目录里的进度、生词本、设置搬过来（旧文件不动）。
const _legacyProductNames = ['旅行英语25天', 'travel_english'];

/// [appDataDir] 默认是 %APPDATA%，测试时传临时目录。返回是否导入了旧数据
Future<bool> importLegacyWindowsData({String? appDataDir}) async {
  if (kIsWeb || !Platform.isWindows) return false;
  final appData = appDataDir ?? Platform.environment['APPDATA'];
  if (appData == null) return false;
  final prefs = await SharedPreferences.getInstance();
  // 新目录里已经有数据（不是第一次启动），不覆盖
  if (prefs.getKeys().isNotEmpty) return false;

  for (final name in _legacyProductNames) {
    final file = File('$appData\\com.travel\\$name\\shared_preferences.json');
    if (!file.existsSync()) continue;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in data.entries) {
        // 文件里的 key 带 flutter. 前缀，API 里不带
        if (!key.startsWith('flutter.')) continue;
        final k = key.substring('flutter.'.length);
        switch (value) {
          case String v:
            await prefs.setString(k, v);
          case bool v:
            await prefs.setBool(k, v);
          case int v:
            await prefs.setInt(k, v);
          case double v:
            await prefs.setDouble(k, v);
          case List v:
            await prefs.setStringList(k, v.cast<String>());
        }
      }
      debugPrint('imported legacy data from ${file.path}');
      return true;
    } on Object catch (e) {
      // 旧文件坏了就算了，从头开始
      debugPrint('legacy import failed: $e');
    }
  }
  return false;
}
