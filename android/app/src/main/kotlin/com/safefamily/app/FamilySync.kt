package com.safefamily.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
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
    private const val MAX_QUEUE = 500
    private const val TIMEOUT_MS = 15_000
    private const val DEFAULT_LOCK_MINUTES = 60

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

    /** Một lượt: lệnh → luật → hàng rào → gửi vị trí → gửi sự kiện. Gọi ở luồng nền. */
    @Synchronized
    fun syncOnce(context: Context): Boolean {
        if (!isConfigured(context)) return false
        return try {
            if (!pullCommands(context)) return false
            pullPolicy(context)
            pullGeofences(context)
            flush(context, KEY_LOCATIONS, "locations", "points")
            flush(context, KEY_EVENTS, "geofence-events", "events")
            true
        } catch (e: java.io.IOException) {
            false // offline: giữ nguyên luật + hàng chờ, lượt sau thử lại
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
            "study_approve" -> StudyBlock.approve(context)
            "study_reject" -> StudyBlock.reject(context)
            else -> return false
        }
        return true
    }

    /** Gói luật = `{"timeLimit": <cấu hình giới hạn thời gian>}`. Hỏng thì giữ luật cũ. */
    private fun pullPolicy(context: Context) {
        val r = request(context, "GET", "/api/devices/me/policy", null)
        if (r.code != 200) return
        val dto = JSONObject(r.body)
        val version = dto.getInt("version")
        val p = prefs(context)
        if (version == 0 || version == p.getInt(KEY_POLICY_VERSION, 0)) return
        val policy = JSONObject(dto.getString("json"))
        val timeLimit = policy.optJSONObject("timeLimit")
        if (timeLimit != null) TimeLimits.setConfig(context, timeLimit.toString())
        p.edit().putInt(KEY_POLICY_VERSION, version).apply()
    }

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

    private class Reply(val code: Int, val body: String)

    private fun request(context: Context, method: String, path: String, body: JSONObject?): Reply {
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
