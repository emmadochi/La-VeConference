package org.lifechangerstouch.lavie

import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.util.Rational
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SCREEN_SHARE_CHANNEL = "org.lifechangerstouch.lavie/screen_share"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        try {
                            val intent = Intent(this, ScreenShareService::class.java)
                            ContextCompat.startForegroundService(this, intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("START_FAILED", e.message, null)
                        }
                    }
                    "stopService" -> {
                        try {
                            val intent = Intent(this, ScreenShareService::class.java).apply {
                                action = ScreenShareService.ACTION_STOP
                            }
                            startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {
                // Ignore if PiP not supported or not enabled in current state
            }
        }
    }
}
