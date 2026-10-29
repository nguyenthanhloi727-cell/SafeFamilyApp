package com.safefamily.app

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AlarmManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import android.text.TextUtils
import android.view.accessibility.AccessibilityManager
import com.khanhtq.app_blocker.blocking.AppBlockerAccessibilityService
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
                    "disableAccessibility" -> disableBlockerService(result)
                    "rememberRelock" -> {
                        TempRelocks.remember(
                            this,
                            call.argument<String>("package")!!,
                            call.argument<Number>("atMillis")!!.toLong(),
                        )
                        result.success(null)
                    }
                    "forgetRelock" -> {
                        TempRelocks.forget(this, call.argument<String>("package")!!)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        timeLimitChannel(messenger)
        newAppsChannel(messenger)
        permissionsChannel(messenger)
        // Chống bypass: đồng hồ không chỉnh được, bảo vệ màn Cài đặt, Device Admin.
        MethodChannel(messenger, "safefamily/guard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "clock" -> result.success(
                        mapOf(
                            "elapsedMillis" to GuardPrefs.elapsedNow(),
                            "bootCount" to GuardPrefs.bootCount(this),
                        ),
                    )
                    "status" -> result.success(
                        mapOf(
                            "guardService" to isServiceRunning(SETTINGS_GUARD_SERVICE),
                            "deviceAdmin" to isDeviceAdminActive(),
                        ),
                    )
                    "setProtection" -> {
                        GuardPrefs.setProtectionEnabled(this, call.arguments as Boolean)
                        result.success(null)
                    }
                    "allowSettings" -> {
                        GuardPrefs.allowSettings(this, (call.arguments as Number).toLong())
                        result.success(null)
                    }
                    "setContacts" -> {
                        val list = (call.arguments as List<*>).map {
                            val m = it as Map<*, *>
                            GuardPrefs.Contact(
                                m["label"] as String,
                                m["phone"] as String,
                                m["emergency"] as Boolean,
                            )
                        }
                        GuardPrefs.setContacts(this, list)
                        result.success(null)
                    }
                    "consumeChallenge" -> result.success(GuardPrefs.consumeChallenge(this))
                    "consumeExtraTime" -> result.success(GuardPrefs.consumeExtraTime(this))
                    "requestDeviceAdmin" -> {
                        startActivity(
                            Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent())
                                .putExtra(
                                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                    "Bật để con không gỡ được SafeFamily.",
                                ),
                        )
                        result.success(null)
                    }
                    "setSecure" -> {
                        if (call.arguments as Boolean) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleReviewIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleReviewIntent(intent)
    }

    /** Bấm thông báo "Con vừa cài app X": Dart mở màn duyệt khi app hiện lên. */
    private fun handleReviewIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(NewApps.EXTRA_REVIEW, false) == true) {
            NewApps.setReviewRequested(this, true)
        }
    }

    private fun newAppsChannel(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, "safefamily/new_apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enabled" -> result.success(NewApps.enabled(this))
                    "setEnabled" -> {
                        NewApps.setEnabled(this, call.arguments as Boolean)
                        result.success(null)
                    }
                    "pending" -> {
                        NewApps.scan(this, force = true)
                        result.success(
                            NewApps.pending(this).map {
                                mapOf("package" to it, "label" to NewApps.label(this, it))
                            },
                        )
                    }
                    "approve" -> {
                        NewApps.approve(this, call.arguments as String)
                        result.success(null)
                    }
                    "rejected" -> result.success(
                        NewApps.rejected(this).map {
                            mapOf("package" to it, "label" to NewApps.label(this, it))
                        },
                    )
                    "reject" -> {
                        NewApps.reject(this, call.arguments as String)
                        result.success(null)
                    }
                    "consumeReview" -> result.success(NewApps.consumeReviewRequest(this))
                    "notificationsAllowed" -> result.success(notificationsAllowed())
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Quyền SafeFamily đang dùng: trạng thái + mở đúng trang Cài đặt. Dart
     * (PermissionRegistry) giữ danh sách id; chỗ này dùng lại các hàm kiểm tra
     * sẵn có nên không nhân đôi nguồn dữ liệu.
     */
    private fun permissionsChannel(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, "safefamily/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "accessibility" to isBlockerServiceEnabled(),
                            "settings_guard" to isServiceRunning(SETTINGS_GUARD_SERVICE),
                            "usage_access" to TimeLimits.hasUsageAccess(this),
                            "notifications" to areNotificationsEnabled(),
                            "exact_alarm" to canScheduleExactAlarms(),
                            "battery" to isIgnoringBatteryOptimizations(),
                            "device_admin" to isDeviceAdminActive(),
                            "microphone" to (
                                checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                                    PackageManager.PERMISSION_GRANTED
                                ),
                        ),
                    )
                    "openSettings" -> {
                        val intent = permissionSettingsIntent(call.argument<String>("id"))
                        if (intent == null) {
                            result.success(false)
                        } else {
                            // Các trang này liệt kê "SafeFamily": cho vào cửa trước,
                            // nếu không dịch vụ bảo vệ sẽ hỏi PIN lần nữa.
                            GuardPrefs.allowSettings(this, SETTINGS_ALLOW_SECONDS)
                            result.success(startSettings(intent))
                        }
                    }
                    // Tắt thẳng, không cần mở Cài đặt. Dart phải xác thực phụ huynh trước.
                    "removeDeviceAdmin" -> {
                        runCatching {
                            (getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager)
                                .removeActiveAdmin(adminComponent())
                        }
                        result.success(!isDeviceAdminActive())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun permissionSettingsIntent(id: String?): Intent? {
        val packageUri = android.net.Uri.parse("package:$packageName")
        val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
        return when (id) {
            "accessibility", "settings_guard" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "usage_access" -> TimeLimits.usageAccessIntent(this)
            "notifications" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                } else {
                    appDetails
                }
            "exact_alarm" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri)
                } else {
                    appDetails
                }
            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            "device_admin" ->
                if (isDeviceAdminActive()) {
                    Intent(Settings.ACTION_SECURITY_SETTINGS)
                } else {
                    Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                        .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent())
                        .putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            "Bật để con không gỡ được SafeFamily.",
                        )
                }
            "microphone" -> appDetails
            else -> null
        }
    }

    /** `false` nếu máy không có màn hình đó (một số ROM bỏ trang riêng). */
    private fun startSettings(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: android.content.ActivityNotFoundException) {
        false
    }

    /** Khác [notificationsAllowed]: tính cả khi người dùng tắt thông báo của app trong Cài đặt. */
    private fun areNotificationsEnabled(): Boolean =
        (getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
            .areNotificationsEnabled()

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun timeLimitChannel(messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, "safefamily/time_limit")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "config" -> result.success(TimeLimits.config(this))
                    "setConfig" -> try {
                        TimeLimits.setConfig(this, call.arguments as String)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("bad_config", e.message, null)
                    }
                    "usageAccess" -> result.success(TimeLimits.hasUsageAccess(this))
                    "openUsageAccess" -> {
                        startActivity(TimeLimits.usageAccessIntent(this))
                        result.success(null)
                    }
                    "usageToday" -> {
                        val usage = TimeLimits.usageToday(this)
                        if (usage == null) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "totalMinutes" to (usage.total / 60_000L).toInt(),
                                    "apps" to usage.perApp.mapValues { (it.value / 60_000L).toInt() },
                                ),
                            )
                        }
                    }
                    "usageReport" -> result.success(
                        UsageReport.report(this, (call.arguments as Number).toInt()),
                    )
                    "appLabels" -> result.success(
                        UsageReport.labels(this, (call.arguments as List<*>).map { it.toString() }),
                    )
                    "timeJumps" -> result.success(TimeLimits.timeJumps(this))
                    "bonusMinutes" -> result.success(TimeLimits.bonusMinutes(this))
                    "addBonus" -> try {
                        result.success(TimeLimits.addBonus(this, (call.arguments as Number).toInt()))
                    } catch (e: IllegalArgumentException) {
                        result.error("bad_minutes", e.message, null)
                    }
                    "studyStatus" -> result.success(
                        mapOf(
                            "active" to TimeLimits.studyActive(this),
                            "sessionMinutesLeft" to TimeLimits.studySessionMinutesLeft(this),
                            "disabledToday" to TimeLimits.studyDisabledToday(this),
                        ),
                    )
                    "startStudy" -> try {
                        TimeLimits.startStudySession(this, (call.arguments as Number).toInt())
                        result.success(null)
                    } catch (e: IllegalArgumentException) {
                        result.error("bad_minutes", e.message, null)
                    }
                    "stopStudy" -> {
                        TimeLimits.stopStudySession(this)
                        result.success(null)
                    }
                    "pauseStatus" -> result.success(TimeLimits.pauseMinutesLeft(this))
                    "startPause" -> try {
                        TimeLimits.startPause(this, (call.arguments as Number).toInt())
                        result.success(null)
                    } catch (e: IllegalArgumentException) {
                        result.error("bad_minutes", e.message, null)
                    }
                    "stopPause" -> {
                        TimeLimits.stopPause(this)
                        result.success(null)
                    }
                    "limitDisabledUntil" -> result.success(TimeLimits.limitDisabledUntil(this))
                    "setTotalLimitDisabledToday" -> {
                        TimeLimits.setTotalLimitDisabledToday(this, call.arguments as Boolean)
                        result.success(null)
                    }
                    "setStudyDisabledToday" -> {
                        TimeLimits.setStudyDisabledToday(this, call.arguments as Boolean)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun adminComponent() = ComponentName(this, SafeFamilyAdminReceiver::class.java)

    private fun isDeviceAdminActive(): Boolean =
        (getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager)
            .isAdminActive(adminComponent())

    /** Dịch vụ Trợ năng [className] của SafeFamily đang chạy thật (xem [isBlockerServiceEnabled]). */
    private fun isServiceRunning(className: String): Boolean {
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.let { s -> s.packageName == packageName && s.name == className } }
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

    /**
     * Tắt dịch vụ Trợ năng chặn app bằng `disableSelf()` (API 24+), rồi đọc lại
     * trạng thái. Trả `true` nếu dịch vụ thật sự đã tắt; `false` nếu máy không
     * cho (dịch vụ không chạy, API thấp, ROM chặn) để Dart mở Cài đặt như cũ.
     * TODO(verify): hãng khác Xiaomi có thể bỏ qua disableSelf().
     */
    private fun disableBlockerService(result: MethodChannel.Result) {
        val service = AppBlockerAccessibilityService.instance
        if (service == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.success(!isBlockerServiceEnabled())
            return
        }
        runCatching { service.disableSelf() }
        Handler(Looper.getMainLooper()).postDelayed(
            { result.success(!isBlockerServiceEnabled()) },
            DISABLE_RECHECK_MS,
        )
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
    private fun protectedPackages(): Set<String> = TimeLimits.exemptPackages(this)

    companion object {
        private const val DISABLE_RECHECK_MS = 500L
        private const val SETTINGS_ALLOW_SECONDS = 180L // = settingsAllowSeconds (Dart)
        private const val SETTINGS_GUARD_SERVICE = "com.safefamily.app.SettingsGuardService"
        private const val BLOCKER_SERVICE =
            "com.khanhtq.app_blocker.blocking.AppBlockerAccessibilityService"
    }
}
