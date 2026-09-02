package com.crisismesh.app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Phase 5B & 5B.2: MainActivity with MethodChannel bridge for controlling the native Foreground Service
 * and reading device battery percentage for adaptive duty-cycling.
 */
class MainActivity : FlutterActivity() {
    private val BACKGROUND_CHANNEL = "com.crisismesh.app/background_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this, CrisisMeshForegroundService::class.java).apply {
                            action = CrisisMeshForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_FAILED", "Failed to start CrisisMesh foreground service: ${e.message}", null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this, CrisisMeshForegroundService::class.java).apply {
                            action = CrisisMeshForegroundService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_STOP_FAILED", "Failed to stop CrisisMesh foreground service: ${e.message}", null)
                    }
                }
                "isForegroundServiceRunning" -> {
                    result.success(CrisisMeshForegroundService.isRunning)
                }
                "getBatteryLevel" -> {
                    try {
                        val batteryLevel: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                            batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        } else {
                            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                            val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                            val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                            if (level >= 0 && scale > 0) {
                                (level * 100 / scale.toFloat()).toInt()
                            } else {
                                -1
                            }
                        }
                        result.success(batteryLevel)
                    } catch (e: Exception) {
                        result.success(-1)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
