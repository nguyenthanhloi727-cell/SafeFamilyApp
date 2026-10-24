package com.safefamily.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.telecom.TelecomManager
import android.view.inputmethod.InputMethodManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.abs

/**
 * Giới hạn thời gian dùng máy theo ngày (tổng và từng app), thực thi ở native
 * vì tiến trình Flutter có thể đã bị hệ thống tắt.
 *
 * Cấu hình do Dart ghi (JSON, xem [setConfig]); thứ trong tuần đánh số
 * 0 = Thứ Hai … 6 = Chủ Nhật, `-1` = không giới hạn.
 *
 * Thời gian đã dùng = max(UsageStatsManager, bộ đếm riêng). Bộ đếm riêng dựa
 * trên đồng hồ elapsed nên đổi giờ hệ thống không làm nó reset; UsageStats
 * chính xác hơn nhưng tính theo giờ hệ thống.
 */
object TimeLimits {
    private const val FILE = "safefamily_limits"
    private const val KEY_CONFIG = "config"
    private const val KEY_ANCHOR_WALL = "anchor_wall"
    private const val KEY_ANCHOR_ELAPSED = "anchor_elapsed"
    private const val KEY_ANCHOR_BOOT = "anchor_boot"
    private const val KEY_JUMPS = "time_jumps"
    private const val KEY_LAST_SKEW = "last_logged_skew"
    private const val KEY_OWN = "own_counter"
    private const val KEY_LAST_TICK = "own_last_tick"
    private const val KEY_LAST_FG = "own_last_fg"
    private const val KEY_BONUS = "bonus"
    private const val KEY_STUDY = "study_state"
    private const val KEY_PAUSE = "pause_until"
    private const val PAUSE_FOREVER = Long.MAX_VALUE
    private const val MAX_PAUSE_MINUTES = 24 * 60

    private const val SKEW_TOLERANCE_MS = 120_000L
    private const val MAX_TICK_GAP_MS = 45_000L
    private const val MAX_JUMP_LOG = 20
    private const val EXEMPT_CACHE_MS = 5 * 60_000L
    private const val MAX_BONUS_MINUTES = 240
    private const val MAX_STUDY_MINUTES = 240

    // UsageEvents.Event: ACTIVITY_RESUMED (29+) / MOVE_TO_FOREGROUND dùng cùng số 1.
    const val EVENT_RESUMED = 1
    const val EVENT_PAUSED = 2
    const val EVENT_STOPPED = 23

    private var exemptCache: Set<String> = emptySet()
    private var exemptAt = 0L

    /** Kết quả đo: phút/ms đã dùng hôm nay và app đang ở trước. */
    class Usage(
        val perApp: Map<String, Long>,
        val total: Long,
        val foreground: String?,
        val dayStart: Long,
    )

    /** App bị chặn kèm lý do hiện trên màn chặn. */
    class Verdict(
        val packageName: String,
        val message: String,
        val canRequestMore: Boolean = true,
        val needsReview: Boolean = false,
    )

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun config(context: Context): String =
        prefs(context).getString(KEY_CONFIG, null) ?: """{"enabled":false,"total":[-1,-1,-1,-1,-1,-1,-1],"apps":{}}"""

    fun setConfig(context: Context, json: String) {
        JSONObject(json) // hỏng thì ném lỗi, không ghi
        prefs(context).edit().putString(KEY_CONFIG, json).apply()
    }

    fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun usageAccessIntent(context: Context): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:${context.packageName}"))

    // ---- Đồng hồ đáng tin ------------------------------------------------

    /**
     * Giờ treo tường "đáng tin": mốc giờ hệ thống lúc khởi động + thời gian
     * elapsed đã trôi. Con đổi giờ hệ thống thì [trustedNow] không đổi theo
     * và lệch được ghi vào nhật ký. Sau khi máy khởi động lại thì chốt mốc mới.
     */
    @Synchronized
    fun trustedNow(context: Context): Long {
        val p = prefs(context)
        val wall = System.currentTimeMillis()
        val elapsed = GuardPrefs.elapsedNow()
        val boot = GuardPrefs.bootCount(context)
        var anchorWall = p.getLong(KEY_ANCHOR_WALL, 0L)
        var anchorElapsed = p.getLong(KEY_ANCHOR_ELAPSED, 0L)
        val rebooted = p.getInt(KEY_ANCHOR_BOOT, -2) != boot || elapsed < anchorElapsed
        if (anchorWall == 0L || rebooted) {
            anchorWall = wall
            anchorElapsed = elapsed
            p.edit()
                .putLong(KEY_ANCHOR_WALL, wall)
                .putLong(KEY_ANCHOR_ELAPSED, elapsed)
                .putInt(KEY_ANCHOR_BOOT, boot)
                .putLong(KEY_LAST_SKEW, 0L)
                .apply()
        }
        val trusted = anchorWall + (elapsed - anchorElapsed)
        val skew = wall - trusted
        if (abs(skew - p.getLong(KEY_LAST_SKEW, 0L)) > SKEW_TOLERANCE_MS) {
            logJump(p, trusted, skew)
        }
        return trusted
    }

    private fun logJump(p: android.content.SharedPreferences, trusted: Long, skew: Long) {
        val log = runCatching { JSONArray(p.getString(KEY_JUMPS, "[]")) }.getOrDefault(JSONArray())
        log.put(JSONObject().put("at", trusted).put("skewMs", skew))
        val kept = JSONArray()
        for (i in maxOf(0, log.length() - MAX_JUMP_LOG) until log.length()) kept.put(log.get(i))
        p.edit().putString(KEY_JUMPS, kept.toString()).putLong(KEY_LAST_SKEW, skew).apply()
    }

    /** Nhật ký các lần giờ hệ thống bị đổi (mới nhất cuối). */
    fun timeJumps(context: Context): String = prefs(context).getString(KEY_JUMPS, "[]") ?: "[]"

    private fun dayStart(trusted: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = trusted
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    /** 0 = Thứ Hai … 6 = Chủ Nhật. */
    private fun weekdayIndex(trusted: Long): Int {
        val dow = Calendar.getInstance().apply { timeInMillis = trusted }.get(Calendar.DAY_OF_WEEK)
        return (dow + 5) % 7
    }

    // ---- Đo thời gian ----------------------------------------------------

    /** App không bao giờ bị tính giờ hay chặn: gọi điện, màn hình chính, hệ thống, SafeFamily. */
    @Synchronized
    fun exemptPackages(context: Context): Set<String> {
        val now = GuardPrefs.elapsedNow()
        if (exemptCache.isNotEmpty() && now - exemptAt < EXEMPT_CACHE_MS) return exemptCache
        val pm = context.packageManager
        val packages = mutableSetOf(context.packageName, "android", "com.android.systemui")
        val intents = listOf(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:")),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in intents) {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0).mapTo(packages) { it.activityInfo.packageName }
        }
        runCatching {
            (context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage
        }.getOrNull()?.let(packages::add)
        // Bàn phím hiện cửa sổ riêng nhưng không phải app con đang dùng.
        runCatching {
            (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .enabledInputMethodList.mapTo(packages) { it.packageName }
        }
        exemptCache = packages
        exemptAt = now
        return packages
    }

    /** Thời gian dùng từng app từ 00:00 hôm nay; `null` nếu chưa có quyền. */
    fun usageToday(context: Context): Usage? {
        if (!hasUsageAccess(context)) return null
        val trusted = trustedNow(context)
        val start = dayStart(trusted)
        val skew = System.currentTimeMillis() - trusted
        val now = System.currentTimeMillis()
        val from = start + skew
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, now)
        val event = UsageEvents.Event()
        val used = HashMap<String, Long>()
        val open = HashMap<String, Long>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                EVENT_RESUMED -> open.putIfAbsent(pkg, event.timeStamp)
                EVENT_PAUSED, EVENT_STOPPED -> open.remove(pkg)?.let {
                    used.merge(pkg, maxOf(0L, event.timeStamp - it), Long::plus)
                }
            }
        }
        val interactive = (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        var foreground: String? = null
        if (interactive) {
            var latest = 0L
            for ((pkg, since) in open) {
                used.merge(pkg, maxOf(0L, now - since), Long::plus)
                if (since >= latest) {
                    latest = since
                    foreground = pkg
                }
            }
        }
        val exempt = exemptPackages(context)
        val own = ownCounter(context, start)
        val perApp = HashMap<String, Long>()
        for (pkg in used.keys + own.perApp.keys) {
            if (pkg in exempt) continue
            perApp[pkg] = maxOf(used[pkg] ?: 0L, own.perApp[pkg] ?: 0L)
        }
        val statsTotal = used.filterKeys { it !in exempt }.values.sum()
        return Usage(perApp, maxOf(statsTotal, own.total), foreground?.takeIf { it !in exempt }, start)
    }

    private class Own(val total: Long, val perApp: Map<String, Long>)

    private fun readOwn(p: android.content.SharedPreferences, dayStart: Long): JSONObject {
        val json = runCatching { JSONObject(p.getString(KEY_OWN, "{}") ?: "{}") }.getOrDefault(JSONObject())
        return if (json.optLong("day") == dayStart) json else JSONObject().put("day", dayStart)
    }

    private fun ownCounter(context: Context, dayStart: Long): Own {
        val json = readOwn(prefs(context), dayStart)
        val apps = json.optJSONObject("apps") ?: JSONObject()
        val map = HashMap<String, Long>()
        for (key in apps.keys()) map[key] = apps.optLong(key)
        return Own(json.optLong("total"), map)
    }

    /**
     * Bộ đếm riêng (đồng hồ elapsed): cộng khoảng thời gian từ lần gọi trước
     * cho app đã ở trước lúc đó. Khoảng trống dài (dịch vụ bị tắt) bị bỏ qua.
     */
    @Synchronized
    fun tick(context: Context, usage: Usage?) {
        val p = prefs(context)
        val elapsed = GuardPrefs.elapsedNow()
        val lastTick = p.getLong(KEY_LAST_TICK, 0L)
        val lastFg = p.getString(KEY_LAST_FG, null)
        val editor = p.edit()
            .putLong(KEY_LAST_TICK, elapsed)
            .putString(KEY_LAST_FG, usage?.foreground)
        val gap = elapsed - lastTick
        if (usage != null && lastFg != null && gap in 1..MAX_TICK_GAP_MS) {
            val json = readOwn(p, usage.dayStart)
            val apps = json.optJSONObject("apps") ?: JSONObject()
            apps.put(lastFg, apps.optLong(lastFg) + gap)
            json.put("apps", apps).put("total", json.optLong("total") + gap)
            editor.putString(KEY_OWN, json.toString())
        }
        editor.apply()
    }

    // ---- Thực thi --------------------------------------------------------

    /**
     * Giờ ngủ: `"bedtime":{"enabled":true,"days":[[start,end]|null ×7]}`, phút
     * từ 00:00. `end <= start` là khung qua nửa đêm, tính vào ngày bắt đầu.
     * Không cần quyền đo thời gian dùng và không phụ thuộc `enabled` của hạn mức.
     */
    fun bedtimeVerdict(context: Context, packageName: String): Verdict? {
        if (packageName in exemptPackages(context)) return null
        val bedtime = runCatching { JSONObject(config(context)).optJSONObject("bedtime") }.getOrNull()
            ?: return null
        if (!bedtime.optBoolean("enabled")) return null
        val days = bedtime.optJSONArray("days") ?: return null
        return if (inWeekWindow(days, trustedNow(context))) {
            Verdict(packageName, "Đang trong giờ ngủ", canRequestMore = false)
        } else {
            null
        }
    }

    /**
     * [trusted] có nằm trong khung giờ của ngày đó không. [days] là 7 phần tử
     * `[start,end]|null`; khung qua nửa đêm (`end <= start`) tính vào ngày bắt đầu.
     */
    private fun inWeekWindow(days: JSONArray, trusted: Long): Boolean {
        val now = Calendar.getInstance().apply { timeInMillis = trusted }
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val day = weekdayIndex(trusted)
        fun window(i: Int): Pair<Int, Int>? {
            val w = days.optJSONArray(i) ?: return null
            return if (w.length() == 2) w.optInt(0) to w.optInt(1) else null
        }
        window(day)?.let { (start, end) ->
            val inside = if (end <= start) minute >= start else minute in start until end
            if (inside) return true
        }
        val yesterday = window((day + 6) % 7)
        return yesterday != null && yesterday.second <= yesterday.first && minute < yesterday.second
    }

    // ---- Giờ học ---------------------------------------------------------

    /**
     * Giờ học: `"study":{"enabled":true,"days":[[start,end]|null ×7],"allowed":[gói…]}`.
     * Trong giờ học chỉ app trong danh sách trắng (cộng gọi điện, máy tính, từ
     * điển và app miễn trừ) mở được. Ưu tiên: giờ ngủ, giờ học, hạn mức.
     *
     * Trạng thái chạy nằm riêng ngoài cấu hình để Dart ghi cấu hình không xóa
     * nó: `until` = hết phiên "bắt đầu ngay" (giờ đáng tin), `offDay` = ngày
     * đã "tắt hôm nay".
     */
    private fun studyConfig(context: Context): JSONObject? =
        runCatching { JSONObject(config(context)).optJSONObject("study") }.getOrNull()
            ?.takeIf { it.optBoolean("enabled") }

    private fun studyState(context: Context): JSONObject =
        runCatching { JSONObject(prefs(context).getString(KEY_STUDY, "{}") ?: "{}") }
            .getOrDefault(JSONObject())

    private fun putStudyState(context: Context, until: Long, offDay: Long) {
        prefs(context).edit()
            .putString(KEY_STUDY, JSONObject().put("until", until).put("offDay", offDay).toString())
            .apply()
    }

    /** Phiên giờ học bắt đầu ngay còn bao nhiêu phút (0 = không có phiên). */
    fun studySessionMinutesLeft(context: Context): Int {
        val left = studyState(context).optLong("until") - trustedNow(context)
        return if (left > 0) ((left + 59_999L) / 60_000L).toInt() else 0
    }

    fun studyDisabledToday(context: Context): Boolean {
        val off = studyState(context).optLong("offDay")
        return off != 0L && off == dayStart(trustedNow(context))
    }

    @Synchronized
    fun startStudySession(context: Context, minutes: Int) {
        require(minutes in 1..MAX_STUDY_MINUTES) { "minutes=$minutes" }
        putStudyState(context, trustedNow(context) + minutes * 60_000L, 0L)
    }

    @Synchronized
    fun stopStudySession(context: Context) {
        putStudyState(context, 0L, studyState(context).optLong("offDay"))
    }

    /** "Tắt hôm nay" (kết thúc luôn phiên đang chạy) hoặc bật lại. */
    @Synchronized
    fun setStudyDisabledToday(context: Context, disabled: Boolean) {
        putStudyState(context, 0L, if (disabled) dayStart(trustedNow(context)) else 0L)
    }

    /** Giờ học đang hiệu lực: phiên bắt đầu ngay, hoặc trong lịch mà chưa "tắt hôm nay". */
    fun studyActive(context: Context): Boolean {
        val study = studyConfig(context) ?: return false
        if (studySessionMinutesLeft(context) > 0) return true
        if (studyDisabledToday(context)) return false
        val days = study.optJSONArray("days") ?: return false
        return inWeekWindow(days, trustedNow(context))
    }

    /** Mở được trong giờ học dù phụ huynh không chọn: máy tính, từ điển. */
    private fun studyDefaults(context: Context): Set<String> {
        val pm = context.packageManager
        val found = mutableSetOf<String>()
        @Suppress("DEPRECATION")
        pm.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_CALCULATOR),
            0,
        ).mapTo(found) { it.activityInfo.packageName }
        @Suppress("DEPRECATION")
        pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .map { it.activityInfo.packageName }
            .filterTo(found) { it.contains("dictionary", ignoreCase = true) }
        return found
    }

    fun studyVerdict(context: Context, packageName: String): Verdict? {
        if (packageName in exemptPackages(context)) return null
        val study = studyConfig(context) ?: return null
        if (!studyActive(context)) return null
        val allowed = study.optJSONArray("allowed")
        for (i in 0 until (allowed?.length() ?: 0)) {
            if (allowed?.optString(i) == packageName) return null
        }
        if (packageName in studyDefaults(context)) return null
        return Verdict(packageName, "Đang trong giờ học", canRequestMore = false)
    }

    // ---- Tạm dừng máy ----------------------------------------------------

    /**
     * Tạm dừng máy: chặn mọi app trừ danh sách miễn trừ (gọi điện, màn hình
     * chính, SafeFamily). Ưu tiên cao nhất. `until` tính theo giờ đáng tin;
     * [PAUSE_FOREVER] = đến khi phụ huynh tắt. Không phụ thuộc cấu hình nên
     * Dart ghi cấu hình không xóa được nó.
     */
    @Synchronized
    fun startPause(context: Context, minutes: Int) {
        require(minutes == 0 || minutes in 1..MAX_PAUSE_MINUTES) { "minutes=$minutes" }
        val until = if (minutes == 0) PAUSE_FOREVER else trustedNow(context) + minutes * 60_000L
        prefs(context).edit().putLong(KEY_PAUSE, until).apply()
    }

    @Synchronized
    fun stopPause(context: Context) {
        prefs(context).edit().remove(KEY_PAUSE).apply()
    }

    /** `0` = không tạm dừng, [Int.MAX_VALUE] = đến khi tắt, ngược lại số phút còn lại. */
    fun pauseMinutesLeft(context: Context): Int {
        val until = prefs(context).getLong(KEY_PAUSE, 0L)
        if (until == 0L) return 0
        if (until == PAUSE_FOREVER) return Int.MAX_VALUE
        val left = until - trustedNow(context)
        return if (left > 0) ((left + 59_999L) / 60_000L).toInt() else 0
    }

    fun pauseVerdict(context: Context, packageName: String): Verdict? {
        if (packageName in exemptPackages(context)) return null
        if (pauseMinutesLeft(context) == 0) return null
        return Verdict(packageName, "Phụ huynh đã tạm dừng máy", canRequestMore = false)
    }

    // ---- Thêm giờ (bonus) ------------------------------------------------

    /**
     * Số phút phụ huynh đã thêm cho hôm nay. Cộng vào cả hạn mức tổng lẫn hạn
     * mức từng app, không đổi cấu hình gốc, và về 0 khi sang ngày mới (tính
     * theo giờ đáng tin nên đổi giờ hệ thống không giữ lại hay xóa được).
     */
    @Synchronized
    fun bonusMinutes(context: Context): Int {
        val today = dayStart(trustedNow(context))
        val json = runCatching { JSONObject(prefs(context).getString(KEY_BONUS, "{}") ?: "{}") }
            .getOrDefault(JSONObject())
        return if (json.optLong("day") == today) json.optInt("minutes") else 0
    }

    @Synchronized
    fun addBonus(context: Context, minutes: Int): Int {
        require(minutes in 1..MAX_BONUS_MINUTES) { "minutes=$minutes" }
        val total = bonusMinutes(context) + minutes
        val today = dayStart(trustedNow(context))
        prefs(context).edit()
            .putString(KEY_BONUS, JSONObject().put("day", today).put("minutes", total).toString())
            .apply()
        return total
    }

    /**
     * Thời gian còn lại (ms) của [packageName] trước khi bị chặn: nhỏ nhất giữa
     * hạn mức app và hạn mức tổng, đã cộng giờ thêm. `null` = không có hạn mức.
     */
    fun remainingMs(context: Context, usage: Usage, packageName: String): Long? {
        if (packageName in exemptPackages(context)) return null
        val cfg = runCatching { JSONObject(config(context)) }.getOrNull() ?: return null
        if (!cfg.optBoolean("enabled")) return null
        val day = weekdayIndex(trustedNow(context))
        val bonus = bonusMinutes(context) * 60_000L
        var remaining: Long? = null
        val appLimit = cfg.optJSONObject("apps")?.optJSONArray(packageName)?.optInt(day, -1) ?: -1
        if (appLimit >= 0) {
            remaining = appLimit * 60_000L + bonus - (usage.perApp[packageName] ?: 0L)
        }
        val totalLimit = cfg.optJSONArray("total")?.optInt(day, -1) ?: -1
        if (totalLimit >= 0) {
            val left = totalLimit * 60_000L + bonus - usage.total
            remaining = if (remaining == null) left else minOf(remaining, left)
        }
        return remaining
    }

    /** `null` = [packageName] còn được dùng; ngược lại là lý do chặn. */
    fun verdict(context: Context, usage: Usage, packageName: String): Verdict? {
        if (packageName in exemptPackages(context)) return null
        val cfg = runCatching { JSONObject(config(context)) }.getOrNull() ?: return null
        if (!cfg.optBoolean("enabled")) return null
        val day = weekdayIndex(trustedNow(context))
        val bonus = bonusMinutes(context) * 60_000L
        val appLimit = cfg.optJSONObject("apps")?.optJSONArray(packageName)?.optInt(day, -1) ?: -1
        if (appLimit >= 0 && (usage.perApp[packageName] ?: 0L) >= appLimit * 60_000L + bonus) {
            return Verdict(packageName, "Hết giờ dùng ứng dụng này hôm nay")
        }
        val totalLimit = cfg.optJSONArray("total")?.optInt(day, -1) ?: -1
        if (totalLimit >= 0 && usage.total >= totalLimit * 60_000L + bonus) {
            return Verdict(packageName, "Hết giờ dùng máy hôm nay")
        }
        return null
    }
}
