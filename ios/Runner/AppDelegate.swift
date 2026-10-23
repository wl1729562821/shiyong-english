import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var tts: TtsHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      tts = TtsHandler(messenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// 用 iOS 自带的 AVSpeechSynthesizer 朗读英文，MethodChannel "travel_english/tts"，
/// 协议和 Android（TtsHandler.kt）、Windows（tts_channel.cpp）完全一样：
///
/// Dart → 原生：getVoices / speak {text, speed, voiceId, id} / stop
/// 原生 → Dart：onEnd {id, ok}，只在当前这一段读完时发，被 stop 或新的 speak 打断的那段不发
final class TtsHandler: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  // 必须一直持有，局部变量的 synthesizer 会被释放，读到一半就没声了
  private let synthesizer = AVSpeechSynthesizer()

  // 当前这一段；被打断后置空，旧的回调就会被忽略
  private var current: AVSpeechUtterance?
  private var currentId = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "travel_english/tts", binaryMessenger: messenger)
    super.init()
    synthesizer.delegate = self
    // 默认的音频类别会被手机侧面的静音开关静音；学英语时大多开着静音，所以用 playback
    try? AVAudioSession.sharedInstance().setCategory(
      .playback, mode: .spokenAudio, options: [.duckOthers])
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getVoices":
      result(englishVoices())
    case "speak":
      speak(call.arguments as? [String: Any] ?? [:], result: result)
    case "stop":
      current = nil
      synthesizer.stopSpeaking(at: .immediate)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func speak(_ args: [String: Any], result: FlutterResult) {
    let text = args["text"] as? String ?? ""
    let speed = args["speed"] as? Double ?? 1.0
    let voiceId = args["voiceId"] as? String ?? ""
    let id = args["id"] as? Int ?? 0

    // 先打断正在读的。被打断的那段走 didCancel，不会发 onEnd
    current = nil
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: text)
    // 没选发音人，或选的发音人在这台手机上没有，就用系统的美式英语
    utterance.voice =
      (voiceId.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: voiceId))
      ?? AVSpeechSynthesisVoice(language: "en-US")
    // Dart 传的是倍速（1.0 = 正常）；iOS 的 rate 是 0~1，正常是 0.5
    let rate = Float(speed) * AVSpeechUtteranceDefaultSpeechRate
    utterance.rate = min(
      max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)

    current = utterance
    currentId = id
    try? AVAudioSession.sharedInstance().setActive(true)
    synthesizer.speak(utterance)
    result(nil)
  }

  /// 本机的英文发音人。去掉 Albert、Bells 这类搞怪音效声音和 Eloquence 合成声音，
  /// 只留正常的（Samantha、Daniel 等，以及在设置里下载的增强版）
  private func englishVoices() -> [[String: String]] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { voice in
        voice.language.hasPrefix("en")
          && !voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.")
          && !voice.identifier.hasPrefix("com.apple.eloquence.")
      }
      .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
      .map {
        [
          "id": $0.identifier, "name": $0.name, "language": $0.language,
          "quality": qualityName($0),
        ]
      }
  }

  /// 同名的声音可能有压缩版和增强版（比如两个 Samantha），设置页靠它区分
  private func qualityName(_ voice: AVSpeechSynthesisVoice) -> String {
    if #available(iOS 16.0, *), voice.quality == .premium { return "premium" }
    return voice.quality == .enhanced ? "enhanced" : "default"
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self, utterance === self.current else { return }
      self.current = nil
      self.channel.invokeMethod("onEnd", arguments: ["id": self.currentId, "ok": true])
    }
  }
}
