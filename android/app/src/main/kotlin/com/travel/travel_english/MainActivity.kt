package com.travel.travel_english

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tts: TtsHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "travel_english/tts")
        tts = TtsHandler(this, channel)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        tts?.dispose()
        tts = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
