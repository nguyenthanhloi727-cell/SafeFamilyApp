package com.safefamily.app

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/**
 * Trạng thái chống bypass lưu native để dịch vụ Trợ năng và receiver đọc được
 * khi tiến trình Flutter đã bị tắt.
 *
 * Mọi mốc thời gian dùng [SystemClock.elapsedRealtime] (đồng hồ đếm từ lúc
 * khởi động, con đổi giờ hệ thống không chỉnh được) kèm [bootCount] để biết
 * mốc có còn đáng tin sau khi máy khởi động lại hay không.
 */
object GuardPrefs {
    private const val FILE = "safefamily_guard"
    private const val KEY_PROTECTION = "protection_enabled"
    private const val KEY_ALLOW_UNTIL = "settings_allow_until_elapsed"
    private const val KEY_ALLOW_BOOT = "settings_allow_boot"
    private const val KEY_UNINSTALL_UNTIL = "uninstall_allowed_until"
    private const val KEY_UNINSTALL_BOOT = "uninstall_allowed_boot"
    private const val KEY_ADMIN_RESTORE = "uninstall_admin_restore"
    private const val KEY_CHALLENGE = "challenge_pending"
    private const val KEY_EXTRA_TIME = "extra_time_pending"
    private const val KEY_CONTACTS = "family_contacts"
    private const val KEY_REMOTE_BLOCKED = "remote_blocked"
    private const val KEY_SOS = "policy_sos_contacts"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun elapsedNow(): Long = SystemClock.elapsedRealtime()

    /** Số lần máy đã khởi động (đổi khi reboot); -1 nếu máy không cho đọc. */
    fun bootCount(context: Context): Int =
        Settings.Global.getInt(context.contentResolver, "boot_count", -1)

    /** Chỉ bảo vệ sau khi phụ huynh đã đặt PIN (trước đó không có gì để hỏi). */
    fun protectionEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_PROTECTION, false)

    fun setProtectionEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_PROTECTION, enabled).apply()
    }

    /** Phụ huynh vừa xác thực: cho vào màn hệ thống thêm [seconds] giây. */
    fun allowSettings(context: Context, seconds: Long) {
        prefs(context).edit()
            .putLong(KEY_ALLOW_UNTIL, elapsedNow() + seconds * 1000)
            .putInt(KEY_ALLOW_BOOT, bootCount(context))
            .apply()
    }

    fun settingsAllowed(context: Context): Boolean {
        val p = prefs(context)
        val until = p.getLong(KEY_ALLOW_UNTIL, 0L)
        if (until == 0L) return false
        // Máy khởi động lại: mốc elapsed cũ không còn nghĩa → hết hạn.
        if (p.getInt(KEY_ALLOW_BOOT, -1) != bootCount(context)) return false
        return elapsedNow() < until
    }

    /**
     * Cửa gỡ app: chỉ [UninstallGate.begin] được gọi hàm này (sau khi Dart đã
     * qua PIN + sinh trắc). Lưu bền, hết hạn theo đồng hồ elapsed như [allowSettings].
     */
    fun beginUninstallWindow(context: Context, seconds: Long, adminWasRemoved: Boolean) {
        prefs(context).edit()
            .putLong(KEY_UNINSTALL_UNTIL, elapsedNow() + seconds * 1000)
            .putInt(KEY_UNINSTALL_BOOT, bootCount(context))
            .putBoolean(KEY_ADMIN_RESTORE, adminWasRemoved)
            .apply()
    }

    fun uninstallAllowed(context: Context): Boolean {
        val p = prefs(context)
        val until = p.getLong(KEY_UNINSTALL_UNTIL, 0L)
        if (until == 0L) return false
        if (p.getInt(KEY_UNINSTALL_BOOT, -1) != bootCount(context)) return false
        return elapsedNow() < until
    }

    /** Đóng cửa gỡ app. Trả về `true` nếu Quản trị thiết bị đã bị gỡ và cần bật lại. */
    fun endUninstallWindow(context: Context): Boolean {
        val p = prefs(context)
        val restore = p.getBoolean(KEY_ADMIN_RESTORE, false)
        p.edit().remove(KEY_UNINSTALL_UNTIL).remove(KEY_UNINSTALL_BOOT).apply()
        return restore
    }

    fun adminRestorePending(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ADMIN_RESTORE, false)

    fun clearAdminRestore(context: Context) {
        prefs(context).edit().putBoolean(KEY_ADMIN_RESTORE, false).apply()
    }

    fun setChallengePending(context: Context, pending: Boolean) {
        prefs(context).edit().putBoolean(KEY_CHALLENGE, pending).apply()
    }

    /** Lấy và xóa cờ "cần hỏi PIN" (Dart gọi mỗi lần app hiện lên). */
    fun consumeChallenge(context: Context): Boolean {
        val p = prefs(context)
        val pending = p.getBoolean(KEY_CHALLENGE, false)
        if (pending) p.edit().putBoolean(KEY_CHALLENGE, false).apply()
        return pending
    }

    /** Con bấm "Xin thêm giờ" trên màn chặn: SafeFamily phải hiện hộp chọn số phút + xác thực. */
    fun setExtraTimePending(context: Context, pending: Boolean) {
        prefs(context).edit().putBoolean(KEY_EXTRA_TIME, pending).apply()
    }

    fun consumeExtraTime(context: Context): Boolean {
        val p = prefs(context)
        val pending = p.getBoolean(KEY_EXTRA_TIME, false)
        if (pending) p.edit().putBoolean(KEY_EXTRA_TIME, false).apply()
        return pending
    }

    /**
     * Các app máy mẹ đang khóa (`policy.appLock.blocked`, đã lọc app hệ thống).
     * Giữ riêng để lần đồng bộ sau chỉ gỡ đúng những app mẹ vừa bỏ khóa, không
     * đụng tới app bị khóa bằng cách khác.
     */
    fun remoteBlocked(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_REMOTE_BLOCKED, emptySet())?.toSet() ?: emptySet()

    fun setRemoteBlocked(context: Context, packages: Set<String>) {
        prefs(context).edit().putStringSet(KEY_REMOTE_BLOCKED, HashSet(packages)).apply()
    }

    /** Danh bạ gia đình (chỉ người có số) để màn chặn gọi được khi Flutter không chạy. */
    data class Contact(val label: String, val phone: String, val emergency: Boolean)

    fun setContacts(context: Context, contacts: List<Contact>) {
        val array = org.json.JSONArray()
        for (c in contacts) {
            array.put(
                org.json.JSONObject()
                    .put("label", c.label)
                    .put("phone", c.phone)
                    .put("emergency", c.emergency),
            )
        }
        prefs(context).edit().putString(KEY_CONTACTS, array.toString()).apply()
    }

    fun contacts(context: Context): List<Contact> {
        val raw = prefs(context).getString(KEY_CONTACTS, null) ?: return emptyList()
        return runCatching {
            val array = org.json.JSONArray(raw)
            (0 until array.length()).map {
                val o = array.getJSONObject(it)
                Contact(o.getString("label"), o.getString("phone"), o.optBoolean("emergency"))
            }
        }.getOrDefault(emptyList())
    }

    /**
     * Số SOS mẹ chọn, đến từ `policy.contacts` (API-13). Tách khỏi [contacts] (danh bạ trên máy con):
     * luật mới của mẹ thay hết danh sách này, kể cả thành rỗng.
     */
    fun setSos(context: Context, sos: List<Contact>) {
        val array = org.json.JSONArray()
        for (c in sos) array.put(org.json.JSONObject().put("label", c.label).put("phone", c.phone))
        prefs(context).edit().putString(KEY_SOS, array.toString()).apply()
    }

    fun sos(context: Context): List<Contact> {
        val raw = prefs(context).getString(KEY_SOS, null) ?: return emptyList()
        return runCatching {
            val array = org.json.JSONArray(raw)
            (0 until array.length()).map {
                val o = array.getJSONObject(it)
                Contact(o.getString("label"), o.getString("phone"), true)
            }
        }.getOrDefault(emptyList())
    }
}
