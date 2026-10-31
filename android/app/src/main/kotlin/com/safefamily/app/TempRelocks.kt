package com.safefamily.app

import android.content.Context
import com.khanhtq.app_blocker.persistence.BlockerPreferences
import org.json.JSONObject

/**
 * Danh sách app đang "mở tạm" và hạn chặn lại, giữ ở phía native.
 *
 * Lịch tự chặn lại của app_blocker là báo thức một lần: nếu máy tắt đúng lúc
 * hạn trôi qua thì sau khi khởi động lại báo thức đó không chạy nữa và app
 * được mở mãi. [sweep] đối chiếu hạn với đồng hồ và chặn lại ngay những app
 * đã quá hạn; gọi khi máy khởi động, khi dịch vụ Trợ năng kết nối và mỗi lần
 * cửa sổ đổi.
 */
object TempRelocks {
    private const val FILE = "safefamily_relocks"
    private const val KEY = "entries"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun load(context: Context): JSONObject =
        runCatching { JSONObject(prefs(context).getString(KEY, "{}") ?: "{}") }
            .getOrDefault(JSONObject())

    private fun save(context: Context, entries: JSONObject) {
        prefs(context).edit().putString(KEY, entries.toString()).apply()
    }

    /** Ghi nhớ: [packageName] được mở tạm tới [atEpochMillis] (giờ treo tường). */
    @Synchronized
    fun remember(context: Context, packageName: String, atEpochMillis: Long) {
        val remaining = atEpochMillis - System.currentTimeMillis()
        val entries = load(context)
        entries.put(
            packageName,
            JSONObject()
                .put("wall", atEpochMillis)
                .put("elapsed", GuardPrefs.elapsedNow() + remaining)
                .put("boot", GuardPrefs.bootCount(context)),
        )
        save(context, entries)
    }

    @Synchronized
    fun forget(context: Context, packageName: String) {
        val entries = load(context)
        if (entries.has(packageName)) {
            entries.remove(packageName)
            save(context, entries)
        }
    }

    /** App đang mở tạm (còn trong danh sách, chưa được [sweep] chặn lại). */
    @Synchronized
    fun pending(context: Context): Set<String> {
        val keys = load(context).keys()
        return buildSet { while (keys.hasNext()) add(keys.next()) }
    }

    /**
     * App đang mở tạm kèm giờ chặn lại còn lại (giờ treo tường, ước lượng), để báo mẹ.
     * Tính theo cùng quy tắc với [sweep]: cùng lần khởi động thì tin đồng hồ elapsed.
     */
    @Synchronized
    fun pendingUntil(context: Context): Map<String, Long> {
        val entries = load(context)
        val boot = GuardPrefs.bootCount(context)
        val elapsed = GuardPrefs.elapsedNow()
        val wall = System.currentTimeMillis()
        val out = mutableMapOf<String, Long>()
        val keys = entries.keys()
        while (keys.hasNext()) {
            val pkg = keys.next()
            val entry = entries.optJSONObject(pkg) ?: continue
            val sameBoot = boot != -1 && entry.optInt("boot", -1) == boot
            out[pkg] = if (sameBoot) wall + (entry.optLong("elapsed") - elapsed) else entry.optLong("wall")
        }
        return out
    }

    /** Chặn lại các app đã quá hạn. Trả về `true` nếu có app vừa bị chặn lại. */
    @Synchronized
    fun sweep(context: Context): Boolean {
        val entries = load(context)
        if (entries.length() == 0) return false
        val boot = GuardPrefs.bootCount(context)
        val elapsed = GuardPrefs.elapsedNow()
        val wall = System.currentTimeMillis()
        val expired = mutableListOf<String>()
        val keys = entries.keys()
        while (keys.hasNext()) {
            val pkg = keys.next()
            val entry = entries.optJSONObject(pkg) ?: continue
            val sameBoot = boot != -1 && entry.optInt("boot", -1) == boot
            // Cùng lần khởi động: tin đồng hồ elapsed (đổi giờ hệ thống cũng
            // không kéo dài hay rút ngắn được). Sau reboot elapsed bị đặt lại
            // nên dùng mốc giờ treo tường đã lưu.
            val due = if (sameBoot) {
                elapsed >= entry.optLong("elapsed")
            } else {
                wall >= entry.optLong("wall")
            }
            if (due) expired.add(pkg)
        }
        if (expired.isEmpty()) return false
        val preferences = BlockerPreferences(context.applicationContext)
        preferences.setBlockedApps(preferences.getBlockedApps() + expired)
        preferences.setIsBlocking(true)
        expired.forEach { entries.remove(it) }
        save(context, entries)
        return true
    }
}
