package com.safefamily.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Sau khi máy khởi động: chặn lại ngay app đã quá hạn mở tạm, và đối chiếu app mới cài. */
class GuardBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        TempRelocks.sweep(context)
        runCatching { NewApps.scan(context, force = true) }
        // Máy con đã ghép đôi: bật lại đồng bộ + vị trí; hàng rào do hệ thống xóa khi khởi động nên đăng ký lại.
        FamilySync.ensureService(context)
        FamilySync.onBoot(context)
    }
}
