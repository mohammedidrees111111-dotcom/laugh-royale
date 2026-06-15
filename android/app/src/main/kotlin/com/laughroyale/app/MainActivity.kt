package com.laughroyale.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Safe MethodChannel — handles native calls without crashing
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
    }
}
