package com.safefamily.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Có app được cài / gỡ: đưa app lạ vào danh sách chờ duyệt và báo phụ huynh. */
class PackageChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pkg = intent.data?.schemeSpecificPart ?: return
        // Cập nhật app có sẵn cũng gửi ADDED/REMOVED kèm cờ REPLACING.
        val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> if (!replacing) NewApps.scan(context, force = true)
            Intent.ACTION_PACKAGE_REMOVED -> if (!replacing) NewApps.onRemoved(context, pkg)
        }
    }
}
