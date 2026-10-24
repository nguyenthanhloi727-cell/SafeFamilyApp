package com.safefamily.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Quản trị thiết bị: khi đang bật, SafeFamily không gỡ được cho tới khi tắt
 * quyền này; màn tắt quyền nằm trong Cài đặt nên bị [SettingsGuardService] chặn.
 */
class SafeFamilyAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Tắt quyền này sẽ cho phép gỡ SafeFamily. Chỉ phụ huynh nên làm."
}
