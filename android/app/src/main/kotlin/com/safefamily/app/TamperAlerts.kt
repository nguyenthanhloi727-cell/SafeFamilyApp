package com.safefamily.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Máy con báo mẹ khi bị can thiệp (API-10, `POST /api/devices/me/alerts`): đổi giờ máy, cố gỡ app,
 * tắt Trợ năng / Quản trị thiết bị, thiếu quyền. Chỉ gửi LOẠI sự kiện, mã/số ngắn và thời điểm: không nội dung, không vị trí.
 * ("Mất kết nối" do server tự phát hiện, máy con không tự báo được.)
 *
 * Cảnh báo xếp hàng trong SharedPreferences (không mất khi offline hay kill app) rồi gửi ngay ở luồng nền;
 * chưa gửi được thì [syncWithServer] (mỗi lượt [FamilySync.syncOnce]) gửi bù. Mọi lỗi mạng/máy chủ bị nuốt
 * để không làm hỏng lượt đồng bộ. Máy chưa ghép đôi thì không làm gì.
 *
 * Quyền/giờ: so với MỐC lúc ghép đôi ([reset]) nên quyền chưa cấp xong lúc cài đặt không báo; chỉ báo khi mất đi
 * (cạnh xuống), và báo lại nếu cấp rồi mất lần nữa. Trùng loại trong 10 phút thì bỏ (server cũng chặn trùng).
 * TODO(verify): trên máy thật (Xiaomi T11 Pro) xem tắt Trợ năng có gọi `onUnbind` của [SettingsGuardService] không,
 * và cập nhật app (khởi động lại dịch vụ) có báo nhầm không (đã chờ [CONFIRM_DELAY_MS] giây rồi kiểm lại để giảm).
 */
object TamperAlerts {
    const val TIME_CHANGED = "time_changed"
    const val APP_UNINSTALL_ATTEMPT = "app_uninstall_attempt"
    const val ACCESSIBILITY_OFF = "accessibility_off"
    const val DEVICE_ADMIN_OFF = "device_admin_off"
    const val PERMISSION_MISSING = "permission_missing"

    private val KINDS = setOf(TIME_CHANGED, APP_UNINSTALL_ATTEMPT, ACCESSIBILITY_OFF, DEVICE_ADMIN_OFF, PERMISSION_MISSING)

    private const val FILE = "safefamily_alerts"
    private const val KEY_PENDING = "pending"
    private const val KEY_LAST = "last_queued" // {kind: thời điểm xếp hàng gần nhất}
    private const val KEY_PERMS = "missing_permissions" // quyền đang thiếu đã tính (cạnh xuống); vắng = chưa có mốc
    private const val KEY_JUMP_AT = "jump_alerted_at"

    private const val MAX_QUEUE = 30

    /** Khớp AlertRules.DedupWindow ở server. */
    private const val DEDUP_MS = 10 * 60_000L

    /** Nhỏ hơn AlertRules.MaxEventAge (7 ngày) một chút: quá hạn thì server từ chối (400), bỏ luôn cho khỏi kẹt. */
    private const val MAX_AGE_MS = 7 * 24 * 60 * 60_000L - 60 * 60_000L
    private const val CONFIRM_DELAY_MS = 15_000L

    /** Khớp AlertRules.DetailCode: chỉ mã/số ngắn. */
    private val DETAIL_RE = Regex("^-?[a-z0-9_]{1,31}$")

    private val queueLock = Any()
    private val netLock = Any()

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Ghép đôi (hoặc ghép lại): bỏ hàng chờ cũ và lấy mốc quyền + giờ hiện tại để không báo những gì có từ trước. */
    fun reset(context: Context) {
        synchronized(queueLock) {
            val edit = prefs(context).edit().clear()
            runCatching { edit.putString(KEY_PERMS, JSONArray(PermissionStatus.missing(context)).toString()) }
            edit.putLong(KEY_JUMP_AT, newestJump(context)?.first ?: 0L)
            edit.commit()
        }
    }

    /** Hủy ghép / đổi vai trò: quên hết. */
    fun forget(context: Context) {
        synchronized(queueLock) { prefs(context).edit().clear().commit() }
    }

    // ---- Điểm vào cho các nơi phát hiện --------------------------------------

    /** Xếp hàng rồi gửi ngay ở luồng nền (không chặn luồng gọi). Gọi được từ luồng chính. */
    fun report(context: Context, kind: String, detail: String? = null) {
        if (queue(context, kind, detail, System.currentTimeMillis())) Thread { flush(context) }.start()
    }

    /** Một quyền vừa mất. Mỗi lần mất chỉ báo một lần (cạnh xuống) dù phát hiện từ nhiều đường. */
    fun permissionLost(context: Context, id: String) {
        if (!FamilySync.isConfigured(context)) return
        if (id == "device_admin" && GuardPrefs.uninstallAllowed(context)) return // phụ huynh đang gỡ app hợp lệ
        val queued = synchronized(queueLock) {
            // Chưa có mốc (bản cũ nâng cấp): lấy mốc là các quyền khác đang thiếu, để chỉ báo đúng quyền vừa mất.
            val known = if (prefs(context).contains(KEY_PERMS)) strings(context, KEY_PERMS)
            else runCatching { PermissionStatus.missing(context).toSet() - id }.getOrDefault(emptySet())
            if (id in known) return@synchronized false
            prefs(context).edit().putString(KEY_PERMS, JSONArray(known + id).toString()).commit()
            queueLocked(context, kindFor(id), id, System.currentTimeMillis())
        }
        if (queued) Thread { flush(context) }.start()
    }

    /**
     * Dịch vụ [id] vừa bị ngắt kết nối: chờ [CONFIRM_DELAY_MS] rồi kiểm lại, vì cập nhật app hay hệ thống khởi động
     * lại dịch vụ cũng gọi ngắt kết nối. Vẫn thiếu thì mới báo.
     */
    fun confirmLost(context: Context, id: String) {
        val app = context.applicationContext
        Thread {
            runCatching {
                Thread.sleep(CONFIRM_DELAY_MS)
                if (PermissionStatus.snapshot(app)[id] == false) permissionLost(app, id)
            }
        }.start()
    }

    /** Xếp hàng báo giờ máy bị đổi nếu nhật ký của [TimeLimits] có lần lệch mới. `true` = có xếp hàng (cần [flush]). */
    fun checkTimeJumps(context: Context): Boolean {
        if (!FamilySync.isConfigured(context)) return false
        val (at, skewMs) = newestJump(context) ?: return false
        return synchronized(queueLock) {
            val p = prefs(context)
            if (at <= p.getLong(KEY_JUMP_AT, 0L)) return@synchronized false
            p.edit().putLong(KEY_JUMP_AT, at).commit()
            // Lệch tính bằng phút (có dấu): chỉ số, không nội dung.
            queueLocked(context, TIME_CHANGED, (skewMs / 60_000L).toString(), at)
        }
    }

    /** Quyền mới thiếu so với lần trước → xếp hàng. Lần đầu (chưa có mốc) chỉ ghi mốc. */
    private fun checkPermissions(context: Context) {
        val missing = PermissionStatus.missing(context).toMutableSet()
        if (GuardPrefs.uninstallAllowed(context)) missing.remove("device_admin")
        synchronized(queueLock) {
            val p = prefs(context)
            val first = !p.contains(KEY_PERMS)
            val known = strings(context, KEY_PERMS)
            p.edit().putString(KEY_PERMS, JSONArray(missing.toList()).toString()).commit()
            if (first) return
            for (id in missing - known) queueLocked(context, kindFor(id), id, System.currentTimeMillis())
        }
    }

    /** Trợ năng (cả hai dịch vụ) → `accessibility_off`; Quản trị thiết bị → `device_admin_off`; còn lại → `permission_missing`. */
    private fun kindFor(id: String): String = when (id) {
        "accessibility", "settings_guard" -> ACCESSIBILITY_OFF
        "device_admin" -> DEVICE_ADMIN_OFF
        else -> PERMISSION_MISSING
    }

    // ---- Hàng chờ ---------------------------------------------------------------

    private fun queue(context: Context, kind: String, detail: String?, atMs: Long): Boolean {
        if (!FamilySync.isConfigured(context)) return false
        return synchronized(queueLock) { queueLocked(context, kind, detail, atMs) }
    }

    /** Gọi trong [queueLock]. `false` nếu bỏ (loại lạ, trùng trong 10 phút, máy chưa ghép). */
    private fun queueLocked(context: Context, kind: String, detail: String?, atMs: Long): Boolean {
        if (kind !in KINDS) return false
        val p = prefs(context)
        val last = runCatching { JSONObject(p.getString(KEY_LAST, "{}")) }.getOrDefault(JSONObject())
        if (kotlin.math.abs(atMs - last.optLong(kind, 0L)) < DEDUP_MS) return false
        val queue = JSONArray(p.getString(KEY_PENDING, "[]"))
        val item = JSONObject().put("kind", kind).put("at", atMs)
        detail?.takeIf { DETAIL_RE.matches(it) }?.let { item.put("detail", it) }
        queue.put(item)
        val kept = if (queue.length() > MAX_QUEUE) {
            JSONArray().also { out -> for (i in queue.length() - MAX_QUEUE until queue.length()) out.put(queue.get(i)) }
        } else queue
        last.put(kind, atMs)
        // commit(): có thể bị kill ngay sau đó (tiến trình tắt, gỡ app), không chờ ghi nền.
        return p.edit().putString(KEY_PENDING, kept.toString()).putString(KEY_LAST, last.toString()).commit()
    }

    /** Lượt đồng bộ: phát hiện giờ/quyền mới rồi gửi bù hàng chờ. Gọi trong [FamilySync.syncOnce]; mọi lỗi bị nuốt. */
    fun syncWithServer(context: Context) {
        runCatching { checkTimeJumps(context) }
        runCatching { checkPermissions(context) }
        flush(context)
    }

    /**
     * Gửi hàng chờ (cũ trước). 200/409 (đã có) và 400/404 (server không nhận) → bỏ khỏi hàng; 401/429/5xx/mất mạng → giữ
     * phần còn lại, lượt sau thử lại. Đồng bộ (đồng thời chỉ một luồng gửi).
     */
    fun flush(context: Context) {
        synchronized(netLock) {
            runCatching {
                if (!FamilySync.isConfigured(context)) return
                val p = prefs(context)
                val queue = synchronized(queueLock) { JSONArray(p.getString(KEY_PENDING, "[]")) }
                if (queue.length() == 0) return
                val handled = mutableSetOf<String>()
                try {
                    for (i in 0 until queue.length()) {
                        val item = queue.getJSONObject(i)
                        val at = item.optLong("at", 0L)
                        if (System.currentTimeMillis() - at > MAX_AGE_MS) { handled.add(key(item)); continue }
                        val body = JSONObject().put("kind", item.getString("kind")).put("occurredAt", FamilySync.iso(at))
                        item.optString("detail").takeIf { it.isNotEmpty() }?.let { body.put("detail", it) }
                        val r = FamilySync.request(context, "POST", "/api/devices/me/alerts", body) // IOException: giữ nguyên hàng
                        when (r.code) {
                            in 200..299, 409, 400, 404 -> handled.add(key(item))
                            else -> break
                        }
                    }
                } finally {
                    if (handled.isNotEmpty()) synchronized(queueLock) {
                        // Đọc lại: có thể vừa xếp thêm trong lúc đang gửi.
                        val now = JSONArray(p.getString(KEY_PENDING, "[]"))
                        val rest = JSONArray()
                        for (i in 0 until now.length()) if (key(now.getJSONObject(i)) !in handled) rest.put(now.getJSONObject(i))
                        p.edit().putString(KEY_PENDING, rest.toString()).commit()
                    }
                }
            }
        }
    }

    private fun key(item: JSONObject) = "${item.optString("kind")}@${item.optLong("at", 0L)}"

    private fun strings(context: Context, key: String): Set<String> {
        val array = runCatching { JSONArray(prefs(context).getString(key, "[]")) }.getOrDefault(JSONArray())
        return (0 until array.length()).map { array.getString(it) }.toSet()
    }

    /** (thời điểm, độ lệch ms) của lần đổi giờ mới nhất trong nhật ký [TimeLimits.timeJumps], hoặc `null`. */
    private fun newestJump(context: Context): Pair<Long, Long>? = runCatching {
        val log = JSONArray(TimeLimits.timeJumps(context))
        var best: Pair<Long, Long>? = null
        for (i in 0 until log.length()) {
            val e = log.getJSONObject(i)
            val at = e.optLong("at", 0L)
            if (at > (best?.first ?: 0L)) best = at to e.optLong("skewMs", 0L)
        }
        best
    }.getOrNull()
}
