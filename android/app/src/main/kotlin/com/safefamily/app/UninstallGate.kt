package com.safefamily.app

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Đường DUY NHẤT để gỡ SafeFamily. Dart chỉ gọi [begin] sau khi phụ huynh đã
 * qua PIN rồi sinh trắc. Chống gỡ (dịch vụ Trợ năng + Quản trị thiết bị) được
 * thả trong [WINDOW_SECONDS] giây; hủy hoặc hết hạn thì [finish] khóa lại.
 */
object UninstallGate {
    const val WINDOW_SECONDS = 120L

    /** Mở cửa, gỡ Quản trị thiết bị rồi mở màn gỡ của hệ thống. `false` nếu máy không mở được. */
    fun begin(activity: Activity): Boolean {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(activity, SafeFamilyAdminReceiver::class.java)
        val wasAdmin = dpm.isAdminActive(admin)
        GuardPrefs.beginUninstallWindow(activity, WINDOW_SECONDS, wasAdmin)
        if (wasAdmin) runCatching { dpm.removeActiveAdmin(admin) }
        return try {
            activity.startActivity(
                Intent(Intent.ACTION_DELETE, Uri.parse("package:${activity.packageName}")),
            )
            true
        } catch (e: ActivityNotFoundException) {
            finish(activity)
            false
        }
    }

    /**
     * Đóng cửa gỡ app và, nếu đã gỡ Quản trị thiết bị, mở lại màn bật nó.
     * Android không cho bật Quản trị thiết bị âm thầm nên phải qua hộp thoại xác nhận.
     * TODO(verify): hãng nào đó có thể chặn mở hộp thoại này từ nền; khi đó cờ
     * còn lại và Quyền ứng dụng vẫn hiện "Quản trị thiết bị: chưa bật".
     */
    fun finish(context: Context) {
        val restore = GuardPrefs.endUninstallWindow(context)
        if (!restore) return
        val admin = ComponentName(context, SafeFamilyAdminReceiver::class.java)
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (dpm.isAdminActive(admin)) {
            GuardPrefs.clearAdminRestore(context)
            return
        }
        GuardPrefs.allowSettings(context, 180L)
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
            .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Bật để con không gỡ được SafeFamily.")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (runCatching { context.startActivity(intent) }.isSuccess) {
            GuardPrefs.clearAdminRestore(context)
        }
    }
}
