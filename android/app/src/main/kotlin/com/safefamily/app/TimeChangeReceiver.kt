package com.safefamily.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Giờ hệ thống vừa bị đổi: [TimeLimits.trustedNow] so với giờ mới và ghi lệch
 * vào nhật ký. Giới hạn ngày không reset vì dùng đồng hồ elapsed.
 */
class TimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        TimeLimits.trustedNow(context)
    }
}
