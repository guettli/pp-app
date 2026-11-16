package de.sharedinbox.pp2

import android.os.Build
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
    }
}
