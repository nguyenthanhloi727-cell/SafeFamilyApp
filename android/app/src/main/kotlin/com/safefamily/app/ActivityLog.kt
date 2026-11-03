package com.safefamily.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Nhật ký hoạt động của máy con cho mẹ xem (T8, `POST /api/devices/me/activity`): con mở app bị chặn (tên gói),
 * nhập sai PIN / vân tay ở khu phụ huynh, phụ huynh mở khóa thành công. Chỉ gửi LOẠI sự kiện, tên gói (với
 * [BLOCKED_APP_OPEN]) và thời điểm: không nội dung, không vị trí.
 *
 * Sự kiện xếp hàng trong SharedPreferences (không mất khi offline hay kill app), gửi theo lô trong
 * [FamilySync.syncOnce] ([syncWithServer]) và ngay sau khi ghi ở luồng nền. Mọi lỗi mạng/máy chủ bị nuốt để không
 * làm hỏng lượt đồng bộ. Máy chưa ghép đôi (kể cả máy mẹ) thì không ghi gì.
 */
object ActivityLog {
    const val BLOCKED_APP_OPEN = "blocked_app_open"
    const val PARENT_AUTH_FAILED = "parent_auth_failed"
    const val PARENT_UNLOCKED = "parent_unlocked"

    private val KINDS = setOf(BLOCKED_APP_OPEN, PARENT_AUTH_FAILED, PARENT_UNLOCKED)

    private const val FILE = "safefamily_activity"
    private const val KEY_PENDING = "pending"
    private const val KEY_LAST = "last_queued" // {kind|detail: thời điểm ghi gần nhất} để chống ghi dồn

    private const val MAX_QUEUE = 200

    /** Khớp ActivityRules.MaxBatch ở server. */
    private const val BATCH = 50

    /** Cùng một app bị chặn bị mở liên tục (hệ thống bắn nhiều sự kiện cửa sổ) chỉ ghi một dòng trong khoảng này. */
    private const val DEDUP_MS = 60_000L

    /** Nhỏ hơn ActivityRules.Retention (30 ngày): quá hạn thì server từ chối cả lô (400), bỏ luôn cho khỏi kẹt. */
    private const val MAX_AGE_MS = 29L * 24 * 60 * 60_000L

    /** Khớp ActivityRules.PackageName / MaxDetailLength. */
    private val PACKAGE_RE = Regex("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*$")
    private const val MAX_DETAIL = 100

    private val queueLock = Any()
    private val netLock = Any()

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Hủy ghép / đổi vai trò / ghép lại: quên hết, không gửi nhật ký của lần ghép trước. */
    fun forget(context: Context) {
        synchronized(queueLock) { prefs(context).edit().clear().commit() }
    }

    /** Ghi một sự kiện rồi gửi ngay ở luồng nền (không chặn luồng gọi). Gọi được từ luồng chính. */
    fun record(context: Context, kind: String, detail: String? = null) {
        if (queue(context, kind, detail, System.currentTimeMillis())) Thread { flush(context) }.start()
    }

    private fun queue(context: Context, kind: String, detail: String?, atMs: Long): Boolean {
        if (kind !in KINDS) return false
        // Loại có tên gói thì bắt buộc đúng dạng; loại còn lại không mang detail.
        val d = if (kind == BLOCKED_APP_OPEN) {
            detail?.takeIf { it.length <= MAX_DETAIL && PACKAGE_RE.matches(it) } ?: return false
        } else null
        if (!FamilySync.isConfigured(context)) return false
        return synchronized(queueLock) {
            val p = prefs(context)
            val last = runCatching { JSONObject(p.getString(KEY_LAST, "{}")) }.getOrDefault(JSONObject())
            val dedupKey = "$kind|${d ?: ""}"
            // Nhập sai PIN nhiều lần là điều mẹ cần thấy, nên chỉ chống dồn với app bị chặn.
            if (kind == BLOCKED_APP_OPEN && kotlin.math.abs(atMs - last.optLong(dedupKey, 0L)) < DEDUP_MS) return@synchronized false
            val queue = JSONArray(p.getString(KEY_PENDING, "[]"))
            val item = JSONObject().put("kind", kind).put("at", atMs)
            d?.let { item.put("detail", it) }
            queue.put(item)
            val kept = if (queue.length() > MAX_QUEUE) {
                JSONArray().also { out -> for (i in queue.length() - MAX_QUEUE until queue.length()) out.put(queue.get(i)) }
            } else queue
            last.put(dedupKey, atMs)
            // commit(): có thể bị kill ngay sau đó, không chờ ghi nền.
            p.edit().putString(KEY_PENDING, kept.toString()).putString(KEY_LAST, last.toString()).commit()
        }
    }

    /** Lượt đồng bộ: gửi bù hàng chờ. Gọi trong [FamilySync.syncOnce]; mọi lỗi bị nuốt. */
    fun syncWithServer(context: Context) = flush(context)

    /**
     * Gửi hàng chờ theo lô ≤ [BATCH], cũ trước. 2xx và 400/404 (server không nhận) → bỏ lô khỏi hàng;
     * 401/429/5xx/mất mạng → giữ phần còn lại, lượt sau thử lại. Đồng bộ (đồng thời chỉ một luồng gửi).
     */
    fun flush(context: Context) {
        synchronized(netLock) {
            runCatching {
                if (!FamilySync.isConfigured(context)) return
                val p = prefs(context)
                while (true) {
                    val all = synchronized(queueLock) { JSONArray(p.getString(KEY_PENDING, "[]")) }
                    // Bỏ mục quá hạn trước khi gửi: một mục cũ sẽ làm server từ chối cả lô.
                    val fresh = JSONArray()
                    for (i in 0 until all.length()) {
                        val item = all.getJSONObject(i)
                        if (System.currentTimeMillis() - item.optLong("at", 0L) <= MAX_AGE_MS) fresh.put(item)
                    }
                    if (fresh.length() == 0) {
                        if (all.length() > 0) drop(p, all)
                        return
                    }
                    val batch = JSONArray()
                    for (i in 0 until minOf(BATCH, fresh.length())) batch.put(fresh.get(i))
                    val events = JSONArray()
                    for (i in 0 until batch.length()) {
                        val item = batch.getJSONObject(i)
                        val e = JSONObject().put("kind", item.getString("kind")).put("occurredAt", FamilySync.iso(item.optLong("at", 0L)))
                        item.optString("detail").takeIf { it.isNotEmpty() }?.let { e.put("detail", it) }
                        events.put(e)
                    }
                    // IOException: giữ nguyên hàng chờ
                    val r = FamilySync.request(context, "POST", "/api/devices/me/activity", JSONObject().put("events", events))
                    when (r.code) {
                        in 200..299, 400, 404 -> {
                            // Bỏ lô vừa gửi cùng các mục quá hạn đã lọc ra.
                            val sent = (0 until batch.length()).map { key(batch.getJSONObject(it)) }.toSet()
                            val stale = (0 until all.length()).map { all.getJSONObject(it) }
                                .filter { System.currentTimeMillis() - it.optLong("at", 0L) > MAX_AGE_MS }
                                .map { key(it) }
                            drop(p, null, sent + stale)
                            if (fresh.length() <= BATCH) return
                        }
                        else -> return
                    }
                }
            }
        }
    }

    /** Bỏ các mục [gone] (hoặc toàn bộ [all] nếu cho) khỏi hàng chờ; đọc lại vì có thể vừa xếp thêm trong lúc gửi. */
    private fun drop(p: android.content.SharedPreferences, all: JSONArray?, gone: Set<String> = emptySet()) {
        synchronized(queueLock) {
            val now = JSONArray(p.getString(KEY_PENDING, "[]"))
            val skip = gone + (if (all != null) (0 until all.length()).map { key(all.getJSONObject(it)) } else emptyList())
            val rest = JSONArray()
            for (i in 0 until now.length()) if (key(now.getJSONObject(i)) !in skip) rest.put(now.getJSONObject(i))
            p.edit().putString(KEY_PENDING, rest.toString()).commit()
        }
    }

    private fun key(item: JSONObject) = "${item.optString("kind")}@${item.optLong("at", 0L)}@${item.optString("detail")}"
}
