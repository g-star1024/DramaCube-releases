package com.dramacube.dramacube

import android.app.UiModeManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dramacube/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTV" -> {
                        val uiModeManager = getSystemService(UI_MODE_SERVICE) as UiModeManager
                        result.success(uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
