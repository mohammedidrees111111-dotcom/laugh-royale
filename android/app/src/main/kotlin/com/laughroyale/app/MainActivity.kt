package com.laughroyale.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var audioManager: AudioManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Main native bridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.laughroyale.app/native"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getPlatform" -> result.success("Android")
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NATIVE_ERROR", e.message, null)
            }
        }

        // Voice chat channel — handles speakerphone + audio focus
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.laughroyale.app/voice"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "enableSpeakerphone" -> {
                        val am = audioManager
                        if (am != null) {
                            am.mode = AudioManager.MODE_IN_COMMUNICATION
                            am.isSpeakerphoneOn = true
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val attrs = AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .build()
                                val focusRequest = AudioFocusRequest.Builder(
                                    AudioManager.AUDIOFOCUS_GAIN
                                )
                                    .setAudioAttributes(attrs)
                                    .setWillPause(false)
                                    .build()
                                am.requestAudioFocus(focusRequest)
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "disableSpeakerphone" -> {
                        audioManager?.let {
                            it.isSpeakerphoneOn = false
                            it.mode = AudioManager.MODE_NORMAL
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                it.abandonAudioFocusRequest(null)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("VOICE_ERROR", e.message, null)
            }
        }
    }
}
