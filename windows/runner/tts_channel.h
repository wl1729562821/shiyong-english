#ifndef RUNNER_TTS_CHANNEL_H_
#define RUNNER_TTS_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <wrl/client.h>

#include <memory>
#include <string>

struct ISpVoice;

// 用 Windows 自带的 SAPI 语音引擎朗读英文，通过 MethodChannel "travel_english/tts"
// 和 Dart 通信，协议和 Android 端（TtsHandler.kt）完全一样：
//
// Dart → 原生：getVoices / speak {text, speed, voiceId, id} / stop
// 原生 → Dart：onEnd {id, ok}，只在这一段自然读完时发，被 stop 或新的 speak 打断不发
//
// SAPI 的事件通过窗口消息 kSapiEventMessage 通知，FlutterWindow 收到后调用
// HandleSapiEvents，这样回调 Dart 时一定在平台线程上。
// （从 english_reader 的 tts_channel.cpp 精简而来，去掉了暂停和逐词高亮）
class TtsChannel {
 public:
  static constexpr UINT kSapiEventMessage = WM_APP + 1;

  TtsChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~TtsChannel();

  TtsChannel(const TtsChannel&) = delete;
  TtsChannel& operator=(const TtsChannel&) = delete;

  void HandleSapiEvents();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  flutter::EncodableList GetVoices();
  bool SetVoice(const std::wstring& token_id);
  // 立刻停止，清空正在读和排队的内容
  void Purge();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Microsoft::WRL::ComPtr<ISpVoice> voice_;
  std::wstring voice_id_;
  // 当前朗读的流编号，只转发这个流的事件；0 表示没有在读
  ULONG stream_ = 0;
  // Dart 传来的这一段的编号，读完时原样带回去
  int32_t speak_id_ = 0;
};

#endif  // RUNNER_TTS_CHANNEL_H_
