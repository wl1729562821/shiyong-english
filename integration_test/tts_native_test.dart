import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_english/services/progress_service.dart';
import 'package:travel_english/services/tts_service.dart';

/// 在真机上调用真正的语音引擎（Windows: SAPI，Android: TextToSpeech），
/// 检查 Dart 层“读完返回 true / 被打断返回 false”的约定和原生实现对得上。
///
/// flutter test integration_test/tts_native_test.dart -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实语音引擎：读完、打断、停止、慢速', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Get.put(await ProgressService.create());
    final tts = Get.put(TtsService());
    await tts.loadVoices();
    expect(tts.problem.value, isNull, reason: '没有可用的英文发音人');
    expect(tts.voices, isNotEmpty);
    // 没选发音人时也必须是英文发音人（Windows 中文系统的默认发音人是中文的 Huihui）
    final fallback = tts.defaultVoice;
    if (fallback != null) expect(fallback.language.toLowerCase(), 'en-us');
    // ignore: avoid_print
    print(
        'voices: ${tts.voices.map((v) => '${v.language} ${v.name}').join(' | ')}');

    Future<(bool, Duration)> timed(Future<bool> Function() action) async {
      final sw = Stopwatch()..start();
      final ok = await action();
      return (ok, sw.elapsed);
    }

    // 1. 正常读完：返回 true，而且确实花了时间
    final (ok, normal) =
        await timed(() => tts.say('May I see your passport, please?'));
    expect(ok, isTrue);
    expect(normal, greaterThan(const Duration(milliseconds: 800)));
    expect(tts.speaking.value, isNull);

    // 2. 慢速明显更慢
    final (okSlow, slow) = await timed(
        () => tts.say('May I see your passport, please?', speed: 0.6));
    expect(okSlow, isTrue);
    expect(slow, greaterThan(normal * 1.2));

    // 3. 读到一半被新的一句打断：旧的返回 false，新的返回 true
    final first = tts.say(
        'This is a long sentence that will be interrupted before it is finished.');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final second = tts.say('Thank you.');
    expect(await first, isFalse);
    expect(await second, isTrue);

    // 4. stop：立即返回 false，之后不会有迟到的 onEnd 把状态弄乱
    final third = tts
        .say('Another long sentence that we are going to stop in the middle.');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tts.stop();
    expect(await third, isFalse);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(tts.speaking.value, isNull);

    // 5. 换一个发音人也能读
    final other = tts.voices.last;
    ProgressService.to.setVoice(other.id);
    expect(await tts.say('Have a nice day!'), isTrue);

    // 6. 连续播放：中途 stop 后循环退出
    final seq = tts.beginSequence();
    expect(await tts.sayInSequence(seq, 'One.'), isTrue);
    await tts.stop();
    expect(await tts.sayInSequence(seq, 'Two.'), isFalse);
    // ignore: avoid_print
    print('normal ${normal.inMilliseconds}ms, slow ${slow.inMilliseconds}ms');
  });
}
