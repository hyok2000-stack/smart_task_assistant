package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.app.AlarmManager
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
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

    private fun dispatchReminderService(intent: Intent) {
        try {
            // 注意：startForegroundService 不要求 POST_NOTIFICATIONS 权限——
            // 未授权时前台服务照常运行，仅通知不显示。此前的"未授权则跳过启动"
            // 门禁会让整条原生提醒链在 Android 13+ 上静默瘫痪（后台提醒完全失效）。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "Failed to start foreground service (ignored)", e)
        }
    }

    private fun notifyReminderAppState(foreground: Boolean) {
        try {
            val intent = Intent(this, ReminderForegroundService::class.java).apply {
                action = if (foreground) {
                    ReminderForegroundService.ACTION_APP_FOREGROUND
                } else {
                    ReminderForegroundService.ACTION_APP_BACKGROUND
                }
            }
            dispatchReminderService(intent)
        } catch (e: Exception) {
            Log.w("MainActivity", "Failed to notify reminder app state: foreground=$foreground", e)
        }
    }

    override fun onResume() {
        super.onResume()
        notifyReminderAppState(true)
        // APP 回前台刷新桌面小组件数据
        TodayWidgetProvider.updateAll(this)
    }

    override fun onPause() {
        notifyReminderAppState(false)
        super.onPause()
    }

    override fun onStop() {
        notifyReminderAppState(false)
        super.onStop()
    }

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
        setupFileChannels(flutterEngine)
        setupSpeechChannels(flutterEngine)
    }

    // --- Vosk 离线语音识别通道 ---

    private var voskHandler: VoskSpeechHandler? = null

    private fun setupSpeechChannels(flutterEngine: FlutterEngine) {
        val handler = VoskSpeechHandler(this)
        voskHandler = handler

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.smarttask.smart_task_assistant/speech"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> handler.init(result)
                "start" -> {
                    handler.start()
                    result.success(true)
                }
                "stop" -> {
                    handler.stop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.smarttask.smart_task_assistant/speech_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                handler.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                handler.setEventSink(null)
            }
        })
    }

    // --- File open channel (open content URI via system Intent) ---

    private fun setupFileChannels(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.smarttask.smart_task_assistant/file")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "persistUri" -> {
                        // 持久化 content URI 读取权限，确保 App 重启后仍能访问附件
                        val uriStr = call.argument<String>("uri")
                        if (uriStr == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = Uri.parse(uriStr)
                            contentResolver.takePersistableUriPermission(
                                uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            Log.w("MainActivity", "Failed to persist URI: $uriStr", e)
                            result.success(false) // 非 content URI 则忽略
                        }
                    }
                    "openFile" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("INVALID_ARG", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val parsedUri = Uri.parse(uri)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                data = parsedUri
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.w("MainActivity", "Failed to open file: $uri", e)
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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
                "isGmsAvailable" -> {
                    // 检测 Google Play Services 是否可用（华为设备通常不可用）
                    try {
                        val isAvailable = isGooglePlayServicesAvailable(this)
                        result.success(isAvailable)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
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
                        dispatchReminderService(intent)
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
                        dispatchReminderService(intent)
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
                        dispatchReminderService(intent)
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
                        dispatchReminderService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to clear state: ${e.message}", null)
                    }
                }
                "clearContinualState" -> {
                    try {
                        val id = call.argument<String>("id") ?: run {
                            result.error("INVALID_ARG", "id is required", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, ReminderForegroundService::class.java).apply {
                            action = ReminderForegroundService.ACTION_CLEAR_CONTINUAL
                            putExtra("id", id)
                        }
                        dispatchReminderService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to clear continual state: ${e.message}", null)
                    }
                }
                "snoozeReminder" -> {
                    try {
                        val id = call.argument<String>("id") ?: run {
                            result.error("INVALID_ARG", "id is required", null)
                            return@setMethodCallHandler
                        }
                        val minutes = call.argument<Int>("minutes") ?: 10
                        val snoozeUntil = call.argument<Number>("snoozeUntil")?.toLong()
                        val intent = Intent(this, ReminderForegroundService::class.java).apply {
                            action = ReminderForegroundService.ACTION_SNOOZE
                            putExtra("id", id)
                            putExtra("minutes", minutes)
                            if (snoozeUntil != null) putExtra("snoozeUntil", snoozeUntil)
                        }
                        dispatchReminderService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to snooze reminder: ${e.message}", null)
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
                "isScreenOn" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isInteractive)
                    } catch (e: Exception) {
                        result.success(true)
                    }
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
                "areNotificationsEnabled" -> {
                    try {
                        result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openNotificationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", "Failed to open notification settings: ${e.message}", null)
                    }
                }
                "canScheduleExactAlarms" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val alarmManager = getSystemService(AlarmManager::class.java)
                            result.success(alarmManager.canScheduleExactAlarms())
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openExactAlarmSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", "Failed to open exact alarm settings: ${e.message}", null)
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

    /**
     * 检测 Google Play Services 是否可用。
     * 华为设备（HarmonyOS/EMUI）通常没有 GMS。
     */
    private fun isGooglePlayServicesAvailable(context: Context): Boolean {
        return try {
            val pm = context.packageManager
            // 检查 Google Play Services 包是否存在
            pm.getPackageInfo("com.google.android.gms", 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        notifyReminderAppState(false)
        super.onDestroy()
        // Cleanup clipboard channels
        clipboardEventChannel?.setStreamHandler(null)
        try { unregisterReceiver(clipboardReceiver) } catch (_: Exception) {}

        // Cleanup reminder channels
        reminderEventChannel?.setStreamHandler(null)
        ReminderBridge.getInstance().eventSink = null
    }
}
