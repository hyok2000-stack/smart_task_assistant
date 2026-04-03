package com.smarttask.smart_task_assistant

import android.app.*
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 提醒前台服务：使用 AlarmManager 在 Doze 模式下也能定时唤醒检查任务/习惯
 */
class ReminderForegroundService : Service() {
    companion object {
        private const val TAG = "ReminderForegroundService"
        private const val CHANNEL_ID = "reminder_service_channel"
        private const val NOTIFICATION_ID = 2001
        private const val CHECK_INTERVAL = 30_000L // 30 seconds

        // Intent actions
        const val ACTION_STOP = "com.smarttask.smart_task_assistant.ACTION_STOP_REMINDER"
        const val ACTION_APP_FOREGROUND = "com.smarttask.smart_task_assistant.ACTION_APP_FOREGROUND"
        const val ACTION_APP_BACKGROUND = "com.smarttask.smart_task_assistant.ACTION_APP_BACKGROUND"
        const val ACTION_CLEAR_STATE = "com.smarttask.smart_task_assistant.ACTION_CLEAR_STATE"
        const val ACTION_REFRESH_DATA = "com.smarttask.smart_task_assistant.ACTION_REFRESH_DATA"
        const val ACTION_CHECK = "com.smarttask.smart_task_assistant.ACTION_CHECK"

        private const val CHECK_REQUEST_CODE = 1001

        @Volatile
        var isRunning = false
            private set

        @Volatile
        var isReminderShowing = false

        fun start(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            context.stopService(intent)
        }
    }

    private var checker: ReminderChecker? = null
    private var audioHelper: ReminderAudioHelper? = null
    private var ttsHelper: ReminderTtsHelper? = null
    private var handlerThread: HandlerThread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    @Volatile
    private var isAppForeground = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "ReminderForegroundService created")
        isRunning = true

        checker = ReminderChecker(this)
        audioHelper = ReminderAudioHelper(this)
        ttsHelper = ReminderTtsHelper(this)

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        // HandlerThread for delayed TTS playback in triggerReminder
        handlerThread = HandlerThread("ReminderCheckThread").apply { start() }

        // Acquire partial WakeLock
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ReminderService::Check")
        wakeLock?.setReferenceCounted(false)

        // Schedule the first check via AlarmManager (works in Doze mode)
        scheduleNextCheck()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")

        when (intent?.action) {
            ACTION_STOP -> {
                userRequestedStop = true
                cancelScheduledCheck()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_CHECK -> {
                // AlarmManager woke us up — run check and schedule next
                onHandleCheck()
                scheduleNextCheck()
            }
            ACTION_APP_FOREGROUND -> {
                isAppForeground = true
                Log.d(TAG, "App is foreground, suppressing FullScreenActivity")
            }
            ACTION_APP_BACKGROUND -> {
                isAppForeground = false
                Log.d(TAG, "App is background, enabling FullScreenActivity")
            }
            ACTION_CLEAR_STATE -> {
                val id = intent.getStringExtra("id")
                if (id != null) {
                    checker?.clearTaskState(id)
                }
            }
            ACTION_REFRESH_DATA -> {
                val type = intent.getStringExtra("type") ?: "all"
                val id = intent.getStringExtra("id")
                checker?.refreshData(type, id)
            }
            else -> {
                // Initial start or restart — schedule first check
                scheduleNextCheck()
            }
        }

        return START_STICKY
    }

    // ==================== AlarmManager scheduling ====================

    /**
     * 使用 AlarmManager.setExactAndAllowWhileIdle 安排下一次检查。
     * 即使在 Doze 模式下也能唤醒 CPU。
     */
    private fun scheduleNextCheck() {
        val intent = Intent(this, ReminderForegroundService::class.java).apply {
            action = ACTION_CHECK
        }
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this, CHECK_REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                this, CHECK_REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = SystemClock.elapsedRealtime() + CHECK_INTERVAL

        try {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent
            )
            Log.d(TAG, "Next check scheduled in ${CHECK_INTERVAL}ms (exact+idle)")
        } catch (e: Exception) {
            Log.e(TAG, "setExactAndAllowWhileIdle failed, falling back", e)
            try {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            } catch (e2: Exception) {
                Log.e(TAG, "setAndAllowWhileIdle also failed", e2)
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            }
        }
    }

    /**
     * 取消已安排的检查
     */
    private fun cancelScheduledCheck() {
        val intent = Intent(this, ReminderForegroundService::class.java).apply {
            action = ACTION_CHECK
        }
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this, CHECK_REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                this, CHECK_REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Scheduled check cancelled")
    }

    // ==================== Check logic ====================

    private fun onHandleCheck() {
        val needsVoiceHold = try {
            wakeLock?.acquire(15_000L) // max 15s safety net
            val items = checker?.checkAll() ?: emptyList()

            for (item in items) {
                Log.d(TAG, "Triggering reminder: type=${item.type} id=${item.id} title=${item.title}")
                triggerReminder(item)
            }

            // Check if any item needs voice playback (1.5s internal delay + TTS init + playback)
            items.any {
                it.voiceEnabled && (!it.voiceText.isNullOrBlank() || !it.customVoicePath.isNullOrBlank() || !it.title.isNullOrBlank())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onHandleCheck", e)
            false
        }

        // Delay WakeLock release to cover 1.5s sleep + TTS initialization + playback
        if (needsVoiceHold) {
            handlerThread?.looper?.let { looper ->
                Handler(looper).postDelayed({
                    try { wakeLock?.release() } catch (_: Exception) {}
                    Log.d(TAG, "WakeLock released (voice hold)")
                }, 8_000L)
            }
        } else {
            try { wakeLock?.release() } catch (_: Exception) {}
        }
    }

    private fun triggerReminder(item: ReminderChecker.ReminderItem) {
        // Play sound + vibration
        audioHelper?.playSequence(item.soundEnabled, item.vibrationEnabled)

        // Play voice with delay (TTS or custom voice file)
        // For tasks: voiceText is null, but title is always available
        // For habits: voiceText or title is available
        val hasVoiceContent = item.voiceEnabled &&
            (!item.voiceText.isNullOrBlank() || !item.customVoicePath.isNullOrBlank() || !item.title.isNullOrBlank())
        Log.d(TAG, "Voice check for '${item.title}': voiceEnabled=${item.voiceEnabled}, hasContent=$hasVoiceContent")
        if (hasVoiceContent) {
            val speakText = when {
                !item.voiceText.isNullOrBlank() -> item.voiceText
                item.type == "task" -> {
                    val prefix = when (item.priority) {
                        2 -> "紧急任务提醒，"
                        0 -> "温和提醒，"
                        else -> "任务提醒，"
                    }
                    "$prefix${item.title}"
                }
                else -> item.title
            }
            Log.d(TAG, "Requesting voice for '${item.title}': text='$speakText'")
            ttsHelper?.speak(
                text = speakText ?: "",
                voiceType = item.voiceType,
                voiceStyle = item.voiceStyle,
                speed = item.voiceSpeed,
                customVoicePath = item.customVoicePath
            )
        }

        // Send event to Flutter
        val eventJson = buildEventJson(item.id, item.type, "shown")
        ReminderBridge.getInstance().sendEvent(eventJson)

        // Show FullScreenActivity if app is in background
        if (!isAppForeground && !isReminderShowing) {
            showFullScreenReminder(item)
        }
    }

    private fun showFullScreenReminder(item: ReminderChecker.ReminderItem) {
        try {
            isReminderShowing = true

            // === 主方法：通过 Notification + setFullScreenIntent 启动全屏界面 ===
            // Android 10+ 后台直接 startActivity() 会被静默阻止，
            // 必须通过高优先级通知的 setFullScreenIntent() 才能可靠弹出
            postFullScreenNotification(item)

            // === 辅助：也尝试直接 startActivity（某些设备/旧版本可能仍然有效）===
            try {
                val directIntent = Intent(this, FullScreenReminderActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra("id", item.id)
                    putExtra("type", item.type)
                    putExtra("title", item.title)
                    putExtra("body", item.body ?: "")
                    putExtra("priority", item.priority)
                    putExtra("dueTime", item.dueTime ?: "")
                    putExtra("assignee", item.assignee ?: "")
                    putExtra("habitIconCode", item.habitIconCode)
                    putExtra("habitTargetCount", item.habitTargetCount)
                    putExtra("habitCurrentCount", item.habitCurrentCount)
                    putExtra("habitNeedsRecord", item.habitNeedsRecord)
                    putExtra("voiceEnabled", item.voiceEnabled)
                    putExtra("soundEnabled", item.soundEnabled)
                    putExtra("vibrationEnabled", item.vibrationEnabled)
                }
                startActivity(directIntent)
            } catch (e: Exception) {
                Log.d(TAG, "Direct startActivity blocked (expected on Android 10+)", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show full-screen reminder", e)
            isReminderShowing = false
        }
    }

    /**
     * 通过高优先级通知 + setFullScreenIntent 弹出全屏提醒
     * 这是 Android 10+ 后台弹出全屏界面的唯一可靠方式
     */
    private fun postFullScreenNotification(item: ReminderChecker.ReminderItem) {
        val nm = getSystemService(NotificationManager::class.java)

        // 创建高重要性通知渠道
        val channelId = "reminder_fullscreen_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "全屏提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "任务和习惯全屏提醒"
                enableLights(true)
                enableVibration(true)
                setSound(null, null) // 我们自己播放声音，不需要系统通知音
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

        // 构建全屏 Intent（包含所有提醒数据）
        val fullScreenIntent = Intent(this, FullScreenReminderActivity::class.java).apply {
            putExtra("id", item.id)
            putExtra("type", item.type)
            putExtra("title", item.title)
            putExtra("body", item.body ?: "")
            putExtra("priority", item.priority)
            putExtra("dueTime", item.dueTime ?: "")
            putExtra("assignee", item.assignee ?: "")
            putExtra("habitIconCode", item.habitIconCode)
            putExtra("habitTargetCount", item.habitTargetCount)
            putExtra("habitCurrentCount", item.habitCurrentCount)
            putExtra("habitNeedsRecord", item.habitNeedsRecord)
            putExtra("voiceEnabled", item.voiceEnabled)
            putExtra("soundEnabled", item.soundEnabled)
            putExtra("vibrationEnabled", item.vibrationEnabled)
        }

        val fullScreenPendingIntent = PendingIntent.getActivity(
            this, item.id.hashCode(), fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 构建高优先级通知（触发全屏 Intent）
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(item.title)
            .setContentText(item.body ?: "")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setTimeoutAfter(60_000L) // 1分钟后自动取消
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .build()

        nm.notify(item.id.hashCode(), notification)
        Log.d(TAG, "Full-screen notification posted for: ${item.title}")
    }

    private fun buildEventJson(id: String, type: String, action: String): String {
        return """{"id":"$id","type":"$type","action":"$action"}"""
    }

    fun setAppForeground(foreground: Boolean) {
        isAppForeground = foreground
    }

    fun refreshData(type: String, id: String?) {
        checker?.refreshData(type, id)
    }

    fun clearState(id: String) {
        checker?.clearTaskState(id)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "提醒服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "持续监控任务和习惯提醒"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("提醒服务运行中")
            .setContentText("正在监控任务和习惯提醒")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "onTaskRemoved — app swiped from recents")
        // AlarmManager periodic checks will automatically restart the service
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "ReminderForegroundService destroyed")
        isRunning = false
        isAppForeground = false
        isReminderShowing = false

        cancelScheduledCheck()
        handlerThread?.quitSafely()
        try { wakeLock?.release() } catch (_: Exception) {}
        ttsHelper?.release()

        handlerThread = null
        wakeLock = null
        checker = null
        audioHelper = null
        ttsHelper = null

        // Schedule restart unless user explicitly stopped the service
        if (!userRequestedStop) {
            Log.d(TAG, "Service destroyed unexpectedly, scheduling restart")
            scheduleRestart(5_000L)
        }
    }

    private var userRequestedStop = false

    private fun scheduleRestart(delayMs: Long) {
        try {
            val restartIntent = Intent(this, ReminderForegroundService::class.java)
            val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    this, 1, restartIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getService(
                    this, 1, restartIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + delayMs,
                pendingIntent
            )
            Log.d(TAG, "Restart scheduled in ${delayMs}ms")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule restart", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
