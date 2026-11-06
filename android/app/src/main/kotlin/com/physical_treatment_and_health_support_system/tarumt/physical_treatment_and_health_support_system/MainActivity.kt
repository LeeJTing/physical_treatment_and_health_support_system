package com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: the health plugin's Health Connect permission request needs a
// ComponentActivity (M200).
class MainActivity : FlutterFragmentActivity() {
    // Opens HealthGuide's notification settings (Reminders > "Turn on notifications"): after two
    // refusals Android no longer shows its permission dialog, so Settings is the only way back.
    // Used by PluginScheduler.openSettings() in lib/device_platform.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apths/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openHealthConnectPermissions") {
                    result.success(openHealthConnectPermissions())
                    return@setMethodCallHandler
                }
                if (call.method != "openNotificationSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                } else {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                }
                try {
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }

    // Health Connect's page where HealthGuide's read access can be allowed again (M200): on
    // Android 14+ the app's own permission page inside Settings, before that the Health Connect app.
    private fun openHealthConnectPermissions(): Boolean {
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= 34) {
                add(Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS")
                    .putExtra(Intent.EXTRA_PACKAGE_NAME, packageName))
            }
            add(Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"))
            add(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"))
        }
        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try the next one.
            }
        }
        return false
    }
}
