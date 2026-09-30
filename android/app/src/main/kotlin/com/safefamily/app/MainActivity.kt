package com.safefamily.app

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telecom.TelecomManager
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// biometric_storage yêu cầu FlutterFragmentActivity (hộp thoại BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Cho Dart biết máy có phần cứng vân tay / khuôn mặt hay không
        // (biometric_storage chỉ báo dùng được hay không, không báo vân tay hay khuôn mặt).
        MethodChannel(messenger, "safefamily/biometric_hardware")
            .setMethodCallHandler { call, result ->
                if (call.method == "features") {
                    val pm = packageManager
                    val atLeastQ = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    result.success(
                        mapOf(
                            "fingerprint" to pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT),
                            "face" to (atLeastQ && pm.hasSystemFeature(PackageManager.FEATURE_FACE)),
                            "iris" to (atLeastQ && pm.hasSystemFeature(PackageManager.FEATURE_IRIS)),
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }
        // Khóa ứng dụng: trạng thái từng quyền + app không được chặn.
        MethodChannel(messenger, "safefamily/app_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissions" -> result.success(
                        mapOf(
                            "accessibility" to isBlockerServiceEnabled(),
                            "exactAlarm" to canScheduleExactAlarms(),
                            "battery" to isIgnoringBatteryOptimizations(),
                        ),
                    )
                    "protectedPackages" -> result.success(protectedPackages().toList())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Dịch vụ Trợ năng của app_blocker đang CHẠY thật. Chỉ xem danh sách bật
     * trong Cài đặt là chưa đủ: tiến trình bị tắt hẳn (vuốt khỏi đa nhiệm trên
     * MIUI, cài lại app) thì Android đánh dấu dịch vụ "đã crash", vẫn nằm trong
     * danh sách bật nhưng không chạy lại cho tới khi tắt/bật lại.
     */
    private fun isBlockerServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val service = ComponentName(packageName, BLOCKER_SERVICE)
        val listed = TextUtils.SimpleStringSplitter(':').apply { setString(enabled) }
            .any { it.equals(service.flattenToString(), ignoreCase = true) }
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val running = manager
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.let { s -> s.packageName == packageName && s.name == BLOCKER_SERVICE } }
        return listed && running
    }

    private fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            (getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()

    private fun isIgnoringBatteryOptimizations(): Boolean =
        (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .isIgnoringBatteryOptimizations(packageName)

    /**
     * App Điện thoại, Cài đặt, trình khởi động (launcher) của máy này — hỏi
     * Android xem app nào nhận các lệnh đó, không ghi cứng theo hãng.
     */
    private fun protectedPackages(): Set<String> {
        val pm = packageManager
        val intents = listOf(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:")),
            Intent(Settings.ACTION_SETTINGS),
        )
        val packages = mutableSetOf(packageName)
        for (intent in intents) {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0).mapTo(packages) { it.activityInfo.packageName }
        }
        runCatching {
            (getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage
        }.getOrNull()?.let(packages::add)
        return packages
    }

    companion object {
        private const val BLOCKER_SERVICE =
            "com.khanhtq.app_blocker.blocking.AppBlockerAccessibilityService"
    }
}
