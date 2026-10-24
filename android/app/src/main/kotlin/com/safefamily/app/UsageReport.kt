package com.safefamily.app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import org.json.JSONObject
import java.util.Calendar

/**
 * Số liệu cho báo cáo thời gian dùng. Bộ nhớ thống kê của hệ thống chỉ giữ
 * lịch sử ngắn, nên mỗi ngày được chụp lại (snapshot) vào kho riêng và giữ
 * [KEEP_DAYS] ngày. Ngày tính theo giờ đáng tin ([TimeLimits.trustedNow]).
 */
object UsageReport {
    private const val FILE = "safefamily_report"
    private const val KEY_DAYS = "days"
    private const val KEEP_DAYS = 30
    private const val DAY_MS = 24 * 60 * 60 * 1000L
    private const val SNAPSHOT_EVERY_MS = 5 * 60_000L

    private var lastSnapshotAt = 0L

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun readDays(context: Context): JSONObject =
        runCatching { JSONObject(prefs(context).getString(KEY_DAYS, "{}") ?: "{}") }
            .getOrDefault(JSONObject())

    /** "2026-10-24" cho ngày bắt đầu lúc [dayStart]. */
    private fun dateKey(dayStart: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = dayStart }
        return "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
    }

    private fun dayStartOf(trusted: Long, daysAgo: Int): Long =
        Calendar.getInstance().apply {
            timeInMillis = trusted
            add(Calendar.DAY_OF_YEAR, -daysAgo)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    /** Thời gian foreground (ms) từng app trong [from, to) theo UsageStats; app còn mở lúc [to] tính đến [to]. */
    private fun foregroundMs(context: Context, from: Long, to: Long): Map<String, Long> {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, to)
        val event = UsageEvents.Event()
        val used = HashMap<String, Long>()
        val open = HashMap<String, Long>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                TimeLimits.EVENT_RESUMED -> open.putIfAbsent(pkg, event.timeStamp)
                TimeLimits.EVENT_PAUSED, TimeLimits.EVENT_STOPPED -> open.remove(pkg)?.let {
                    used.merge(pkg, maxOf(0L, event.timeStamp - it), Long::plus)
                }
            }
        }
        for ((pkg, since) in open) used.merge(pkg, maxOf(0L, to - since), Long::plus)
        return used
    }

    private fun dayJson(perApp: Map<String, Long>, blocks: Int): JSONObject {
        val apps = JSONObject()
        for ((pkg, ms) in perApp) if (ms >= 60_000L) apps.put(pkg, ms)
        return JSONObject().put("apps", apps).put("blocks", blocks)
    }

    /** Lưu số liệu hôm nay vào kho, bỏ ngày quá [KEEP_DAYS]. Giữ nguyên số lần bị chặn. */
    @Synchronized
    fun snapshot(context: Context, force: Boolean = false) {
        val now = GuardPrefs.elapsedNow()
        if (!force && lastSnapshotAt != 0L && now - lastSnapshotAt < SNAPSHOT_EVERY_MS) return
        val usage = runCatching { TimeLimits.usageToday(context) }.getOrNull() ?: return
        lastSnapshotAt = now
        val days = readDays(context)
        val key = dateKey(usage.dayStart)
        val blocks = days.optJSONObject(key)?.optInt("blocks") ?: 0
        days.put(key, dayJson(usage.perApp, blocks))
        prune(days, usage.dayStart)
        prefs(context).edit().putString(KEY_DAYS, days.toString()).apply()
    }

    private fun prune(days: JSONObject, today: Long) {
        val oldest = dateKey(today - (KEEP_DAYS - 1) * DAY_MS)
        for (key in days.keys().asSequence().toList()) if (key < oldest) days.remove(key)
    }

    /** Một lần con chạm vào app bị chặn (màn chặn hiện lên). */
    @Synchronized
    fun recordBlock(context: Context) {
        val days = readDays(context)
        val key = dateKey(dayStartOf(TimeLimits.trustedNow(context), 0))
        val day = days.optJSONObject(key) ?: JSONObject().put("apps", JSONObject())
        days.put(key, day.put("blocks", day.optInt("blocks") + 1))
        prefs(context).edit().putString(KEY_DAYS, days.toString()).apply()
    }

    /**
     * Báo cáo [count] ngày gần nhất (cũ nhất trước, cuối là hôm nay). Ngày
     * chưa có snapshot thì lấy từ UsageStats rồi lưu lại. `null` nếu chưa có
     * quyền truy cập dữ liệu sử dụng.
     */
    @Synchronized
    fun report(context: Context, count: Int): List<Map<String, Any>>? {
        if (!TimeLimits.hasUsageAccess(context)) return null
        snapshot(context, force = true)
        val trusted = TimeLimits.trustedNow(context)
        val skew = System.currentTimeMillis() - trusted
        val exempt = TimeLimits.exemptPackages(context)
        val days = readDays(context)
        var changed = false
        val out = ArrayList<Map<String, Any>>()
        for (ago in (count - 1) downTo 0) {
            val start = dayStartOf(trusted, ago)
            val key = dateKey(start)
            var day = days.optJSONObject(key)
            if (day == null && ago > 0) {
                val used = foregroundMs(context, start + skew, start + DAY_MS + skew)
                    .filterKeys { it !in exempt }
                day = dayJson(used, 0)
                days.put(key, day)
                changed = true
            }
            val apps = day?.optJSONObject("apps") ?: JSONObject()
            val minutes = HashMap<String, Int>()
            var total = 0L
            for (pkg in apps.keys()) {
                val ms = apps.optLong(pkg)
                total += ms
                minutes[pkg] = (ms / 60_000L).toInt()
            }
            out.add(
                mapOf(
                    "date" to key,
                    "totalMinutes" to (total / 60_000L).toInt(),
                    "blocks" to (day?.optInt("blocks") ?: 0),
                    "apps" to minutes,
                ),
            )
        }
        if (changed) {
            prune(days, dayStartOf(trusted, 0))
            prefs(context).edit().putString(KEY_DAYS, days.toString()).apply()
        }
        return out
    }

    /** Tên hiển thị của các gói (nhãn app trong PackageManager). */
    fun labels(context: Context, packages: List<String>): Map<String, String> {
        val pm = context.packageManager
        return packages.associateWith { pkg ->
            runCatching { pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() }
                .getOrDefault(pkg)
        }
    }
}
