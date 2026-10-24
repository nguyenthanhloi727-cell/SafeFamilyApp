package com.safefamily.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Duyệt app mới cài: app xuất hiện sau lần quét đầu tiên bị chặn cho tới khi
 * phụ huynh xác thực và cho phép.
 *
 * - `known`: app có từ lúc bật tính năng (hoặc đã được duyệt).
 * - `pending`: app mới cài, đang chờ duyệt.
 * Lần quét đầu tiên chỉ ghi nhận mọi app đang có vào `known`, không chặn gì.
 * Tắt rồi bật lại cũng ghi nhận lại như vậy (app cài lúc tắt không bị chặn).
 */
object NewApps {
    private const val FILE = "safefamily_new_apps"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_BASELINED = "baselined"
    private const val KEY_KNOWN = "known"
    private const val KEY_PENDING = "pending"
    private const val KEY_REVIEW = "review_pending"
    private const val CHANNEL = "new_apps"
    private const val SCAN_MIN_GAP_MS = 5_000L

    /** Extra của Intent mở MainActivity ở màn duyệt app. */
    const val EXTRA_REVIEW = "review_new_apps"

    private var lastScan = 0L

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun strings(context: Context, key: String): Set<String> =
        prefs(context).getStringSet(key, emptySet())?.toSet() ?: emptySet()

    private fun putStrings(context: Context, key: String, value: Set<String>) {
        prefs(context).edit().putStringSet(key, value).apply()
    }

    /** Mặc định bật. */
    fun enabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, true)

    @Synchronized
    fun setEnabled(context: Context, enabled: Boolean) {
        val wasEnabled = enabled(context)
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (!enabled) {
            // Tắt thì mở khóa luôn các app đang chờ duyệt.
            putStrings(context, KEY_KNOWN, strings(context, KEY_KNOWN) + strings(context, KEY_PENDING))
            putStrings(context, KEY_PENDING, emptySet())
        } else if (!wasEnabled) {
            // Bật lại: app cài lúc tắt coi như đã có sẵn.
            prefs(context).edit().putBoolean(KEY_BASELINED, false).apply()
            scan(context, force = true)
        }
    }

    /** Mọi app có biểu tượng mở được trên màn hình chính (trừ SafeFamily). */
    private fun launchable(context: Context): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        return context.packageManager.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName }
            .filterTo(mutableSetOf()) { it != context.packageName }
    }

    /**
     * Đối chiếu app đang cài với `known`; app lạ vào `pending` và phụ huynh
     * được báo. Gọi lúc dịch vụ chạy, lúc khởi động máy, khi có broadcast cài
     * app và định kỳ để không sót app cài lúc dịch vụ chưa chạy.
     * Trả về các app vừa bị đưa vào chờ duyệt.
     */
    @Synchronized
    fun scan(context: Context, force: Boolean = false): List<String> {
        if (!enabled(context)) return emptyList()
        val now = GuardPrefs.elapsedNow()
        if (!force && now - lastScan < SCAN_MIN_GAP_MS) return emptyList()
        lastScan = now

        val installed = launchable(context)
        val p = prefs(context)
        if (!p.getBoolean(KEY_BASELINED, false)) {
            putStrings(context, KEY_KNOWN, installed)
            putStrings(context, KEY_PENDING, emptySet())
            p.edit().putBoolean(KEY_BASELINED, true).apply()
            return emptyList()
        }
        val known = strings(context, KEY_KNOWN)
        val oldPending = strings(context, KEY_PENDING)
        // Gỡ rồi thì không còn gì để duyệt (cài lại sẽ là app mới).
        val pending = oldPending.filterTo(mutableSetOf()) { it in installed }
        val added = installed.filter { it !in known && it !in pending }
        pending += added
        if (pending != oldPending) putStrings(context, KEY_PENDING, pending)
        putStrings(context, KEY_KNOWN, known.filterTo(mutableSetOf()) { it in installed || it in pending })
        added.forEach { announce(context, it) }
        return added
    }

    /** App bị gỡ: quên luôn, lần cài lại phải duyệt lại. */
    @Synchronized
    fun onRemoved(context: Context, packageName: String) {
        putStrings(context, KEY_PENDING, strings(context, KEY_PENDING) - packageName)
        putStrings(context, KEY_KNOWN, strings(context, KEY_KNOWN) - packageName)
        cancelAnnouncement(context, packageName)
    }

    fun pending(context: Context): List<String> = strings(context, KEY_PENDING).sorted()

    @Synchronized
    fun approve(context: Context, packageName: String) {
        putStrings(context, KEY_PENDING, strings(context, KEY_PENDING) - packageName)
        putStrings(context, KEY_KNOWN, strings(context, KEY_KNOWN) + packageName)
        cancelAnnouncement(context, packageName)
    }

    fun label(context: Context, packageName: String): String =
        runCatching {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        }.getOrDefault(packageName)

    /** Lý do chặn nếu [packageName] đang chờ duyệt; `null` = không liên quan. */
    fun verdict(context: Context, packageName: String): TimeLimits.Verdict? {
        if (!enabled(context) || packageName == context.packageName) return null
        if (packageName in TimeLimits.exemptPackages(context)) return null
        if (packageName !in strings(context, KEY_KNOWN) && packageName !in strings(context, KEY_PENDING)) {
            scan(context)
        }
        if (packageName !in strings(context, KEY_PENDING)) return null
        return TimeLimits.Verdict(
            packageName,
            "Ứng dụng mới, chờ bố mẹ duyệt",
            canRequestMore = false,
            needsReview = true,
        )
    }

    // ---- Yêu cầu mở màn duyệt trong Flutter ------------------------------

    fun setReviewRequested(context: Context, requested: Boolean) {
        prefs(context).edit().putBoolean(KEY_REVIEW, requested).apply()
    }

    fun consumeReviewRequest(context: Context): Boolean {
        val p = prefs(context)
        val requested = p.getBoolean(KEY_REVIEW, false)
        if (requested) p.edit().putBoolean(KEY_REVIEW, false).apply()
        return requested
    }

    // ---- Thông báo -------------------------------------------------------

    private fun announce(context: Context, packageName: String) {
        runCatching {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Ứng dụng mới cài", NotificationManager.IMPORTANCE_HIGH),
                )
            }
            val open = PendingIntent.getActivity(
                context,
                packageName.hashCode(),
                Intent(context, MainActivity::class.java)
                    .putExtra(EXTRA_REVIEW, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            manager.notify(
                packageName.hashCode(),
                builder
                    .setSmallIcon(context.applicationInfo.icon)
                    .setContentTitle("Con vừa cài app ${label(context, packageName)}")
                    .setContentText("App bị chặn cho tới khi bố mẹ duyệt trong SafeFamily.")
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        }
    }

    private fun cancelAnnouncement(context: Context, packageName: String) {
        runCatching {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(packageName.hashCode())
        }
    }

    /** Mở SafeFamily ở màn duyệt app (dùng cho nút trên màn chặn). */
    fun openReview(context: Context) {
        setReviewRequested(context, true)
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
    }
}
