package com.safefamily.app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray

/**
 * Đăng ký hàng rào địa lý của máy mẹ với GeofencingClient (Play Services). Hàng
 * rào do hệ thống theo dõi nên vẫn báo khi offline; sự kiện vào hàng chờ của
 * [FamilySync] rồi gửi bù khi có mạng. Tối đa 100 vùng/app (server cũng giới hạn).
 * TODO(verify): ROM hãng (Xiaomi...) có thể giết tiến trình nền làm báo trễ;
 * máy không có Google Play Services thì không đăng ký được.
 */
object Geofences {
    private const val MIN_RADIUS_M = 100f

    private fun pending(context: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(
            context.applicationContext,
            0,
            Intent(context.applicationContext, GeofenceReceiver::class.java),
            flags,
        )
    }

    /** Thay toàn bộ vùng đang đăng ký bằng [fences] (mảng `{id,name,lat,lng,radiusM}`). */
    @SuppressLint("MissingPermission") // FamilySync kiểm tra hasLocationPermission trước khi gọi
    fun replaceAll(context: Context, fences: JSONArray) {
        val client = LocationServices.getGeofencingClient(context.applicationContext)
        client.removeGeofences(pending(context))
        if (fences.length() == 0) return
        val list = (0 until fences.length()).map { i ->
            val f = fences.getJSONObject(i)
            Geofence.Builder()
                .setRequestId(f.getInt("id").toString())
                .setCircularRegion(
                    f.getDouble("lat"),
                    f.getDouble("lng"),
                    maxOf(MIN_RADIUS_M, f.getDouble("radiusM").toFloat()),
                )
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
                .build()
        }
        client.addGeofences(
            GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(list)
                .build(),
            pending(context),
        )
    }

    fun removeAll(context: Context) {
        LocationServices.getGeofencingClient(context.applicationContext).removeGeofences(pending(context))
    }
}
