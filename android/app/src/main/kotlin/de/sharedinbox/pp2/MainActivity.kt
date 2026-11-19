package de.sharedinbox.pp2

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // For bug reports (lib/net/device_info.dart): what the report screen
    // shows and sends, nothing else.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "de.sharedinbox.pp2/device",
        ).setMethodCallHandler { call, result ->
            if (call.method != "info") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val version = try {
                packageManager.getPackageInfo(packageName, 0).versionName ?: ""
            } catch (e: Exception) {
                ""
            }
            result.success(
                mapOf(
                    "app" to version,
                    "phone" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "android" to "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
                ),
            )
        }
        // Speaking counts like touching (lib/game/screen_awake.dart): kept
        // on while the child talks. Clearing the flag pokes the idle timer
        // (the window manager's wake lock is ON_AFTER_RELEASE), so the
        // usual screen timeout starts from the last word.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "de.sharedinbox.pp2/screen",
        ).setMethodCallHandler { call, result ->
            if (call.method != "keepOn") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            if (call.arguments == true) window.addFlags(flag) else window.clearFlags(flag)
            result.success(null)
        }
    }
}
