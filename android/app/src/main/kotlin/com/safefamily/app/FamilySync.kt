package com.safefamily.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.khanhtq.app_blocker.blocking.BlockingServiceManager
import com.khanhtq.app_blocker.persistence.BlockerPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Máy con nói chuyện với API (docs/API_TIEN_TRINH.md): hỏi lệnh và luật, tải hàng
 * rào địa lý, gửi vị trí và sự kiện vào/ra vùng. Chạy nguyên trong Kotlin để
 * vẫn đồng bộ khi Flutter không chạy (app bị đóng); Dart chỉ ghi địa chỉ + token
 * thiết bị qua [configure].
 *
 * Mọi dữ liệu chờ gửi (vị trí, sự kiện hàng rào) nằm trong SharedPreferences, nên
 * offline hay kill app không mất; gửi bù khi có mạng.
 * TODO(verify): token thiết bị đang lưu SharedPreferences thường (app tắt backup);
 * cân nhắc EncryptedSharedPreferences/Keystore trước khi phát hành.
 */
object FamilySync {
    private const val FILE = "safefamily_family"
    private const val KEY_URL = "base_url"
    private const val KEY_TOKEN = "device_token"
    private const val KEY_POLICY_VERSION = "policy_version"
    private const val KEY_GEOFENCE_VERSION = "geofence_version"
    private const val KEY_LOCATIONS = "pending_locations"
    private const val KEY_EVENTS = "pending_events"
    private const val KEY_REQUESTS = "pending_requests"
    private const val KEY_TRACKED = "tracked_requests"
    private const val MAX_QUEUE = 500
    private const val TIMEOUT_MS = 15_000
    private const val DEFAULT_LOCK_MINUTES = 60

    /** Khớp CommandRules.MaxUnlockMinutes ở server. */
    private const val MAX_UNLOCK_MINUTES = 240

    /** Khớp CommandRules.MaxExtraMinutes ở server. */
    private const val MAX_EXTRA_MINUTES = 120

    /** Loại yêu cầu của con (RequestRules ở server). */
    const val REQUEST_EXTRA_TIME = "extra_time"
    const val REQUEST_STUDY_DONE = "study_done"
    private const val MAX_REQUEST_QUEUE = 10
    private const val MAX_TRACKED = 20

    /** Khớp RequestRules.PendingMaxAge ở server: quá hạn này server không còn xét yêu cầu. */
    private const val REQUEST_MAX_AGE_MS = 24 * 60 * 60_000L
    private const val REQUEST_CHANNEL = "request_result"
    private const val REQUEST_NOTIFICATION_ID = 0x57D2

    /** Bản schema gói luật máy con hiểu (xem lib/core/network/policy_schema.dart). */
    private const val SUPPORTED_SCHEMA = 1

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun isConfigured(context: Context): Boolean {
        val p = prefs(context)
        return !p.getString(KEY_URL, null).isNullOrEmpty() && !p.getString(KEY_TOKEN, null).isNullOrEmpty()
    }

    @Synchronized
    fun configure(context: Context, baseUrl: String, token: String) {
        val p = prefs(context)
        val changed = p.getString(KEY_TOKEN, null) != token
        p.edit().putString(KEY_URL, baseUrl.trimEnd('/')).putString(KEY_TOKEN, token).apply()
        if (changed) resetVersions(context)
    }

    /** Hủy ghép / đổi vai trò: quên token, xóa hàng chờ, gỡ hàng rào đã đăng ký. */
    @Synchronized
    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
        runCatching { Geofences.removeAll(context) }
        stopService(context)
    }

    private fun resetVersions(context: Context) {
        prefs(context).edit().remove(KEY_POLICY_VERSION).remove(KEY_GEOFENCE_VERSION).apply()
    }

    // ---- Dịch vụ nền -------------------------------------------------------

    fun hasLocationPermission(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    fun hasBackgroundLocation(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            context.checkSelfPermission(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** Bật dịch vụ nền nếu máy này đã ghép đôi. An toàn khi gọi nhiều lần. */
    fun ensureService(context: Context) {
        if (!isConfigured(context)) return
        runCatching {
            val intent = Intent(context, FamilyService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } // TODO(verify): Android 12+ có thể từ chối khởi động nền; mở app sẽ bật lại.
    }

    /** Sau khởi động máy hệ thống đã xóa hàng rào: bắt buộc tải và đăng ký lại ở lượt đồng bộ kế. */
    fun onBoot(context: Context) {
        prefs(context).edit().remove(KEY_GEOFENCE_VERSION).apply()
    }

    fun stopService(context: Context) {
        runCatching { context.stopService(Intent(context, FamilyService::class.java)) }
    }

    // ---- Hàng chờ gửi ------------------------------------------------------

    @Synchronized
    fun addLocation(context: Context, lat: Double, lng: Double, accuracy: Double, timeMs: Long) {
        append(context, KEY_LOCATIONS, JSONObject()
            .put("lat", lat).put("lng", lng).put("accuracy", accuracy).put("time", iso(timeMs)))
    }

    @Synchronized
    fun addGeofenceEvent(context: Context, geofenceId: Int, type: String, timeMs: Long) {
        append(context, KEY_EVENTS, JSONObject()
            .put("geofenceId", geofenceId).put("type", type).put("time", iso(timeMs)))
    }

    private fun append(context: Context, key: String, item: JSONObject) {
        val p = prefs(context)
        val list = JSONArray(p.getString(key, "[]"))
        list.put(item)
        val kept = if (list.length() > MAX_QUEUE) {
            JSONArray().also { out -> for (i in list.length() - MAX_QUEUE until list.length()) out.put(list.get(i)) }
        } else list
        p.edit().putString(key, kept.toString()).apply()
    }

    private fun iso(ms: Long): String {
        val f = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
        f.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return f.format(java.util.Date(ms))
    }

    // ---- Đồng bộ một lượt --------------------------------------------------

    /** Một lượt: lệnh → luật → hàng rào → trạng thái → yêu cầu → app mới → gửi vị trí → gửi sự kiện. Gọi ở luồng nền. */
    @Synchronized
    fun syncOnce(context: Context): Boolean {
        if (!isConfigured(context)) return false
        return try {
            if (!pullCommands(context)) return false
            TempRelocks.sweep(context) // chặn lại app mở tạm đã quá hạn
            pullPolicy(context)
            pullGeofences(context)
            pushStatus(context) // lỗi mạng/ máy chủ chỉ bỏ qua lượt này, không làm hỏng các bước còn lại
            syncRequests(context) // gửi yêu cầu chờ + xem kết quả; mọi lỗi chỉ bỏ qua lượt này
            NewApps.syncWithServer(context) // app mới cài lên + quyết định của mẹ xuống; mọi lỗi chỉ bỏ qua
            flush(context, KEY_LOCATIONS, "locations", "points")
            flush(context, KEY_EVENTS, "geofence-events", "events")
            true
        } catch (e: java.io.IOException) {
            false // offline: giữ nguyên luật + hàng chờ, lượt sau thử lại
        }
    }

    // ---- Yêu cầu của con (API-06) ------------------------------------------

    /**
     * Con xin thêm giờ / báo "đã học xong". Xếp vào hàng chờ (SharedPreferences, không mất khi offline hay kill
     * app) rồi gửi ngay ở luồng nền nếu có mạng; không có mạng thì lượt đồng bộ sau gửi bù. CHỈ gửi loại yêu cầu
     * và số phút xin ([minutes] chỉ cho extra_time), không gửi app đang dùng hay nội dung. Máy chưa ghép thì bỏ qua.
     * Cùng loại đang chờ thì không xếp thêm (server cũng chặn trùng).
     */
    fun queueRequest(context: Context, kind: String, minutes: Int = 0) {
        if (!isConfigured(context)) return
        if (kind == REQUEST_EXTRA_TIME && minutes !in 1..MAX_EXTRA_MINUTES) return
        val p = prefs(context)
        // Khóa riêng (không phải khóa của FamilySync): StudyBlock giữ khóa của nó khi gọi vào đây, còn
        // syncOnce giữ khóa FamilySync khi gọi StudyBlock; dùng chung khóa sẽ khóa chéo nhau.
        synchronized(requestQueueLock) {
            val queue = JSONArray(p.getString(KEY_REQUESTS, "[]"))
            for (i in 0 until queue.length()) if (queue.getJSONObject(i).optString("kind") == kind) return
            if (queue.length() >= MAX_REQUEST_QUEUE) return
            val item = JSONObject().put("kind", kind).put("at", System.currentTimeMillis())
            if (kind == REQUEST_EXTRA_TIME) item.put("minutes", minutes)
            queue.put(item)
            p.edit().putString(KEY_REQUESTS, queue.toString()).apply()
        }
        Thread { syncRequests(context) }.start()
    }

    private val requestQueueLock = Any()
    private val requestSyncLock = Any()

    /** Gửi hàng chờ rồi hỏi kết quả các yêu cầu đã gửi. Lỗi (mạng, 5xx, đọc dữ liệu) bị nuốt: lượt sau thử lại. */
    private fun syncRequests(context: Context) {
        synchronized(requestSyncLock) {
            runCatching {
                flushRequests(context)
                pollRequests(context)
            }
        }
    }

    private fun flushRequests(context: Context) {
        val p = prefs(context)
        val queue = synchronized(requestQueueLock) { JSONArray(p.getString(KEY_REQUESTS, "[]")) }
        if (queue.length() == 0) return
        val handled = mutableSetOf<String>() // mục đã gửi xong hoặc bỏ; phần còn lại giữ nguyên trong hàng
        var stop = false
        try {
            for (i in 0 until queue.length()) {
                if (stop) break
                val item = queue.getJSONObject(i)
                val key = "${item.optString("kind")}@${item.optLong("at", 0L)}"
                // Quá hạn thì server cũng không xét nữa: bỏ, con bấm lại nếu vẫn cần.
                if (System.currentTimeMillis() - item.optLong("at", 0L) > REQUEST_MAX_AGE_MS) { handled.add(key); continue }
                val kind = item.getString("kind")
                val payload = if (kind == REQUEST_EXTRA_TIME) JSONObject().put("minutes", item.getInt("minutes")) else JSONObject()
                val body = JSONObject().put("kind", kind).put("payloadJson", payload.toString())
                val r = request(context, "POST", "/api/devices/me/requests", body) // IOException: offline, giữ nguyên hàng
                when (r.code) {
                    200, 409 -> { // 409 = đã có yêu cầu cùng loại đang chờ: theo dõi chính nó
                        val id = runCatching { JSONObject(r.body).getInt("id") }.getOrNull()
                        if (id != null) track(context, id, kind)
                        handled.add(key)
                    }
                    400, 401, 404 -> handled.add(key) // dữ liệu hỏng / máy bị hủy ghép: bỏ, tránh kẹt hàng chờ
                    else -> stop = true // 429, 5xx: giữ, thử lại sau
                }
            }
        } finally {
            if (handled.isNotEmpty()) synchronized(requestQueueLock) {
                // Đọc lại: con có thể vừa xếp thêm yêu cầu trong lúc đang gửi.
                val now = JSONArray(p.getString(KEY_REQUESTS, "[]"))
                val rest = JSONArray()
                for (i in 0 until now.length()) {
                    val entry = now.getJSONObject(i)
                    if ("${entry.optString("kind")}@${entry.optLong("at", 0L)}" !in handled) rest.put(entry)
                }
                p.edit().putString(KEY_REQUESTS, rest.toString()).apply()
            }
        }
    }

    private fun track(context: Context, id: Int, kind: String) {
        val p = prefs(context)
        val list = JSONArray(p.getString(KEY_TRACKED, "[]"))
        for (i in 0 until list.length()) if (list.getJSONObject(i).optInt("id") == id) return
        list.put(JSONObject().put("id", id).put("kind", kind).put("at", System.currentTimeMillis()))
        val kept = if (list.length() > MAX_TRACKED) {
            JSONArray().also { out -> for (i in list.length() - MAX_TRACKED until list.length()) out.put(list.get(i)) }
        } else list
        p.edit().putString(KEY_TRACKED, kept.toString()).apply()
    }

    /** Hỏi kết quả từng yêu cầu đang theo dõi; đã duyệt/từ chối thì báo con rồi thôi theo dõi. */
    private fun pollRequests(context: Context) {
        val p = prefs(context)
        val tracked = JSONArray(p.getString(KEY_TRACKED, "[]"))
        if (tracked.length() == 0) return
        val keep = JSONArray()
        for (i in 0 until tracked.length()) {
            val item = tracked.getJSONObject(i)
            val r = try {
                request(context, "GET", "/api/devices/me/requests/${item.getInt("id")}", null)
            } catch (e: java.io.IOException) {
                for (j in i until tracked.length()) keep.put(tracked.get(j)) // offline: giữ phần còn lại
                break
            }
            val expired = System.currentTimeMillis() - item.optLong("at", 0L) > REQUEST_MAX_AGE_MS
            when (r.code) {
                200 -> {
                    val status = runCatching { JSONObject(r.body).getString("status") }.getOrDefault("pending")
                    if (status == "pending") {
                        if (!expired) keep.put(item)
                    } else {
                        notifyRequestResult(context, item.getString("kind"), status == "approved")
                    }
                }
                404 -> {} // server không còn yêu cầu này
                else -> if (!expired) keep.put(item)
            }
        }
        p.edit().putString(KEY_TRACKED, keep.toString()).apply()
    }

    /** Con thấy kết quả bằng thông báo. Thiếu quyền POST_NOTIFICATIONS thì notify() bị bỏ qua (TODO(verify) trên máy thật). */
    private fun notifyRequestResult(context: Context, kind: String, approved: Boolean) {
        runCatching {
            val text = when {
                kind == REQUEST_EXTRA_TIME && approved -> "Bố mẹ đã đồng ý cho thêm giờ."
                kind == REQUEST_EXTRA_TIME -> "Bố mẹ chưa đồng ý cho thêm giờ."
                approved -> "Bố mẹ đã duyệt: con dùng máy lại được."
                else -> "Bố mẹ chưa duyệt, con học tiếp nhé."
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    android.app.NotificationChannel(REQUEST_CHANNEL, "Trả lời của bố mẹ", android.app.NotificationManager.IMPORTANCE_DEFAULT),
                )
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(context, REQUEST_CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }
            manager.notify(
                REQUEST_NOTIFICATION_ID + if (kind == REQUEST_EXTRA_TIME) 0 else 1,
                builder.setSmallIcon(context.applicationInfo.icon)
                    .setContentTitle("SafeFamily")
                    .setContentText(text)
                    .setAutoCancel(true)
                    .build(),
            )
        }
    }

    /** `false` nếu token bị thu hồi (401): máy mẹ đã hủy ghép → dọn sạch. */
    private fun pullCommands(context: Context): Boolean {
        val r = request(context, "GET", "/api/devices/me/commands", null)
        if (r.code == 401) {
            clear(context)
            return false
        }
        if (r.code != 200) return true
        val list = JSONArray(r.body)
        for (i in 0 until list.length()) {
            val c = list.getJSONObject(i)
            // Chỉ ack lệnh đã thực hiện được; lỗi thì để lượt sau thử lại.
            if (runCatching { apply(context, c.getString("type"), c.optString("payloadJson", "{}")) }.getOrDefault(false)) {
                request(context, "POST", "/api/devices/me/commands/${c.getInt("id")}/ack", null)
            }
        }
        return true
    }

    /** Thi hành lệnh của mẹ bằng đúng các hàm chặn sẵn có. `false` = lệnh lạ/sai. */
    internal fun apply(context: Context, type: String, payloadJson: String): Boolean {
        val minutes = runCatching { JSONObject(payloadJson).optInt("minutes", 0) }.getOrDefault(0)
        when (type) {
            "pause" -> TimeLimits.startPause(context, minutes)
            // Khóa từ xa = tạm dừng thiết bị (chỉ còn Điện thoại/SMS), tái dùng lớp phủ có sẵn.
            "lock" -> TimeLimits.startPause(context, if (minutes > 0) minutes else DEFAULT_LOCK_MINUTES)
            "unpause", "unlock" -> TimeLimits.stopPause(context)
            "study_start" -> TimeLimits.startStudySession(context, if (minutes > 0) minutes else 30)
            "study_stop" -> TimeLimits.stopStudySession(context)
            "disable_limit_today" -> TimeLimits.setTotalLimitDisabledToday(context, true)
            "enable_limit_today" -> TimeLimits.setTotalLimitDisabledToday(context, false)
            "extra_time_grant" -> {
                // Mẹ duyệt xin thêm giờ (API-06). Số phút sai thì không ack.
                if (minutes !in 1..MAX_EXTRA_MINUTES) return false
                TimeLimits.addBonus(context, minutes)
            }
            "study_approve" -> StudyBlock.approve(context)
            "study_reject" -> StudyBlock.reject(context)
            "app_unlock_temp", "app_relock", "app_block", "app_allow" -> return applyAppCommand(context, type, payloadJson)
            else -> return false
        }
        return true
    }

    /**
     * Lệnh theo app. `false` (không ack) khi payload sai hoặc muốn chặn app miễn trừ.
     * Làm việc trên [GuardPrefs.remoteBlocked] = danh sách mẹ đang khóa, để lần đồng bộ luật
     * kế tiếp ([applyRemoteBlocked]) tính đúng phần cần bỏ/giữ.
     *
     * Lệnh ghi đè danh sách đó chỉ tới khi mẹ đẩy luật phiên bản mới; luật mới là nguồn sự thật.
     * Riêng mở tạm thì luật mới không cắt ngang (xem [applyRemoteBlocked]).
     * TODO(verify): chạy trên máy thật; hạn mở tạm do [TempRelocks.sweep] chặn lại khi cửa sổ đổi,
     * đồng bộ, hoặc khởi động máy, không có báo thức chính xác.
     */
    private fun applyAppCommand(context: Context, type: String, payloadJson: String): Boolean {
        val json = runCatching { JSONObject(payloadJson) }.getOrNull() ?: return false
        val pkg = json.optString("package", "")
        if (!Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$").matches(pkg)) return false
        val exempt = pkg in TimeLimits.exemptPackages(context)
        val manager = BlockingServiceManager(context.applicationContext)
        val remote = GuardPrefs.remoteBlocked(context)
        when (type) {
            "app_unlock_temp" -> {
                val minutes = json.optInt("minutes", 0)
                if (minutes !in 1..MAX_UNLOCK_MINUTES) return false
                // Chỉ mở app đang bị chặn: ghi hạn cho app chưa chặn thì tới hạn lại bị chặn nhầm.
                val blocked = BlockerPreferences(context.applicationContext).getBlockedApps()
                if (exempt || (pkg !in blocked && pkg !in TempRelocks.pending(context))) return true // đang mở tạm: gia hạn
                // Ghi hạn TRƯỚC khi bỏ chặn: lỗi giữa chừng thì app vẫn bị chặn.
                TempRelocks.remember(context, pkg, System.currentTimeMillis() + minutes * 60_000L)
                manager.stopBlockingApps(listOf(pkg))
            }
            "app_relock" -> {
                val wasUnlocked = pkg in TempRelocks.pending(context)
                TempRelocks.forget(context, pkg)
                if (!exempt && (wasUnlocked || pkg in remote)) manager.startBlocking(listOf(pkg))
            }
            "app_block" -> {
                if (exempt) return false
                TempRelocks.forget(context, pkg)
                manager.startBlocking(listOf(pkg))
                GuardPrefs.setRemoteBlocked(context, remote + pkg)
            }
            "app_allow" -> {
                TempRelocks.forget(context, pkg)
                if (pkg in remote) {
                    manager.stopBlockingApps(listOf(pkg))
                    GuardPrefs.setRemoteBlocked(context, remote - pkg)
                }
            }
        }
        return true
    }

    /**
     * Gói luật = `{"schemaVersion":1,"timeLimit":{...},"appLock":{"blocked":[pkg],"schedules":[...]}}`.
     * Kiểm tra HẾT trước khi ghi bất cứ thứ gì: gói hỏng, sai kiểu hoặc schema
     * mới hơn bản app này hiểu thì giữ nguyên luật cũ (và không nhớ phiên bản,
     * để lượt sau thử lại). Gói cũ chưa có `schemaVersion`/`appLock` vẫn nhận.
     */
    private fun pullPolicy(context: Context) {
        val r = request(context, "GET", "/api/devices/me/policy", null)
        if (r.code != 200) return
        val p = prefs(context)
        val parsed = runCatching { parsePolicy(r.body) }.getOrNull() ?: return
        if (parsed.version == 0 || parsed.version == p.getInt(KEY_POLICY_VERSION, 0)) return
        val applied = runCatching {
            parsed.timeLimit?.let { TimeLimits.setConfig(context, it.toString()) }
            parsed.blocked?.let { applyRemoteBlocked(context, it) }
        }.isSuccess
        if (applied) p.edit().putInt(KEY_POLICY_VERSION, parsed.version).apply()
    }

    private class ParsedPolicy(val version: Int, val timeLimit: JSONObject?, val blocked: Set<String>?)

    /** `null` ở timeLimit/blocked = gói không nhắc tới phần đó (giữ nguyên). Ném lỗi nếu gói không hợp lệ. */
    private fun parsePolicy(body: String): ParsedPolicy {
        val dto = JSONObject(body)
        val version = dto.getInt("version")
        if (version == 0) return ParsedPolicy(0, null, null)
        val policy = JSONObject(dto.getString("json"))
        val schema = policy.optInt("schemaVersion", 1)
        require(schema in 1..SUPPORTED_SCHEMA) { "schema $schema chưa hỗ trợ" }

        val timeLimit = if (policy.has("timeLimit")) {
            policy.getJSONObject("timeLimit") // sai kiểu → ném lỗi
        } else null

        val blocked = if (policy.has("appLock")) {
            val array = policy.getJSONObject("appLock").getJSONArray("blocked")
            val out = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                val pkg = array.get(i)
                require(pkg is String && pkg.isNotBlank()) { "tên gói không hợp lệ" }
                out.add(pkg)
            }
            out
        } else null
        return ParsedPolicy(version, timeLimit, blocked)
    }

    /**
     * Khóa đúng danh sách mẹ gửi. Bỏ khóa chỉ những app mẹ từng khóa mà nay không còn;
     * không bao giờ khóa app hệ thống/Điện thoại/launcher/SafeFamily.
     */
    private fun applyRemoteBlocked(context: Context, blocked: Set<String>) {
        val wanted = blocked - TimeLimits.exemptPackages(context)
        val previous = GuardPrefs.remoteBlocked(context)
        val manager = BlockingServiceManager(context.applicationContext)
        val release = (previous - wanted).toList()
        // App mẹ bỏ khỏi danh sách thì hạn "chặn lại" cũ phải bỏ theo, nếu không tới hạn lại bị chặn nhầm.
        release.forEach { TempRelocks.forget(context, it) }
        if (release.isNotEmpty()) manager.stopBlockingApps(release)
        // Đang mở tạm thì giữ nguyên tới hạn, luật mới không cắt ngang.
        val unlocked = TempRelocks.pending(context)
        val toBlock = (wanted - unlocked).toList()
        if (toBlock.isNotEmpty()) manager.startBlocking(toBlock)
        GuardPrefs.setRemoteBlocked(context, wanted)
    }

    /**
     * Báo mẹ trạng thái máy (API-09, `PUT /api/devices/me/status`). Chỉ các trường: pin, phiên bản luật đã áp,
     * tạm dừng, giờ học, quyền còn thiếu, phiên bản app, app đang mở tạm (tên gói + hạn). KHÔNG gửi app đang
     * dùng hay nội dung. Mọi lỗi (mạng, 4xx/5xx, đọc trạng thái) đều bỏ qua, lượt sau gửi lại.
     */
    private fun pushStatus(context: Context) {
        runCatching {
            val temp = JSONArray()
            for ((pkg, until) in TempRelocks.pendingUntil(context)) {
                if (until > System.currentTimeMillis()) temp.put(JSONObject().put("package", pkg).put("until", iso(until)))
            }
            val body = JSONObject()
                .put("policyVersion", prefs(context).getInt(KEY_POLICY_VERSION, 0))
                .put("isPaused", TimeLimits.pauseMinutesLeft(context) > 0)
                .put("studyActive", TimeLimits.studyActive(context))
                .put("permissionsMissing", JSONArray(PermissionStatus.missing(context)))
                .put("tempUnlocked", temp)
            batteryPercent(context)?.let { body.put("batteryPercent", it) }
            appVersion(context)?.let { body.put("appVersion", it) }
            request(context, "PUT", "/api/devices/me/status", body)
        }
    }

    /** 0–100, hoặc `null` nếu máy không cho đọc. */
    private fun batteryPercent(context: Context): Int? {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
        val direct = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
        if (direct != null && direct in 1..100) return direct
        // Một số máy trả 0 / Int.MIN_VALUE: đọc từ intent pin (sticky, không cần quyền).
        val intent = context.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else null
    }

    /** `versionName` đã lọc theo đúng ký tự server nhận (≤32), sai dạng thì không gửi. */
    private fun appVersion(context: Context): String? = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }.getOrNull()?.takeIf { it.length in 1..32 && Regex("^[0-9A-Za-z.+_-]+$").matches(it) }

    private fun pullGeofences(context: Context) {
        val r = request(context, "GET", "/api/devices/me/geofences", null)
        if (r.code != 200) return
        val dto = JSONObject(r.body)
        val version = dto.getInt("version")
        val p = prefs(context)
        if (version == p.getInt(KEY_GEOFENCE_VERSION, -1)) return
        if (!hasLocationPermission(context)) return // chưa có quyền: lượt sau đăng ký
        Geofences.replaceAll(context, dto.getJSONArray("geofences"))
        p.edit().putInt(KEY_GEOFENCE_VERSION, version).apply()
    }

    private fun flush(context: Context, key: String, path: String, field: String) {
        val p = prefs(context)
        val pending = p.getString(key, "[]") ?: "[]"
        if (pending == "[]") return
        val r = request(context, "POST", "/api/devices/me/$path", JSONObject().put(field, JSONArray(pending)))
        if (r.code in 200..299) {
            // Chỉ bỏ phần đã gửi; mục thêm trong lúc gửi vẫn giữ.
            synchronized(this) {
                val sent = JSONArray(pending).length()
                val now = JSONArray(p.getString(key, "[]"))
                val rest = JSONArray().also { out -> for (i in sent until now.length()) out.put(now.get(i)) }
                p.edit().putString(key, rest.toString()).apply()
            }
        } else if (r.code == 400) {
            p.edit().putString(key, "[]").apply() // dữ liệu hỏng: bỏ, tránh kẹt hàng chờ
        }
    }

    // ---- HTTP --------------------------------------------------------------

    internal class Reply(val code: Int, val body: String)

    internal fun request(context: Context, method: String, path: String, body: JSONObject?): Reply {
        val p = prefs(context)
        val conn = URL(p.getString(KEY_URL, "") + path).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            conn.setRequestProperty("Authorization", "Bearer ${p.getString(KEY_TOKEN, "")}")
            if (body != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
            } else if (method == "POST") {
                conn.doOutput = true
                conn.setFixedLengthStreamingMode(0)
            }
            val code = conn.responseCode
            val stream = if (code >= 400) conn.errorStream else conn.inputStream
            return Reply(code, stream?.bufferedReader()?.use { it.readText() } ?: "")
        } finally {
            conn.disconnect()
        }
    }
}
