package com.safefamily.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Giờ hệ thống vừa bị đổi: [TimeLimits.trustedNow] so với giờ mới và ghi lệch
 * vào nhật ký. Giới hạn ngày không reset vì dùng đồng hồ elapsed.
 * Lệch mới thì báo mẹ ([TamperAlerts], API-10): chỉ số phút lệch, không gì khác.
 */
class TimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        TimeLimits.trustedNow(context)
        if (!runCatching { TamperAlerts.checkTimeJumps(context) }.getOrDefault(false)) return
        // Gửi ngay ở luồng nền; goAsync giữ tiến trình sống tới khi gửi xong. Không gửi được thì lượt đồng bộ sau gửi bù.
        val pending = goAsync()
        Thread {
            try {
                TamperAlerts.flush(context.applicationContext)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
