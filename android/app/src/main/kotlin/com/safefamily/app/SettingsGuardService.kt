package com.safefamily.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.khanhtq.app_blocker.blocking.AppBlockerAccessibilityService

/**
 * Chặn đường xóa dữ liệu / tắt Trợ năng / tắt quản trị thiết bị / gỡ SafeFamily.
 *
 * Khi một màn của Cài đặt (hoặc trình cài đặt, Play Store) đang hiện chữ
 * "SafeFamily" và phụ huynh chưa xác thực: về màn hình chính rồi mở SafeFamily
 * ở chế độ hỏi PIN. Xác thực đúng thì Dart gọi `allowSettings` để mở cửa
 * một khoảng ngắn.
 *
 * Nhận diện theo tên gói + tên app trên màn hình (tên app không bị dịch theo
 * ngôn ngữ, khác với tên nút) nên vẫn có thể lọt ở ROM lạ chưa có trong
 * [GUARDED_PACKAGES].
 */
class SettingsGuardService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var lastScan = 0L

    private val ticker = object : Runnable {
        override fun run() {
            enforceTimeLimits(null)
            handler.postDelayed(this, nextTickMs)
        }
    }

    private var lastBlockAt = 0L

    /** Gần hết giờ thì đo dày hơn để cảnh báo đúng lúc còn ~1 phút. */
    private var nextTickMs = TICK_MS
    private var warnedKey: String? = null
    private var warningView: TextView? = null

    /** Lớp phủ xám khi máy đang tạm dừng; ẩn khi SafeFamily ở trước để phụ huynh thao tác rõ. */
    private var pauseTint: View? = null
    private var foregroundPackage: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        sweepRelocks()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        hideWarning()
        hidePauseTint()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && isRealScreen(event, pkg)) {
            foregroundPackage = pkg
            syncPauseTint()
        }
        if (pkg == packageName) return

        // Mỗi lần cửa sổ đổi: chặn lại app đã quá hạn mở tạm (kể cả sau reboot).
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            sweepRelocks()
            enforceTimeLimits(pkg)
        }

        if (pkg !in GUARDED_PACKAGES) return
        if (!GuardPrefs.protectionEnabled(this)) return
        if (GuardPrefs.settingsAllowed(this)) return

        val now = GuardPrefs.elapsedNow()
        if (now - lastScan < SCAN_INTERVAL_MS) return
        lastScan = now

        val root = rootInActiveWindow ?: return
        if (!mentionsApp(root)) return
        challenge()
    }

    private fun sweepRelocks() {
        if (TempRelocks.sweep(this)) {
            AppBlockerAccessibilityService.instance?.checkCurrentForegroundApp()
        }
    }

    /**
     * Giới hạn thời gian: đo, cộng bộ đếm riêng, rồi chặn nếu [candidate]
     * (app vừa hiện lên) hoặc app đang ở trước đã hết giờ.
     */
    private fun enforceTimeLimits(candidate: String?) {
        syncPauseTint()
        // Quét định kỳ để không sót app cài lúc dịch vụ chưa chạy (có giãn cách bên trong).
        runCatching { NewApps.scan(this) }
        val usage = runCatching { TimeLimits.usageToday(this) }.getOrNull()
        TimeLimits.tick(this, usage)
        if (usage != null) runCatching { UsageReport.snapshot(this) }
        val target = candidate ?: usage?.foreground
        nextTickMs = TICK_MS
        if (target == null) return
        if (usage != null) warnIfAlmostOut(usage, target)
        // Tạm dừng máy, app mới chờ duyệt, giờ ngủ, giờ học, rồi hạn mức; các loại đầu không cần quyền đo thời gian dùng.
        val verdict = TimeLimits.pauseVerdict(this, target)
            ?: NewApps.verdict(this, target)
            ?: TimeLimits.bedtimeVerdict(this, target)
            ?: TimeLimits.studyVerdict(this, target)
            ?: usage?.let { TimeLimits.verdict(this, it, target) }
            ?: return
        val now = GuardPrefs.elapsedNow()
        if (now - lastBlockAt < BLOCK_COOLDOWN_MS) return
        lastBlockAt = now
        runCatching { UsageReport.recordBlock(this) }
        performGlobalAction(GLOBAL_ACTION_HOME)
        handler.postDelayed({
            startActivity(
                Intent(this, TimeLimitBlockActivity::class.java)
                    .putExtra(TimeLimitBlockActivity.EXTRA_MESSAGE, verdict.message)
                    .putExtra(TimeLimitBlockActivity.EXTRA_CAN_REQUEST, verdict.canRequestMore)
                    .putExtra(TimeLimitBlockActivity.EXTRA_NEEDS_REVIEW, verdict.needsReview)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_HISTORY),
            )
        }, LAUNCH_DELAY_MS)
    }

    /**
     * Còn ≤ 60 giây thì hiện banner "Còn 1 phút" (một lần cho mỗi app mỗi mức
     * giờ thêm), không chặn nửa chừng. Gần ngưỡng thì đo dày hơn.
     */
    private fun warnIfAlmostOut(usage: TimeLimits.Usage, target: String) {
        val remaining = TimeLimits.remainingMs(this, usage, target) ?: return
        if (remaining > WARN_MS + TICK_MS) return
        nextTickMs = FAST_TICK_MS
        if (remaining <= 0 || remaining > WARN_MS) return
        val key = "$target|${TimeLimits.bonusMinutes(this)}"
        if (key == warnedKey) return
        warnedKey = key
        showWarning()
    }

    private fun showWarning() {
        hideWarning()
        val density = resources.displayMetrics.density
        val pad = (12 * density).toInt()
        val view = TextView(this).apply {
            text = "Còn 1 phút nữa là hết giờ"
            textSize = 16f
            setTextColor(Color.WHITE)
            setBackgroundColor(WARNING_BACKGROUND)
            gravity = Gravity.CENTER
            setPadding(pad, pad, pad, pad)
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP }
        runCatching {
            (getSystemService(WINDOW_SERVICE) as WindowManager).addView(view, params)
            warningView = view
            handler.postDelayed({ hideWarning() }, WARNING_SHOWN_MS)
        }
    }

    /**
     * Sự kiện đổi cửa sổ có phải một màn hình/app thật không. Bỏ qua thanh hệ
     * thống, bàn phím và view nổi (kể cả lớp phủ của chính mình) để không đoán
     * sai app ở trước làm lớp phủ lúc hiện lúc ẩn.
     */
    private fun isRealScreen(event: AccessibilityEvent, pkg: String): Boolean {
        if (pkg == "com.android.systemui" || pkg == "android") return false
        val cls = event.className?.toString().orEmpty()
        if (cls.startsWith("android.view.") || cls.startsWith("android.widget.")) return false
        return !TimeLimits.isInputMethod(this, pkg)
    }

    private fun syncPauseTint() {
        val fg = foregroundPackage
        val keepClear = fg == packageName ||
            (fg != null && fg in TimeLimits.phoneAndSmsPackages(this))
        val want = !keepClear &&
            runCatching { TimeLimits.pauseMinutesLeft(this) > 0 }.getOrDefault(false)
        if (want) showPauseTint() else hidePauseTint()
    }

    private fun showPauseTint() {
        if (pauseTint != null) return
        val view = View(this).apply { setBackgroundColor(PAUSE_TINT) }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        runCatching {
            (getSystemService(WINDOW_SERVICE) as WindowManager).addView(view, params)
            pauseTint = view
        }
    }

    private fun hidePauseTint() {
        val view = pauseTint ?: return
        pauseTint = null
        runCatching { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(view) }
    }

    private fun hideWarning() {
        val view = warningView ?: return
        warningView = null
        runCatching { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(view) }
    }

    private fun challenge() {
        GuardPrefs.setChallengePending(this, true)
        performGlobalAction(GLOBAL_ACTION_HOME)
        handler.postDelayed({
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
            )
        }, LAUNCH_DELAY_MS)
    }

    /** Màn hiện có chữ "SafeFamily" (tên app, hoặc tên dịch vụ Trợ năng). */
    private fun mentionsApp(root: AccessibilityNodeInfo): Boolean {
        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.add(root)
        var visited = 0
        while (stack.isNotEmpty() && visited < MAX_NODES) {
            val node = stack.removeLast()
            visited++
            val text = node.text?.toString().orEmpty() + " " + node.contentDescription?.toString().orEmpty()
            if (text.contains(APP_NAME, ignoreCase = true)) return true
            for (i in 0 until node.childCount) node.getChild(i)?.let(stack::add)
        }
        return false
    }

    companion object {
        private const val APP_NAME = "SafeFamily"
        private const val MAX_NODES = 600
        private const val SCAN_INTERVAL_MS = 400L
        private const val LAUNCH_DELAY_MS = 150L
        private const val TICK_MS = 30_000L
        private const val FAST_TICK_MS = 5_000L
        private const val WARN_MS = 60_000L
        private const val WARNING_SHOWN_MS = 8_000L
        private const val WARNING_BACKGROUND = 0xE6E65100.toInt()
        /** Xám đậm ~65% (ARGB); tăng 0xA6 để đậm hơn, giảm để nhạt hơn. */
        private const val PAUSE_TINT = 0xA6505050.toInt()
        private const val BLOCK_COOLDOWN_MS = 2_000L

        /** Màn Cài đặt / cài đặt app / gỡ app của AOSP và các hãng phổ biến. */
        val GUARDED_PACKAGES = setOf(
            "com.android.settings",
            "com.miui.securitycenter",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.miui.packageinstaller",
            "com.samsung.android.packageinstaller",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.coloros.safecenter",
            "com.oplus.securitypermission",
            "com.iqoo.secure",
            "com.huawei.systemmanager",
            "com.android.vending",
        )
    }
}
