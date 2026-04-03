package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CLIPBOARD_METHOD_CHANNEL = "com.smarttask.smart_task_assistant/clipboard_service"
    private val CLIPBOARD_EVENT_CHANNEL = "com.smarttask.smart_task_assistant/clipboard_monitor"
    private val REMINDER_METHOD_CHANNEL = "com.smarttask.smart_task_assistant/reminder"
    private val REMINDER_EVENT_CHANNEL = "com.smarttask.smart_task_assistant/reminder_events"

    private var clipboardMethodChannel: MethodChannel? = null
    private var clipboardEventChannel: EventChannel? = null
    private var clipboardEventSink: EventChannel.EventSink? = null

    private var reminderMethodChannel: MethodChannel? = null
    private var reminderEventChannel: EventChannel? = null
    private var reminderEventSink: EventChannel.EventSink? = null

    // 剪贴板变化广播接收器
    private val clipboardReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.smarttask.smart_task_assistant.CLIPBOARD_CHANGED") {
                val content = intent.getStringExtra("content")
                if (content != null) {
                    clipboardEventSink?.success(content)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        setupClipboardChannels(flutterEngine)
        setupReminderChannels(flutterEngine)
    }

    // --- Clipboard channels (existing) ---

    private fun setupClipboardChannels(flutterEngine: FlutterEngine) {
        clipboardMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_METHOD_CHANNEL)
        clipboardMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        ClipboardMonitorService.startService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                    }
                }
                "stopService" -> {
                    try {
                        ClipboardMonitorService.stopService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop service: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        clipboardEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_EVENT_CHANNEL)
        clipboardEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                clipboardEventSink = events
                val filter = IntentFilter("com.smarttask.smart_task_assistant.CLIPBOARD_CHANGED")
                registerReceiver(clipboardReceiver, filter)
            }

            override fun onCancel(arguments: Any?) {
                clipboardEventSink = null
                try { unregisterReceiver(clipboardReceiver) } catch (_: Exception) {}
            }
        })
    }

    // --- Reminder channels (new) ---

    private fun setupReminderChannels(flutterEngine: FlutterEngine) {
        // MethodChannel for Flutter → Kotlin calls
        reminderMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDER_METHOD_CHANNEL)
        reminderMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        ReminderForegroundService.start(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start reminder service: ${e.message}", null)
                    }
                }
                "stopService" -> {
                    try {
                        ReminderForegroundService.stop(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop reminder service: ${e.message}", null)
                    }
                }
                "notifyAppForeground" -> {
                    try {
                        val intent = Intent(this, ReminderForegroundService::class.java).apply {
                            action = ReminderForegroundService.ACTION_APP_FOREGROUND
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to notify foreground: ${e.message}", null)
                    }
                }
                "notifyAppBackground" -> {
                    try {
                        val intent = Intent(this, ReminderForegroundService::class.java).apply {
                            action = ReminderForegroundService.ACTION_APP_BACKGROUND
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to notify background: ${e.message}", null)
                    }
                }
                "notifyDataChanged" -> {
                    try {
                        val type = call.argument<String>("type") ?: "all"
                        val id = call.argument<String>("id")
                        val intent = Intent(this, ReminderForegroundService::class.java).apply {
                            action = ReminderForegroundService.ACTION_REFRESH_DATA
                            putExtra("type", type)
                            if (id != null) putExtra("id", id)
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to notify data changed: ${e.message}", null)
                    }
                }
                "clearReminderState" -> {
                    try {
                        val id = call.argument<String>("id") ?: run {
                            result.error("INVALID_ARG", "id is required", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, ReminderForegroundService::class.java).apply {
                            action = ReminderForegroundService.ACTION_CLEAR_STATE
                            putExtra("id", id)
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to clear state: ${e.message}", null)
                    }
                }
                "requestFullScreenPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = getSystemService(NotificationManager::class.java)
                            if (nm.canUseFullScreenIntent()) {
                                result.success(true)
                            } else {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(false)
                            }
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("PERMISSION_ERROR", "Failed to request permission: ${e.message}", null)
                    }
                }
                "isServiceRunning" -> {
                    result.success(ReminderForegroundService.isRunning)
                }
                "hasFullScreenPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = getSystemService(NotificationManager::class.java)
                            result.success(nm.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(true)
                    }
                }
                "isBatteryOptimized" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
                        result.success(!isIgnoring)
                    } catch (e: Exception) {
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimization" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (pm.isIgnoringBatteryOptimizations(packageName)) {
                            result.success(true)
                        } else {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        // Fallback: open battery optimization settings
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                        } catch (_: Exception) {}
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel for Kotlin → Flutter events
        reminderEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDER_EVENT_CHANNEL)
        reminderEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                reminderEventSink = events

                // Wire up the bridge to send events through this sink
                val bridge = ReminderBridge.getInstance()
                bridge.eventSink = { eventJson ->
                    runOnUiThread {
                        try {
                            events?.success(eventJson)
                        } catch (e: Exception) {
                            Log.w("MainActivity", "Failed to send reminder event", e)
                        }
                    }
                }

                // Drain buffered events
                val buffered = bridge.drainBuffer()
                for (event in buffered) {
                    try {
                        events?.success(event)
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Failed to replay buffered event", e)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                reminderEventSink = null
                ReminderBridge.getInstance().eventSink = null
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        // Cleanup clipboard channels
        clipboardEventChannel?.setStreamHandler(null)
        try { unregisterReceiver(clipboardReceiver) } catch (_: Exception) {}

        // Cleanup reminder channels
        reminderEventChannel?.setStreamHandler(null)
        ReminderBridge.getInstance().eventSink = null
    }
}
