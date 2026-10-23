import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'progress_service.dart';

/// 系统里安装的英文发音人
class TtsVoice {
  const TtsVoice(
      {required this.id,
      required this.name,
      required this.language,
      this.quality = ''});

  factory TtsVoice.fromMap(Map<Object?, Object?> map) => TtsVoice(
        id: map['id'] as String,
        name: map['name'] as String,
        language: map['language'] as String? ?? '',
        quality: map['quality'] as String? ?? '',
      );

  final String id;
  final String name;

  /// 比如 en-US、en-GB
  final String language;

  /// 只有 iOS 会传：default / enhanced / premium（同名声音的压缩版和增强版）
  final String quality;

  String get qualityLabel => switch (quality) {
        'premium' => '高级',
        'enhanced' => '增强',
        _ => '',
      };

  bool get isEnglish => language.toLowerCase().startsWith('en');

  String get accent => switch (language.toLowerCase()) {
        'en-us' => '美式',
        'en-gb' => '英式',
        'en-au' => '澳式',
        'en-in' => '印度',
        'en-ca' => '加拿大',
        _ => language,
      };

  /// Windows: "Microsoft Zira Desktop" → "Zira Desktop"；
  /// Android: "en-us-x-sfg-local" → "sfg"
  String get shortName {
    final android =
        RegExp(r'^[a-z]{2}-[a-z]{2}-x-([a-z0-9]+)').firstMatch(name);
    if (android != null) return android.group(1)!;
    return name.replaceFirst(RegExp(r'^Microsoft\s+'), '');
  }
}

/// 朗读英文。原生代码：Android 是 TtsHandler.kt，Windows 是 tts_channel.cpp，
/// 两边协议一样：speak 立即返回，读完后原生回调 onEnd {id}。
///
/// 这里把它包装成 `await say(text)`：读完返回 true，被打断返回 false，
/// 这样“全部播放”、“角色扮演”就能写成普通的 for 循环。
class TtsService extends GetxService {
  TtsService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('travel_english/tts') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static TtsService get to => Get.find();

  final MethodChannel _channel;

  /// 正在读的那句话，界面用它高亮
  final speaking = RxnString();

  /// 是否在连续播放（全部播放 / 角色扮演）
  final sequenceRunning = false.obs;

  final voices = <TtsVoice>[].obs;

  /// 没有可用的英文语音时的原因，null 表示一切正常
  final problem = RxnString();

  /// 没选发音人时用哪个。Android 原生那边会自动用美式英语，这里返回 null；
  /// Windows 的系统默认发音人在中文系统上通常是中文的（Huihui），
  /// 读英文是中式口音，所以默认用第一个美式英语发音人
  TtsVoice? get defaultVoice {
    if (!_isWindows || voices.isEmpty) return null;
    return voices
            .firstWhereOrNull((v) => v.language.toLowerCase() == 'en-us') ??
        voices.first;
  }

  final bool _isWindows =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  int _nextId = 0;
  int? _pendingId;
  Completer<bool>? _pending;

  /// 每开始一个新的连续播放或单句播放都 +1，旧的循环发现编号变了就退出
  int _sequence = 0;

  Future<TtsService> init() async {
    await loadVoices();
    return this;
  }

  Future<void> loadVoices() async {
    try {
      final list =
          await _channel.invokeListMethod<Map<Object?, Object?>>('getVoices');
      voices.assignAll(
          (list ?? const []).map(TtsVoice.fromMap).where((v) => v.isEnglish));
      problem.value = voices.isEmpty ? '没有找到英文发音人' : null;
    } on PlatformException catch (e) {
      voices.clear();
      problem.value = e.message ?? e.code;
    } on MissingPluginException {
      voices.clear();
      problem.value = '当前平台不支持朗读';
    }
  }

  /// 读一句话，打断正在读的内容（包括连续播放）。读完返回 true
  Future<bool> say(String text, {double? speed}) {
    _sequence++;
    sequenceRunning.value = false;
    return _speak(text, speed: speed);
  }

  /// 停止一切朗读
  Future<void> stop() async {
    _sequence++;
    sequenceRunning.value = false;
    _finish(false);
    try {
      await _channel.invokeMethod('stop');
    } on Exception catch (e) {
      debugPrint('tts stop failed: $e');
    }
  }

  /// 开始一段连续播放，返回它的编号。之后用 [sayInSequence] 一句句读，
  /// 期间用户点了别的播放或停止，[isActive] 就变成 false
  int beginSequence() {
    _sequence++;
    sequenceRunning.value = true;
    return _sequence;
  }

  bool isActive(int sequence) => sequence == _sequence;

  Future<bool> sayInSequence(int sequence, String text) async {
    if (!isActive(sequence)) return false;
    return _speak(text);
  }

  /// 连续播放中两句之间的停顿；被打断返回 false
  Future<bool> pause(int sequence, Duration duration) async {
    await Future<void>.delayed(duration);
    return isActive(sequence);
  }

  void endSequence(int sequence) {
    if (isActive(sequence)) sequenceRunning.value = false;
  }

  Future<bool> _speak(String text, {double? speed}) async {
    _finish(false);
    final id = ++_nextId;
    final completer = Completer<bool>();
    _pending = completer;
    _pendingId = id;
    speaking.value = text;
    final progress = ProgressService.to;
    try {
      await _channel.invokeMethod('speak', {
        'text': text,
        'speed': speed ?? progress.speed.value,
        'voiceId': progress.voiceId.value ?? defaultVoice?.id ?? '',
        'id': id,
      });
    } on PlatformException catch (e) {
      problem.value = e.message ?? e.code;
      _finishIf(id, false);
      _showProblem();
    } on MissingPluginException {
      problem.value = '当前平台不支持朗读';
      _finishIf(id, false);
      _showProblem();
    }
    return completer.future;
  }

  DateTime? _lastNotice;

  /// 点了播放却没声音时提示一下原因（连续播放时每句都会失败，几秒内只提示一次）
  void _showProblem() {
    final now = DateTime.now();
    if (_lastNotice != null &&
        now.difference(_lastNotice!) < const Duration(seconds: 6)) {
      return;
    }
    _lastNotice = now;
    if (Get.context == null) return;
    Get.snackbar(
      '无法朗读',
      '${problem.value}。请到「设置」页查看解决办法。',
      // 放在顶部，不挡住底部的“下一题”“全部播放”按钮
      snackPosition: SnackPosition.TOP,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'onEnd') {
      final args = call.arguments as Map<Object?, Object?>;
      _finishIf(args['id'] as int, args['ok'] as bool? ?? true);
    }
  }

  // 原生的 onEnd 可能晚到：上一句刚好读完时用户又点了新的一句，
  // 那个迟到的 onEnd 带的是旧 id，不能把新的这句当成读完了
  void _finishIf(int id, bool ok) {
    if (id == _pendingId) _finish(ok);
  }

  void _finish(bool ok) {
    final completer = _pending;
    _pending = null;
    _pendingId = null;
    speaking.value = null;
    if (completer != null && !completer.isCompleted) completer.complete(ok);
  }

  @override
  void onClose() {
    _channel.setMethodCallHandler(null);
    super.onClose();
  }
}
