package com.safefamily.app

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager

/**
 * Trạng thái các quyền SafeFamily, tính từ [Context] nên chạy được cả ở dịch vụ nền
 * ([FamilySync] báo về máy mẹ) lẫn trong [MainActivity]. Khóa trùng
 * `AppPermission.id` phía Dart (lib/core/permissions/permission_registry.dart).
 */
object PermissionStatus {
    const val SETTINGS_GUARD_SERVICE = "com.safefamily.app.SettingsGuardService"
    private const val BLOCKER_SERVICE =
        "com.khanhtq.app_blocker.blocking.AppBlockerAccessibilityService"

    /** Micro chỉ phục vụ báo thức giọng nói, không liên quan giám sát nên không báo mẹ là "thiếu quyền". */
    private val NOT_REPORTED = setOf("microphone")

    fun snapshot(context: Context): Map<String, Boolean> = mapOf(
        "accessibility" to isBlockerServiceEnabled(context),
        "settings_guard" to isServiceRunning(context, SETTINGS_GUARD_SERVICE),
        "usage_access" to TimeLimits.hasUsageAccess(context),
        "notifications" to areNotificationsEnabled(context),
        "exact_alarm" to canScheduleExactAlarms(context),
        "battery" to isIgnoringBatteryOptimizations(context),
        "device_admin" to isDeviceAdminActive(context),
        "microphone" to (
            context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            ),
    )

    /** Id các quyền còn thiếu, đã bỏ quyền không liên quan giám sát. */
    fun missing(context: Context): List<String> =
        snapshot(context).filter { (id, granted) -> !granted && id !in NOT_REPORTED }.keys.toList()

    fun areNotificationsEnabled(context: Context): Boolean =
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()

    fun canScheduleExactAlarms(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()

    fun isIgnoringBatteryOptimizations(context: Context): Boolean =
        (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .isIgnoringBatteryOptimizations(context.packageName)

    fun isDeviceAdminActive(context: Context): Boolean =
        (context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager)
            .isAdminActive(ComponentName(context, SafeFamilyAdminReceiver::class.java))

    /** Dịch vụ Trợ năng [className] của SafeFamily đang chạy thật. */
    fun isServiceRunning(context: Context, className: String): Boolean {
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.let { s -> s.packageName == context.packageName && s.name == className } }
    }

    /**
     * Dịch vụ Trợ năng của app_blocker đang CHẠY thật. Chỉ xem danh sách bật trong Cài đặt là chưa đủ:
     * tiến trình bị tắt hẳn (vuốt khỏi đa nhiệm trên MIUI, cài lại app) thì Android đánh dấu dịch vụ
     * "đã crash", vẫn nằm trong danh sách bật nhưng không chạy lại cho tới khi tắt/bật lại.
     */
    fun isBlockerServiceEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val service = ComponentName(context.packageName, BLOCKER_SERVICE)
        val listed = TextUtils.SimpleStringSplitter(':').apply { setString(enabled) }
            .any { it.equals(service.flattenToString(), ignoreCase = true) }
        return listed && isServiceRunning(context, BLOCKER_SERVICE)
    }
}
