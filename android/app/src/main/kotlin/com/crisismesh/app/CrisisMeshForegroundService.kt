package com.crisismesh.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Phase 5B: Crisis Mesh Background Mesh Foreground Service
 *
 * Keeps the application process in Foreground Service priority so Nearby Connections
 * Bluetooth/P2P cluster discovery, advertising, and automatic Phase 5A store-and-forward
 * pending SOS transmissions remain active when the Flutter UI is minimized/backgrounded.
 */
class CrisisMeshForegroundService : Service() {

    companion object {
        private const val TAG = "CrisisMeshFGService"
        const val CHANNEL_ID = "crisis_mesh_emergency_mesh_channel"
        const val CHANNEL_NAME = "Crisis Mesh Emergency Service"
        const val NOTIFICATION_ID = 9110

        const val ACTION_START = "com.crisismesh.app.ACTION_START_MESH"
        const val ACTION_STOP = "com.crisismesh.app.ACTION_STOP_MESH"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "CrisisMeshForegroundService created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand with action: $action")

        when (action) {
            ACTION_STOP -> {
                stopForegroundService()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                startForegroundWithNotification()
                return START_STICKY
            }
            else -> {
                startForegroundWithNotification()
                return START_STICKY
            }
        }
    }

    private fun startForegroundWithNotification() {
        try {
            val notification = buildForegroundNotification()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // Android 14+ (API 34)
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            isRunning = true
            Log.d(TAG, "CrisisMeshForegroundService running in foreground (type: connectedDevice)")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}", e)
        }
    }

    private fun stopForegroundService() {
        try {
            Log.d(TAG, "Stopping CrisisMeshForegroundService")
            isRunning = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping foreground service: ${e.message}", e)
        }
    }

    private fun buildForegroundNotification(): Notification {
        // Intent to return to Crisis Mesh when tapping notification
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        // Action to stop emergency mesh directly from notification
        val stopIntent = Intent(this, CrisisMeshForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("Crisis Mesh — Emergency Mesh Active")
            .setContentText("Monitoring nearby peers • Ready to relay emergency SOS")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            val stopAction = Notification.Action.Builder(
                null,
                "STOP MESH",
                stopPendingIntent
            ).build()
            builder.addAction(stopAction)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_SERVICE)
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing notification displayed while Crisis Mesh background emergency peer communication is active"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "CrisisMeshForegroundService destroyed")
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
