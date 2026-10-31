package com.safefamily.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/** Hệ thống báo máy con vừa vào/ra hàng rào: xếp vào hàng chờ rồi thử gửi ngay. */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val type = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "enter"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"
            else -> return
        }
        val now = System.currentTimeMillis()
        event.triggeringGeofences?.forEach { g ->
            g.requestId.toIntOrNull()?.let { FamilySync.addGeofenceEvent(context, it, type, now) }
        }
        val pendingResult = goAsync()
        Thread {
            try {
                FamilySync.syncOnce(context)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
