package com.safefamily.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Trạng thái màn chặn giờ học, lưu bền để kill app / khởi động lại vẫn đúng:
 * `studying → child_claims_done → approved | rejected` (rejected quay lại học).
 *
 * Việc chặn vẫn do [TimeLimits.studyActive] quyết định; ở đây chỉ giữ con đã báo
 * xong chưa và phụ huynh duyệt hay không. Duyệt = kết thúc giờ học đến hết hôm
 * nay (dùng lại "tắt hôm nay"); `approve` chỉ được Dart gọi sau khi xác thực.
 */
object StudyBlock {
    const val STUDYING = "studying"
    const val CHILD_CLAIMS_DONE = "child_claims_done"
    const val APPROVED = "approved"
    const val REJECTED = "rejected"

    private const val FILE = "safefamily_study_block"
    private const val KEY_STATE = "state"
    private const val KEY_STATE_AT = "state_at"
    private const val KEY_NOTIFIED = "start_notified"
    private const val CHANNEL = "study_time"
    private const val NOTIFICATION_ID = 0x57D1
    private const val MAX_CLAIM_AGE_MS = 12 * 60 * 60_000L

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /**
     * Trạng thái hiện tại. Hết giờ học thì về `studying`, để lần giờ học sau
     * không dính cờ "đã báo xong" hay "đã duyệt" của lần trước.
     */
    @Synchronized
    fun state(context: Context): String {
        val p = prefs(context)
        val stored = p.getString(KEY_STATE, STUDYING) ?: STUDYING
        if (stored == STUDYING) return STUDYING
        val age = TimeLimits.trustedNow(context) - p.getLong(KEY_STATE_AT, 0L)
        val stale = !TimeLimits.studyActive(context) || stored == APPROVED || age !in 0..MAX_CLAIM_AGE_MS
        if (!stale) return stored
        put(context, STUDYING)
        return STUDYING
    }

    private fun put(context: Context, state: String) {
        prefs(context).edit()
            .putString(KEY_STATE, state)
            .putLong(KEY_STATE_AT, TimeLimits.trustedNow(context))
            .apply()
    }

    /** Con bấm "Đã học xong". */
    @Synchronized
    fun claimDone(context: Context) {
        if (!TimeLimits.studyActive(context)) return
        if (state(context) == CHILD_CLAIMS_DONE) return
        put(context, CHILD_CLAIMS_DONE)
    }

    /** Phụ huynh đã xác thực và duyệt: mở khóa app đến hết hôm nay. */
    @Synchronized
    fun approve(context: Context): Boolean {
        if (state(context) != CHILD_CLAIMS_DONE) return false
        TimeLimits.setStudyDisabledToday(context, true)
        put(context, APPROVED)
        cancelNotification(context)
        return true
    }

    /** Phụ huynh từ chối: quay lại học. */
    @Synchronized
    fun reject(context: Context): Boolean {
        if (state(context) != CHILD_CLAIMS_DONE) return false
        put(context, REJECTED)
        return true
    }

    // ---- Thông báo bắt đầu giờ học ----------------------------------------

    /**
     * Báo một lần mỗi đợt giờ học (dịch vụ gọi định kỳ và khi bắt đầu phiên).
     * Hết giờ học thì xóa cờ để đợt sau báo lại.
     */
    @Synchronized
    fun syncStartNotification(context: Context) {
        val p = prefs(context)
        val active = TimeLimits.studyActive(context)
        val notified = p.getBoolean(KEY_NOTIFIED, false)
        if (active && !notified) {
            p.edit().putBoolean(KEY_NOTIFIED, true).apply()
            announce(context)
        } else if (!active && notified) {
            p.edit().putBoolean(KEY_NOTIFIED, false).apply()
            cancelNotification(context)
        }
    }

    // Không dựa vào full-screen intent; thiếu quyền POST_NOTIFICATIONS thì notify() bị bỏ qua.
    private fun announce(context: Context) {
        runCatching {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Giờ học", NotificationManager.IMPORTANCE_HIGH),
                )
            }
            val open = PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                Intent(context, MainActivity::class.java)
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
                NOTIFICATION_ID,
                builder
                    .setSmallIcon(context.applicationInfo.icon)
                    .setContentTitle("Đã đến giờ học")
                    .setContentText("Hãy học rồi tiếp tục sử dụng máy nhé.")
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        }
    }

    private fun cancelNotification(context: Context) {
        runCatching {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIFICATION_ID)
        }
    }
}
