package com.safefamily.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

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
    private const val KEY_REJECTED = "rejected"
    private const val KEY_REVIEW = "review_pending"
    private const val KEY_UPLOADED = "uploaded"
    private const val KEY_APPLIED = "applied_decisions"
    private const val UPLOAD_BATCH = 100
    private const val MAX_LABEL = 200
    private val PACKAGE_RE = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")
    private const val CHANNEL = "new_apps"
    private const val SCAN_MIN_GAP_MS = 5_000L

    /** Extra của Intent mở MainActivity ở màn duyệt app. */
    const val EXTRA_REVIEW = "review_new_apps"

    private var lastScan = 0L
    private val netLock = Any()

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
        val rejected = strings(context, KEY_REJECTED).filterTo(mutableSetOf()) { it in installed }
        putStrings(context, KEY_REJECTED, rejected)
        putStrings(
            context,
            KEY_KNOWN,
            known.filterTo(mutableSetOf()) { it in installed || it in pending || it in rejected },
        )
        // App đã gỡ thì quên chuyện đã gửi / đã áp quyết định: cài lại phải gửi lên và duyệt lại.
        forgetSync(context) { it in installed }
        added.forEach { announce(context, it) }
        if (added.isNotEmpty() && FamilySync.isConfigured(context)) {
            val app = context.applicationContext
            Thread { syncWithServer(app) }.start() // gửi ngay nếu có mạng; không thì lượt đồng bộ sau gửi bù
        }
        return added
    }

    /** App bị gỡ: quên luôn, lần cài lại phải duyệt lại. */
    @Synchronized
    fun onRemoved(context: Context, packageName: String) {
        putStrings(context, KEY_PENDING, strings(context, KEY_PENDING) - packageName)
        putStrings(context, KEY_REJECTED, strings(context, KEY_REJECTED) - packageName)
        putStrings(context, KEY_KNOWN, strings(context, KEY_KNOWN) - packageName)
        forgetSync(context) { it != packageName }
        cancelAnnouncement(context, packageName)
    }

    fun pending(context: Context): List<String> = strings(context, KEY_PENDING).sorted()

    fun rejected(context: Context): List<String> = strings(context, KEY_REJECTED).sorted()

    /** Từ chối: app vẫn bị chặn, rời danh sách chờ; cho phép lại bằng [approve]. */
    @Synchronized
    fun reject(context: Context, packageName: String) {
        putStrings(context, KEY_PENDING, strings(context, KEY_PENDING) - packageName)
        putStrings(context, KEY_REJECTED, strings(context, KEY_REJECTED) + packageName)
        cancelAnnouncement(context, packageName)
    }

    @Synchronized
    fun approve(context: Context, packageName: String) {
        putStrings(context, KEY_PENDING, strings(context, KEY_PENDING) - packageName)
        putStrings(context, KEY_REJECTED, strings(context, KEY_REJECTED) - packageName)
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
        if (packageName !in strings(context, KEY_KNOWN) && packageName !in strings(context, KEY_PENDING) &&
            packageName !in strings(context, KEY_REJECTED)
        ) {
            scan(context)
        }
        if (packageName in strings(context, KEY_REJECTED)) {
            return TimeLimits.Verdict(
                packageName,
                "Bố mẹ đã từ chối ứng dụng này",
                canRequestMore = false,
                needsReview = true,
            )
        }
        if (packageName !in strings(context, KEY_PENDING)) return null
        return TimeLimits.Verdict(
            packageName,
            "Ứng dụng mới, chờ bố mẹ duyệt",
            canRequestMore = false,
            needsReview = true,
        )
    }

    // ---- Đồng bộ với server (API-07) -------------------------------------

    /** Giữ lại trong `uploaded` / `applied_decisions` chỉ những gói thỏa [keep]. */
    private fun forgetSync(context: Context, keep: (String) -> Boolean) {
        val p = prefs(context)
        val uploaded = strings(context, KEY_UPLOADED)
        if (!uploaded.all(keep)) putStrings(context, KEY_UPLOADED, uploaded.filterTo(mutableSetOf(), keep))
        val applied = runCatching { JSONObject(p.getString(KEY_APPLIED, "{}")) }.getOrDefault(JSONObject())
        val drop = applied.keys().asSequence().filter { !keep(it) }.toList()
        if (drop.isNotEmpty()) {
            drop.forEach { applied.remove(it) }
            p.edit().putString(KEY_APPLIED, applied.toString()).apply()
        }
    }

    /**
     * Gửi app mới cài lên server rồi kéo quyết định của mẹ về. Chỉ gửi tên app + tên gói (không nội dung) và
     * chỉ app đang chờ duyệt. Hàng chờ chính là `pending` trừ `uploaded` (SharedPreferences, không mất khi
     * offline hay kill app). MỌI lỗi (mạng, 4xx/5xx, dữ liệu hỏng) bị nuốt: lượt sau thử lại, không làm hỏng
     * lượt đồng bộ của [FamilySync]. Không giữ khóa của [NewApps] trong lúc gọi mạng.
     * Mẹ quyết định: `allowed` → [approve], `blocked` → [reject]; việc chặn vẫn do [verdict] lo, không đụng
     * `policy.appLock.blocked` / `GuardPrefs.remoteBlocked` nên không lẫn với danh sách khóa của mẹ (API-04/05).
     * TODO(verify): chạy trên 2 máy thật.
     */
    fun syncWithServer(context: Context) {
        if (!FamilySync.isConfigured(context) || !enabled(context)) return
        synchronized(netLock) {
            runCatching {
                // Còn app chưa gửi được thì chưa kéo quyết định: quyết định cũ của gói cài lại có thể còn trên server.
                if (uploadPending(context)) pullDecisions(context)
            }
        }
    }

    /** `true` nếu không còn app nào chờ gửi. */
    private fun uploadPending(context: Context): Boolean {
        val exempt = TimeLimits.exemptPackages(context)
        val todo = synchronized(this) {
            (strings(context, KEY_PENDING) - strings(context, KEY_UPLOADED))
                .filter { it !in exempt && PACKAGE_RE.matches(it) && it.length <= 200 }
                .sorted()
        }
        for (batch in todo.chunked(UPLOAD_BATCH)) {
            val apps = JSONArray()
            batch.forEach { pkg ->
                apps.put(
                    JSONObject().put("packageName", pkg).put("label", cleanLabel(label(context, pkg), pkg))
                        .put("isNew", true),
                )
            }
            val r = FamilySync.request(context, "POST", "/api/devices/me/apps", JSONObject().put("apps", apps))
            // 400 = server không nhận dữ liệu này: bỏ để không kẹt hàng chờ. 401/429/5xx: giữ, lượt sau thử lại.
            if (r.code !in 200..299 && r.code != 400) return false
            synchronized(this) { putStrings(context, KEY_UPLOADED, strings(context, KEY_UPLOADED) + batch) }
        }
        return true
    }

    private fun cleanLabel(label: String, pkg: String): String =
        label.filter { !it.isISOControl() }.trim().take(MAX_LABEL).ifEmpty { pkg }

    private fun pullDecisions(context: Context) {
        val r = FamilySync.request(context, "GET", "/api/devices/me/apps/decisions", null)
        if (r.code != 200) return
        val array = JSONArray(r.body)
        val decisions = linkedMapOf<String, String>()
        for (i in 0 until array.length()) {
            val item = array.getJSONObject(i)
            val pkg = item.getString("packageName")
            val status = item.getString("status")
            if (PACKAGE_RE.matches(pkg) && (status == "allowed" || status == "blocked")) decisions[pkg] = status
        }
        val p = prefs(context)
        val exempt = TimeLimits.exemptPackages(context)
        synchronized(this) {
            val applied = runCatching { JSONObject(p.getString(KEY_APPLIED, "{}")) }.getOrDefault(JSONObject())
            val installed = launchable(context)
            for ((pkg, status) in decisions) {
                // Đã áp rồi thì thôi: phụ huynh sửa tay trên máy con được giữ tới khi mẹ đổi quyết định.
                if (applied.optString(pkg) == status) continue
                if (pkg !in exempt) {
                    if (status == "allowed") {
                        if (pkg in strings(context, KEY_PENDING) || pkg in strings(context, KEY_REJECTED)) approve(context, pkg)
                    } else if (pkg in installed) {
                        reject(context, pkg)
                    }
                }
                applied.put(pkg, status)
            }
            // Quyết định biến mất (mẹ/máy con đưa app về chờ duyệt): lần quyết định sau phải áp lại.
            applied.keys().asSequence().filter { it !in decisions }.toList().forEach { applied.remove(it) }
            p.edit().putString(KEY_APPLIED, applied.toString()).apply()
        }
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
