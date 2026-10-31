package com.safefamily.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Dịch vụ nền của máy con (đã ghép đôi): mỗi 5 phút hỏi API (lệnh, luật, hàng rào)
 * và gửi vị trí. Luôn hiện thông báo thường trực để trẻ biết vị trí đang được chia sẻ.
 * Chưa cấp quyền vị trí thì vẫn hỏi lệnh/luật, chỉ không lấy vị trí.
 */
class FamilyService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var locationCallback: LocationCallback? = null
    private val poll = object : Runnable {
        override fun run() {
            Thread { FamilySync.syncOnce(this@FamilyService) }.start()
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!FamilySync.isConfigured(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground()
        startLocationUpdates()
        handler.removeCallbacks(poll)
        handler.post(poll)
        return START_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Kết nối gia đình", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val sharing = FamilySync.hasLocationPermission(this)
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("SafeFamily đang kết nối với máy mẹ")
            .setContentText(
                if (sharing) "Vị trí máy này đang được chia sẻ với phụ huynh."
                else "Máy mẹ có thể đặt luật cho máy này.",
            )
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = when {
                sharing -> ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                else -> 0
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Suppress("MissingPermission") // đã kiểm tra hasLocationPermission
    private fun startLocationUpdates() {
        if (locationCallback != null || !FamilySync.hasLocationPermission(this)) return
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.locations.forEach {
                    FamilySync.addLocation(
                        this@FamilyService,
                        it.latitude,
                        it.longitude,
                        it.accuracy.toDouble(),
                        it.time,
                    )
                }
            }
        }
        val request = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, LOCATION_MS)
            .setMinUpdateIntervalMillis(LOCATION_MS / 2)
            .build()
        runCatching {
            LocationServices.getFusedLocationProviderClient(this)
                .requestLocationUpdates(request, callback, Looper.getMainLooper())
            locationCallback = callback
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(poll)
        locationCallback?.let {
            runCatching { LocationServices.getFusedLocationProviderClient(this).removeLocationUpdates(it) }
        }
        locationCallback = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "family_sharing"
        private const val NOTIFICATION_ID = 0xFA31
        private const val POLL_MS = 5 * 60_000L
        private const val LOCATION_MS = 5 * 60_000L
    }
}
