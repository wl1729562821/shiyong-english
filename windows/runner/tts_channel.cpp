#include "tts_channel.h"

#include <flutter/standard_method_codec.h>

#pragma warning(push, 0)
#include <sapi.h>
#pragma warning(pop)

#include <algorithm>
#include <cmath>
#include <cwchar>
#include <set>

#include "utils.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

constexpr char kChannelName[] = "travel_english/tts";

// 第一个目录是 SAPI 桌面语音（Microsoft David Desktop、Zira Desktop）。
// 第二个是 Win10/11 的 OneCore 语音（Microsoft Mark、David、Zira，以及在系统设置里
// 额外安装的语音），SAPI 默认不会列出来，但可以直接拿它的 token 来朗读。
const wchar_t* const kVoiceCategories[] = {
    SPCAT_VOICES,
    L"HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech_OneCore\\Voices",
};

constexpr DWORD kSpeakFlags = SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int size = static_cast<int>(utf8.size());
  const int length =
      ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), size, nullptr, 0);
  std::wstring utf16(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), size, utf16.data(), length);
  return utf16;
}

const EncodableValue* FindArgument(const EncodableMap* args, const char* key) {
  if (args == nullptr) {
    return nullptr;
  }
  auto it = args->find(EncodableValue(key));
  return it == args->end() ? nullptr : &it->second;
}

std::string GetString(const EncodableMap* args, const char* key) {
  const EncodableValue* value = FindArgument(args, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : std::string();
}

int32_t GetInt(const EncodableMap* args, const char* key, int32_t fallback) {
  const EncodableValue* value = FindArgument(args, key);
  const auto* number = value ? std::get_if<int32_t>(value) : nullptr;
  return number ? *number : fallback;
}

double GetDouble(const EncodableMap* args, const char* key, double fallback) {
  const EncodableValue* value = FindArgument(args, key);
  const auto* number = value ? std::get_if<double>(value) : nullptr;
  return number ? *number : fallback;
}

// Dart 传的是倍速（1.0 = 正常），SAPI 要的是 -10 ~ 10 的整数。
// 实测 SAPI 的 ±10 大约是 2.95 倍 / 1/2.95 倍，按对数换算
long SapiRate(double speed) {
  if (speed <= 0) {
    return 0;
  }
  const double rate = 10.0 * std::log(speed) / std::log(2.95);
  return std::clamp(static_cast<long>(std::lround(rate)), -10L, 10L);
}

// 读 token 的属性，比如 Name = "Microsoft Zira Desktop"、Language = "409"
std::wstring GetAttribute(ISpObjectToken* token, const wchar_t* name) {
  ComPtr<ISpDataKey> attributes;
  if (FAILED(token->OpenKey(L"Attributes", &attributes))) {
    return std::wstring();
  }
  wchar_t* value = nullptr;
  if (FAILED(attributes->GetStringValue(name, &value))) {
    return std::wstring();
  }
  std::wstring result(value);
  ::CoTaskMemFree(value);
  return result;
}

// SAPI 的 Language 是十六进制 LCID，可能有多个，用分号隔开，比如 "409;9"。
// 取第一个转成 "en-US" 这样的名字
std::string LanguageTag(const std::wstring& lcids) {
  const LCID lcid = std::wcstoul(lcids.c_str(), nullptr, 16);
  wchar_t name[LOCALE_NAME_MAX_LENGTH] = {};
  if (lcid == 0 ||
      ::LCIDToLocaleName(lcid, name, LOCALE_NAME_MAX_LENGTH, 0) == 0) {
    return std::string();
  }
  return Utf8FromUtf16(name);
}

// 释放事件里附带的数据，和 sphelper.h 的 SpClearEvent 一样
void ClearEvent(SPEVENT& event) {
  switch (event.elParamType) {
    case SPET_LPARAM_IS_POINTER:
    case SPET_LPARAM_IS_STRING:
      ::CoTaskMemFree(reinterpret_cast<void*>(event.lParam));
      break;
    case SPET_LPARAM_IS_TOKEN:
    case SPET_LPARAM_IS_OBJECT:
      reinterpret_cast<IUnknown*>(event.lParam)->Release();
      break;
    default:
      break;
  }
}

}  // namespace

TtsChannel::TtsChannel(flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  // main.cpp 里已经 CoInitializeEx 过，这里直接创建 COM 对象
  if (SUCCEEDED(::CoCreateInstance(
          CLSID_SpVoice, nullptr, CLSCTX_ALL,
          IID_PPV_ARGS(voice_.ReleaseAndGetAddressOf())))) {
    const ULONGLONG interest = SPFEI(SPEI_END_INPUT_STREAM);
    voice_->SetInterest(interest, interest);
    voice_->SetNotifyWindowMessage(window, kSapiEventMessage, 0, 0);
  }

  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

TtsChannel::~TtsChannel() {
  channel_->SetMethodCallHandler(nullptr);
  if (voice_) {
    voice_->SetNotifySink(nullptr);
    Purge();
  }
}

void TtsChannel::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!voice_) {
    result->Error("no_engine", "无法创建 Windows 语音引擎（SAPI）");
    return;
  }
  const std::string& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (method == "getVoices") {
    result->Success(EncodableValue(GetVoices()));
  } else if (method == "speak") {
    Purge();
    const std::wstring voice_id = Utf16FromUtf8(GetString(args, "voiceId"));
    // 发音人没变就不重复设置；空字符串表示用系统默认发音人
    if (!voice_id.empty() && voice_id != voice_id_) {
      if (!SetVoice(voice_id)) {
        result->Error("voice_failed", "切换发音人失败");
        return;
      }
      voice_id_ = voice_id;
    }
    voice_->SetRate(SapiRate(GetDouble(args, "speed", 1.0)));
    speak_id_ = GetInt(args, "id", 0);
    const std::wstring text = Utf16FromUtf8(GetString(args, "text"));
    ULONG stream = 0;
    const HRESULT hr = voice_->Speak(text.c_str(), kSpeakFlags, &stream);
    if (FAILED(hr)) {
      result->Error("speak_failed", "朗读失败，HRESULT = " + std::to_string(hr));
      return;
    }
    stream_ = stream;
    result->Success();
  } else if (method == "stop") {
    Purge();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void TtsChannel::Purge() {
  stream_ = 0;
  voice_->Speak(nullptr, SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
  // 等清空完成，再把被清掉那段留在队列里的事件（比如 END）全部丢掉。
  // SAPI 的流编号是按队列算的，清空后新的 Speak 又从 1 开始，
  // 不丢掉的话，旧的 END 会被当成新内容读完了
  voice_->WaitUntilDone(1000);
  SPEVENT event = {};
  ULONG fetched = 0;
  while (voice_->GetEvents(1, &event, &fetched) == S_OK && fetched == 1) {
    ClearEvent(event);
  }
}

EncodableList TtsChannel::GetVoices() {
  EncodableList voices;
  std::set<std::wstring> ids;
  for (const wchar_t* category_id : kVoiceCategories) {
    ComPtr<ISpObjectTokenCategory> category;
    ComPtr<IEnumSpObjectTokens> tokens;
    if (FAILED(::CoCreateInstance(
            CLSID_SpObjectTokenCategory, nullptr, CLSCTX_ALL,
            IID_PPV_ARGS(category.ReleaseAndGetAddressOf()))) ||
        FAILED(category->SetId(category_id, FALSE)) ||
        FAILED(category->EnumTokens(nullptr, nullptr, &tokens))) {
      continue;
    }

    ComPtr<ISpObjectToken> token;
    while (tokens->Next(1, token.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
      wchar_t* id = nullptr;
      if (FAILED(token->GetId(&id))) {
        continue;
      }
      const std::wstring token_id(id);
      ::CoTaskMemFree(id);
      if (!ids.insert(token_id).second) {
        continue;
      }

      std::wstring name = GetAttribute(token.Get(), L"Name");
      if (name.empty()) {
        name = token_id.substr(token_id.find_last_of(L'\\') + 1);
      }
      voices.push_back(EncodableValue(EncodableMap{
          {EncodableValue("id"), EncodableValue(Utf8FromUtf16(token_id.c_str()))},
          {EncodableValue("name"), EncodableValue(Utf8FromUtf16(name.c_str()))},
          {EncodableValue("language"),
           EncodableValue(LanguageTag(GetAttribute(token.Get(), L"Language")))},
      }));
    }
  }
  return voices;
}

bool TtsChannel::SetVoice(const std::wstring& token_id) {
  ComPtr<ISpObjectToken> token;
  return SUCCEEDED(::CoCreateInstance(
             CLSID_SpObjectToken, nullptr, CLSCTX_ALL,
             IID_PPV_ARGS(token.ReleaseAndGetAddressOf()))) &&
         SUCCEEDED(token->SetId(nullptr, token_id.c_str(), FALSE)) &&
         SUCCEEDED(voice_->SetVoice(token.Get()));
}

void TtsChannel::HandleSapiEvents() {
  if (!voice_) {
    return;
  }
  SPEVENT event = {};
  ULONG fetched = 0;
  while (voice_->GetEvents(1, &event, &fetched) == S_OK && fetched == 1) {
    if (stream_ != 0 && event.ulStreamNum == stream_ &&
        event.eEventId == SPEI_END_INPUT_STREAM) {
      stream_ = 0;
      channel_->InvokeMethod(
          "onEnd", std::make_unique<EncodableValue>(EncodableMap{
                       {EncodableValue("id"), EncodableValue(speak_id_)},
                       {EncodableValue("ok"), EncodableValue(true)},
                   }));
    }
    ClearEvent(event);
  }
}
