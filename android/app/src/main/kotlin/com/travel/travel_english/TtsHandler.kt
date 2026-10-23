package com.travel.travel_english

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * 用 Android 系统的 TextToSpeech 朗读英文，MethodChannel "travel_english/tts"，
 * 协议和 Windows 端（windows/runner/tts_channel.cpp）完全一样：
 *
 * Dart → 原生：getVoices / speak {text, speed, voiceId, id} / stop
 * 原生 → Dart：onEnd {id, ok}，只在当前这一段读完（或出错）时发，
 *             被 stop 或新的 speak 打断的那一段不发。
 *
 * 没用 flutter_tts 插件：它的 Windows 端编译要 nuget，这台电脑没有；
 * 两端都手写通道，Dart 层只需要一套代码。
 */
class TtsHandler(context: Context, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler, TextToSpeech.OnInitListener {

    private val main = Handler(Looper.getMainLooper())

    // TextToSpeech 是异步初始化的，初始化完成前收到的调用先排队
    private var initDone = false
    private var ready = false
    private val pending = mutableListOf<() -> Unit>()

    private val tts = TextToSpeech(context.applicationContext, this)

    // 当前这一段的 utteranceId 和 Dart 传来的 id；被打断后置空，旧的回调就会被忽略
    private var currentUtterance: String? = null
    private var currentId = 0
    private var appliedVoice: String? = null

    init {
        channel.setMethodCallHandler(this)
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) {}

            // 这三个回调都在 TTS 的后台线程，切回主线程再碰 channel
            override fun onDone(utteranceId: String) {
                main.post { finished(utteranceId, true) }
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String) {
                main.post { finished(utteranceId, false) }
            }

            override fun onError(utteranceId: String, errorCode: Int) {
                main.post { finished(utteranceId, false) }
            }
        })
    }

    override fun onInit(status: Int) {
        // onInit 在主线程回调
        initDone = true
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
            tts.language = Locale.US
        }
        pending.forEach { it() }
        pending.clear()
    }

    private fun whenReady(result: MethodChannel.Result, action: () -> Unit) {
        val run = {
            if (ready) {
                action()
            } else {
                result.error("no_engine", "系统没有可用的文字转语音引擎", null)
            }
        }
        if (initDone) run() else pending.add(run)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getVoices" -> whenReady(result) { result.success(englishVoices()) }
            "speak" -> whenReady(result) { speak(call, result) }
            "stop" -> {
                currentUtterance = null
                if (ready) tts.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        val speed = call.argument<Double>("speed") ?: 1.0
        val voiceId = call.argument<String>("voiceId")
        val id = call.argument<Int>("id") ?: 0

        if (voiceId != appliedVoice) {
            val voice = if (voiceId.isNullOrEmpty()) null
            else tts.voices?.firstOrNull { it.name == voiceId }
            // 找不到指定的发音人（比如换了引擎）就退回美式英语默认发音人
            if (voice != null) tts.voice = voice else tts.language = Locale.US
            appliedVoice = voiceId
        }
        tts.setSpeechRate(speed.toFloat())

        val utterance = "u$id"
        currentUtterance = utterance
        currentId = id
        // QUEUE_FLUSH：打断正在读的内容。被打断的那段回调 onStop，不会走 onDone
        val code = tts.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), utterance)
        if (code == TextToSpeech.ERROR) {
            currentUtterance = null
            result.error("speak_failed", "朗读失败", null)
        } else {
            result.success(null)
        }
    }

    private fun finished(utteranceId: String, ok: Boolean) {
        if (utteranceId != currentUtterance) return
        currentUtterance = null
        channel.invokeMethod("onEnd", mapOf("id" to currentId, "ok" to ok))
    }

    /** 本机已安装、不需要联网的英文发音人 */
    private fun englishVoices(): List<Map<String, String>> {
        val voices = try {
            tts.voices
        } catch (e: Exception) {
            // 个别厂商的引擎在 getVoices 里会抛异常
            null
        } ?: return emptyList()
        return voices
            .filter { voice ->
                voice.locale.language == "en" &&
                    !voice.isNetworkConnectionRequired &&
                    voice.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) != true
            }
            .sortedWith(compareBy({ it.locale.toLanguageTag() }, { it.name }))
            .map {
                mapOf(
                    "id" to it.name,
                    "name" to it.name,
                    "language" to it.locale.toLanguageTag(),
                )
            }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        currentUtterance = null
        tts.stop()
        tts.shutdown()
    }
}
