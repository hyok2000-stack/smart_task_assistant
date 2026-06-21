package com.smarttask.smart_task_assistant

import android.app.*
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 提醒前台服务：使用 AlarmManager 在 Doze 模式下也能定时唤醒检查任务/习惯
 */
class ReminderForegroundService : Service() {
    companion object {
        private const val TAG = "ReminderForegroundService"
        private const val CHANNEL_ID = "reminder_service_channel"
        private const val FULLSCREEN_SILENT_CHANNEL_ID = "reminder_fullscreen_channel"
        private const val FULLSCREEN_SOUND_CHANNEL_ID = "reminder_sound_channel_v2"
        private const val NOTIFICATION_ID = 2001
        private const val CHECK_INTERVAL = 30_000L // 30 seconds

        // Intent actions
        const val ACTION_STOP = "com.smarttask.smart_task_assistant.ACTION_STOP_REMINDER"
        const val ACTION_APP_FOREGROUND = "com.smarttask.smart_task_assistant.ACTION_APP_FOREGROUND"
        const val ACTION_APP_BACKGROUND = "com.smarttask.smart_task_assistant.ACTION_APP_BACKGROUND"
        const val ACTION_CLEAR_STATE = "com.smarttask.smart_task_assistant.ACTION_CLEAR_STATE"
        const val ACTION_CLEAR_CONTINUAL = "com.smarttask.smart_task_assistant.ACTION_CLEAR_CONTINUAL"
        const val ACTION_SNOOZE = "com.smarttask.smart_task_assistant.ACTION_SNOOZE"
        const val ACTION_REFRESH_DATA = "com.smarttask.smart_task_assistant.ACTION_REFRESH_DATA"
        const val ACTION_CHECK = "com.smarttask.smart_task_assistant.ACTION_CHECK"

        private const val CHECK_REQUEST_CODE = 1001
        private const val RESTART_REQUEST_CODE = 2001

        @Volatile
        var isRunning = false
            private set

        @Volatile
        var isReminderShowing = false

        @Volatile
        private var isReminderShowingSince = 0L

        private const val REMINDER_SHOWING_TIMEOUT = 120_000L // 2min timeout

        fun start(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java).apply {
                action = ACTION_CHECK
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private var checker: ReminderChecker? = null
    private var audioHelper: ReminderAudioHelper? = null
    private var ttsHelper: ReminderTtsHelper? = null
    private var handlerThread: HandlerThread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var checkHandler: Handler? = null
    private var screenStateReceiverRegistered = false
    private var voiceHoldRunnable: Runnable? = null

    @Volatile
    private var isAppForeground = false

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    isAppForeground = false
                    Log.d(TAG, "Screen off detected, native reminder service takes over")
                    // 获取 WakeLock 确保 handler 线程执行完毕前 CPU 不会休眠
                    // 否则 CPU 可能在 post 执行前就回睡，导致 onHandleCheck 和 scheduleNextCheck 不执行
                    ReminderAlarmReceiver.acquireWakeLock(this@ReminderForegroundService)
                    checkHandler?.post {
                        try {
                            onHandleCheck()
                            scheduleNextCheck()
                        } finally {
                            ReminderAlarmReceiver.releaseWakeLock()
                        }
                    }
                }
                Intent.ACTION_USER_PRESENT -> {
                    Log.d(TAG, "User present detected")
                }
            }
        }
    }

    // 标记 onCreate 的首次检查是否待执行，防止 onStartCommand(else) 重复触发
    @Volatile
    private var onCreateCheckPending = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "ReminderForegroundService created")
        isRunning = true
        isAppForeground = false // 默认后台
        onCreateCheckPending = true

        checker = ReminderChecker(this)
        audioHelper = ReminderAudioHelper(this)
        ttsHelper = ReminderTtsHelper(this)

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        // 电池优化和精确定时权限检查（国产 ROM Doze 模式必需）
        checkBatteryAndAlarmPermissions()

        handlerThread = HandlerThread("ReminderCheckThread").apply { start() }
        checkHandler = Handler(handlerThread!!.looper)

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ReminderService::Check")
        wakeLock?.setReferenceCounted(false)

        try {
            val screenFilter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenStateReceiver, screenFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(screenStateReceiver, screenFilter)
            }
            screenStateReceiverRegistered = true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register screen state receiver", e)
        }

        // 立即执行首次检查（不等 30s），确保重启后不遗漏提醒
        // 等待 TTS 引擎初始化完成后再执行首次检查，避免语音播放失败
        // 获取 WakeLock 防止 TTS 初始化期间 CPU 休眠导致后续检查不执行
        ReminderAlarmReceiver.acquireWakeLock(this)
        checkHandler?.post {
            try {
                onCreateCheckPending = false
                Log.d(TAG, "Immediate first check after service create, waiting for TTS...")
                ttsHelper?.waitForReady()
                Log.d(TAG, "TTS ready, proceeding with first check")
                onHandleCheck()
                // scheduleNextCheck 已在 onHandleCheck 内部调用，此处作为安全兜底
                scheduleNextCheck()
            } finally {
                ReminderAlarmReceiver.releaseWakeLock()
            }
        }
    }

    /**
     * 检查电池优化白名单和精确定时权限
     * 国产 ROM 在 Doze 模式下会延迟或取消非白名单 APP 的 AlarmManager 闹钟，
     * 导致休眠时提醒完全失效。首次创建时自动请求一次白名单。
     */
    private fun checkBatteryAndAlarmPermissions() {
        // --- 电池优化 ---
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
        Log.d(TAG, "Battery optimization: isIgnoring=$isIgnoring")

        if (!isIgnoring) {
            Log.w(TAG, "WARNING: App is NOT whitelisted from battery optimization! " +
                "Reminders will be delayed or missed during Doze mode.")
            val sp = getSharedPreferences("reminder_prefs", Context.MODE_PRIVATE)
            if (!sp.getBoolean("battery_optimization_prompted", false)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    sp.edit().putBoolean("battery_optimization_prompted", true).apply()
                    Log.d(TAG, "Battery optimization exemption dialog shown")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to show battery optimization dialog", e)
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        sp.edit().putBoolean("battery_optimization_prompted", true).apply()
                    } catch (e2: Exception) {
                        Log.w(TAG, "Also failed to open battery settings", e2)
                    }
                }
            }
        }

        // --- 精确定时权限 (Android 12+) ---
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val canSchedule = alarmManager.canScheduleExactAlarms()
            Log.d(TAG, "Exact alarm permission: canScheduleExactAlarms=$canSchedule")
            if (!canSchedule) {
                Log.w(TAG, "WARNING: Exact alarm permission not granted! " +
                    "setAlarmClock() will silently fail on Android 12+.")
                // 引导用户授权精确闹钟（仅提示一次，避免反复弹设置页）
                val sp = getSharedPreferences("reminder_prefs", Context.MODE_PRIVATE)
                if (!sp.getBoolean("exact_alarm_prompted", false)) {
                    try {
                        // Settings.ACTION_REQUEST_EXACT_ALARM 需 API 31+，用字符串常量兼容较低 compileSdk；运行时已限定 SDK_INT>=S
                        val intent = Intent("android.settings.REQUEST_EXACT_ALARM").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        sp.edit().putBoolean("exact_alarm_prompted", true).apply()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to request exact alarm permission", e)
                    }
                }
            }
        }
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
                // AlarmManager woke us up — run check on HandlerThread (避免主线程阻塞)
                if (onCreateCheckPending) {
                    Log.d(TAG, "onCreate check pending, skip ACTION_CHECK to avoid double trigger")
                } else {
                    checkHandler?.post {
                        onHandleCheck()
                        scheduleNextCheck()
                    }
                }
            }
            ACTION_APP_FOREGROUND -> {
                isAppForeground = true
                Log.d(TAG, "App is foreground, suppressing FullScreenActivity")
            }
            ACTION_APP_BACKGROUND -> {
                isAppForeground = false
                Log.d(TAG, "App is background, enabling FullScreenActivity")
                // 在后台线程同步状态 + 检查（避免主线程 DB 查询导致 ANR）
                checkHandler?.post {
                    checker?.syncAllHabitsState()
                    onHandleCheck()
                    scheduleNextCheck()
                }
            }
            ACTION_CLEAR_STATE -> {
                val id = intent.getStringExtra("id")
                if (id != null) {
                    checker?.clearTaskState(id)
                }
            }
            ACTION_CLEAR_CONTINUAL -> {
                val id = intent.getStringExtra("id")
                if (id != null) {
                    checker?.clearContinualState(id)
                }
            }
            ACTION_SNOOZE -> {
                val id = intent.getStringExtra("id")
                val minutes = intent.getIntExtra("minutes", 10)
                if (id != null) {
                    val snoozeUntil = intent.getLongExtra(
                        "snoozeUntil",
                        System.currentTimeMillis() + minutes * 60_000L
                    )
                    checker?.setSnooze(id, snoozeUntil)
                    Log.d(TAG, "Task snoozed from Flutter: id=$id until=$snoozeUntil")
                    scheduleNextCheck()
                }
            }
            ACTION_REFRESH_DATA -> {
                val type = intent.getStringExtra("type") ?: "all"
                val id = intent.getStringExtra("id")
                checkHandler?.post {
                    checker?.refreshData(type, id)
                    onHandleCheck()
                    scheduleNextCheck()
                }
            }
            else -> {
                // Initial start or restart — immediate check + schedule
                if (onCreateCheckPending) {
                    // onCreate 的首次检查尚未执行，跳过避免重复触发
                    Log.d(TAG, "onCreate check pending, skip to avoid double trigger")
                } else {
                    Log.d(TAG, "Service (re)started, running immediate check")
                    checkHandler?.post {
                        onHandleCheck()
                        scheduleNextCheck()
                    }
                }
            }
        }

        return START_STICKY
    }

    // ==================== AlarmManager scheduling ====================

    /**
     * 调度下次检查闹钟
     * 使用 setAlarmClock（闹钟级别），不受 Doze 模式限流。
     * setExactAndAllowWhileIdle 在 Doze 下被限流为约 9 分钟一次，
     * 导致持续提醒被延迟累积。
     *
     * 注意：setAlarmClock 要求墙钟时间（currentTimeMillis），
     * setExactAndAllowWhileIdle 使用 elapsedRealtime。
     */
    private fun scheduleNextCheck() {
        val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            action = ReminderAlarmReceiver.ACTION_CHECK
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this, CHECK_REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerWallClock = System.currentTimeMillis() + CHECK_INTERVAL
        val triggerElapsed = SystemClock.elapsedRealtime() + CHECK_INTERVAL

        try {
            // 闹钟级别：不受 Doze 限制，到点必定触发
            // AlarmClockInfo 使用墙钟时间（currentTimeMillis）
            val alarmInfo = AlarmManager.AlarmClockInfo(triggerWallClock, null)
            alarmManager.setAlarmClock(alarmInfo, pendingIntent)
            Log.d(TAG, "Next check scheduled in ${CHECK_INTERVAL}ms via AlarmClock at $triggerWallClock")
        } catch (e: Exception) {
            Log.e(TAG, "setAlarmClock failed, falling back to setExactAndAllowWhileIdle", e)
            try {
                // 降级方案：setExactAndAllowWhileIdle 使用 elapsedRealtime
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerElapsed,
                    pendingIntent
                )
                Log.d(TAG, "Next check scheduled via setExactAndAllowWhileIdle")
            } catch (e2: Exception) {
                Log.e(TAG, "setExactAndAllowWhileIdle also failed", e2)
                alarmManager.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerElapsed,
                    pendingIntent
                )
            }
        }
    }

    private fun cancelScheduledCheck() {
        val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            action = ReminderAlarmReceiver.ACTION_CHECK
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this, CHECK_REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Scheduled check cancelled")
    }

    // ==================== Check logic ====================

    /**
     * 检测屏幕是否亮着。屏幕关闭时（休眠），即使 isAppForeground 为 true，
     * Flutter 也无法播放语音（引擎暂停），应由原生层接管提醒。
     */
    private fun isScreenOn(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    private fun onHandleCheck() {
        // 取消上一次检查周期的延迟释放，防止在本次检查期间误杀 WakeLock
        voiceHoldRunnable?.let { checkHandler?.removeCallbacks(it) }
        voiceHoldRunnable = null

        // 超时自动重置 isReminderShowing（防止 Activity 未成功启动导致永远无法弹窗）
        if (isReminderShowing && System.currentTimeMillis() - isReminderShowingSince > REMINDER_SHOWING_TIMEOUT) {
            isReminderShowing = false
            Log.d(TAG, "isReminderShowing timed out, resetting")
        }

        // Flutter 处理前台+亮屏的所有提醒，原生层完全跳过
        val screenOn = isScreenOn()
        val effectiveForeground = isAppForeground && screenOn
        Log.d(TAG, "Check state: appForeground=$isAppForeground screenOn=$screenOn effectiveForeground=$effectiveForeground")
        if (effectiveForeground) {
            Log.d(TAG, "App foreground + screen on, skipping native check (Flutter handles it)")
            scheduleNextCheck()
            ReminderAlarmReceiver.releaseWakeLock()
            return
        }

        val needsVoiceHold = try {
            wakeLock?.acquire(60_000L)
            val items = checker?.checkAll(isForeground = false) ?: emptyList()

            Log.d(TAG, "Check found ${items.size} items to trigger")

            for (item in items) {
                Log.d(TAG, "Triggering reminder: type=${item.type} id=${item.id} title=${item.title}")
                val voiceAcceptedOrNoVoice = triggerReminder(item)
                if (voiceAcceptedOrNoVoice) {
                    markReminderDelivered(item)
                } else {
                    Log.w(TAG, "Reminder voice was not accepted; keeping state unmarked for retry: ${item.id}")
                }
            }

            items.any {
                it.voiceEnabled && (!it.voiceText.isNullOrBlank() || !it.customVoicePath.isNullOrBlank() || !it.title.isNullOrBlank())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onHandleCheck", e)
            false
        }

        // 在释放 WakeLock 前先调度下次检查，确保闹钟不会丢失
        scheduleNextCheck()

        if (needsVoiceHold) {
            // 语音播放和 TTS 重试需要额外时间，延迟释放锁。
            // 使用 voiceHoldRunnable 追踪，下次 onHandleCheck 会取消此释放
            voiceHoldRunnable = Runnable {
                try { wakeLock?.release() } catch (_: Exception) {}
                Log.d(TAG, "WakeLock released (voice hold)")
                ReminderAlarmReceiver.releaseWakeLock()
                voiceHoldRunnable = null
            }
            checkHandler?.postDelayed(voiceHoldRunnable!!, 60_000L)
        } else {
            try { wakeLock?.release() } catch (_: Exception) {}
            ReminderAlarmReceiver.releaseWakeLock()
        }
    }

    private fun markReminderDelivered(item: ReminderChecker.ReminderItem) {
        when (item.type) {
            "task" -> checker?.markTaskReminderShown(item.id)
            "habit" -> checker?.markHabitTriggered(item.id)
        }
        Log.d(TAG, "Marked reminder delivered after voice accepted/no voice: type=${item.type} id=${item.id}")
    }

    private fun triggerReminder(item: ReminderChecker.ReminderItem): Boolean {
        // 到达此方法时 effectiveForeground 必为 false（onHandleCheck 已跳过前台场景）
        // 由原生层全权处理：声音、语音（不弹全屏界面）

        val screenOn = isScreenOn()
        // 屏幕关闭时，亮屏唤醒音频硬件 + 等待系统恢复
        if (!screenOn) {
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                val screenLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "ReminderService::ScreenWake"
                )
                screenLock.acquire(10_000L)
                checkHandler?.postDelayed({
                    try { if (screenLock.isHeld) screenLock.release() } catch (_: Exception) {}
                }, 10_000L)
                Log.d(TAG, "Screen wake acquired for reminder")
            } catch (e: Exception) {
                Log.w(TAG, "Screen wake failed", e)
            }
            // 等待音频子系统从 Doze 恢复（深度休眠需要更久）
            try { Thread.sleep(5000L) } catch (_: InterruptedException) {}
        }

        val uiAlreadyShowing = isReminderShowing
        if (uiAlreadyShowing) {
            Log.d(TAG, "Reminder UI already showing; retrying voice without opening another UI")
        }

        // 振动：由 Vibrator 服务直接触发（Doze 模式可靠）
        if (item.vibrationEnabled) {
            audioHelper?.playVibration()
        }

        val hasVoiceContent = item.voiceEnabled &&
            (!item.voiceText.isNullOrBlank() || !item.customVoicePath.isNullOrBlank() || !item.title.isNullOrBlank())
        Log.d(TAG, "Voice check for '${item.title}': voiceEnabled=${item.voiceEnabled}, hasContent=$hasVoiceContent")
        var voiceAccepted = !hasVoiceContent

        // ====== 声音策略 ======
        // 有语音时：先响一下（~800ms 预热音频硬件），然后停掉再播 TTS 语音。
        //   TTS 失败时再响完整铃声兜底。
        // 无语音时：直接播放完整铃声。
        // MediaPlayer + USAGE_ALARM 是 Doze 模式下最可靠的音频输出方式，
        // 不依赖通知系统（国产 ROM 会静默通知声音）。
        var soundMp: android.media.MediaPlayer? = null
        if (item.soundEnabled) {
            soundMp = audioHelper?.playReminderSound()
        }

        // 发静默通知（仅视觉展示，声音由 MediaPlayer 处理）
        if (!uiAlreadyShowing) {
            postSilentNotification(item, playSound = false)
        }

        // TTS 语音播报
        if (hasVoiceContent) {
            // 有语音时：响 800ms 后停掉铃声，让语音接管
            if (soundMp != null) {
                try { Thread.sleep(800L) } catch (_: InterruptedException) {}
                try {
                    soundMp.stop()
                    soundMp.release()
                    soundMp = null
                    Log.d(TAG, "Sound stopped after warm-up, starting voice")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to stop sound", e)
                }
            }

            val speakText = when {
                !item.voiceText.isNullOrBlank() -> item.voiceText
                item.type == "task" -> {
                    val prefix = when (item.priority) {
                        2 -> "紧急任务提醒，"
                        0 -> "温和提醒，"
                        else -> "任务提醒，"
                    }
                    val timeContext = buildTimeContext(item.dueTime)
                    "$prefix$timeContext${item.title}"
                }
                else -> item.title
            }
            Log.d(TAG, "Requesting voice for '${item.title}': text='$speakText'")
            val effectiveCustomVoicePath =
                if (item.voiceType == "custom") item.customVoicePath else null
            voiceAccepted = ttsHelper?.speak(
                text = speakText ?: "",
                voiceType = item.voiceType,
                voiceStyle = item.voiceStyle,
                speed = item.voiceSpeed,
                customVoicePath = effectiveCustomVoicePath
            ) ?: false
            Log.d(TAG, "Voice accepted for '${item.title}': $voiceAccepted")

            // 语音失败时：补响完整铃声兜底（确保用户至少能听到声音提醒）
            if (!voiceAccepted && item.soundEnabled) {
                Log.w(TAG, "Voice failed for '${item.title}', playing full alarm sound as fallback")
                audioHelper?.playReminderSound()
            }
        }

        // Send event to Flutter
        val eventJson = buildEventJson(item.id, item.type, "shown")
        ReminderBridge.getInstance().sendEvent(eventJson)

        return voiceAccepted
    }

    private fun showFullScreenReminder(item: ReminderChecker.ReminderItem): Boolean {
        try {
            postFullScreenNotification(item)

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
                isReminderShowing = true
                isReminderShowingSince = System.currentTimeMillis()
            } catch (e: Exception) {
                Log.d(TAG, "Direct startActivity blocked (expected on Android 10+), using notification fullScreenIntent")
                // Android 10+ 可能阻止后台 startActivity，但通知的 fullScreenIntent 仍会触发
                // 设置标记避免重复弹窗，配合 REMINDER_SHOWING_TIMEOUT 自动恢复
                isReminderShowing = true
                isReminderShowingSince = System.currentTimeMillis()
            }
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show full-screen reminder", e)
            isReminderShowing = false
            return false
        }
    }

    /**
     * 发送提醒通知（带声音），使用通知系统播放声音（Doze 模式下最可靠）
     * 通知系统有系统级权限，MediaPlayer 在 Doze 下可能因音频硬件未恢复而静默失败
     */
    private fun postSilentNotification(item: ReminderChecker.ReminderItem, playSound: Boolean = true) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            val channelId = if (playSound && item.soundEnabled) "reminder_alarm_v2" else "reminder_silent_v2"

            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(item.title ?: "任务提醒")
                .setContentText(item.body ?: "")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setTimeoutAfter(30_000L)
                .build()

            nm.notify(item.id.hashCode(), notification)
            Log.d(TAG, "Sound notification posted for: ${item.title} (sound=${item.soundEnabled}, vibration=${item.vibrationEnabled})")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post notification", e)
        }
    }

    private fun postFullScreenNotification(item: ReminderChecker.ReminderItem) {
        val nm = getSystemService(NotificationManager::class.java)

        val channelId = if (item.soundEnabled) {
            FULLSCREEN_SOUND_CHANNEL_ID
        } else {
            FULLSCREEN_SILENT_CHANNEL_ID
        }
        val notificationSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val alarmAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                FULLSCREEN_SILENT_CHANNEL_ID,
                "全屏提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "任务和习惯全屏提醒"
                enableLights(true)
                enableVibration(true)
                setSound(null, null)
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
            val soundChannel = NotificationChannel(
                FULLSCREEN_SOUND_CHANNEL_ID,
                "Reminder sound",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminder notifications with sound while locked or asleep"
                enableLights(true)
                enableVibration(true)
                if (notificationSoundUri != null) {
                    setSound(notificationSoundUri, alarmAttributes)
                }
                setShowBadge(false)
            }
            nm.createNotificationChannel(soundChannel)
        }

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

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(item.title)
            .setContentText(item.body ?: "")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setSound(if (item.soundEnabled) notificationSoundUri else null)
            .setAutoCancel(true)
            .setTimeoutAfter(60_000L)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .build()

        nm.notify(item.id.hashCode(), notification)
        Log.d(TAG, "Full-screen notification posted for: ${item.title}")
    }

    private fun buildEventJson(id: String, type: String, action: String): String {
        return """{"id":"$id","type":"$type","action":"$action"}"""
    }

    private fun buildTimeContext(dueTime: String?): String {
        if (dueTime.isNullOrBlank()) return ""
        val due = checker?.parseDueTimeMillisPublic(dueTime) ?: return ""
        val diff = due - System.currentTimeMillis()
        return when {
            diff <= 0 -> "任务到期了，"
            diff < 60_000 -> "任务即将到期，"
            diff < 3_600_000 -> "${(diff / 60_000).toInt()}分钟后需要完成，"
            diff < 7_200_000 -> "1小时后需要完成，"
            else -> "${(diff / 3_600_000).toInt()}小时后需要完成，"
        }
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
            val nm = getSystemService(NotificationManager::class.java)

            // 前台服务常驻通道
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "提醒服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "持续监控任务和习惯提醒"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(serviceChannel)

            // 带铃声的提醒通道（无语音时使用）
            val alarmAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val alarmChannel = NotificationChannel(
                "reminder_alarm_v2",
                "任务提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "任务和习惯提醒通知（闹钟级别）"
                if (soundUri != null) setSound(soundUri, alarmAttributes) else setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                setBypassDnd(true)
            }
            nm.createNotificationChannel(alarmChannel)

            // 静音通道（有语音播报时使用）
            val silentChannel = NotificationChannel(
                "reminder_silent_v2",
                "语音提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "语音播报时不重复播铃声"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                setBypassDnd(true)
            }
            nm.createNotificationChannel(silentChannel)
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
        isAppForeground = false
        isReminderShowing = false

        // 重要：先安排重启，再做任何清理
        // onDestroy 中 cancelScheduledCheck 只取消周期检查 alarm，不影响重启 alarm
        scheduleRestart(1_000L)
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "ReminderForegroundService destroyed")
        isRunning = false
        isAppForeground = false
        isReminderShowing = false

        if (userRequestedStop) {
            cancelScheduledCheck()
        } else {
            Log.d(TAG, "Keeping scheduled check alarm alive after service destroy")
        }

        if (screenStateReceiverRegistered) {
            try { unregisterReceiver(screenStateReceiver) } catch (_: Exception) {}
            screenStateReceiverRegistered = false
        }

        handlerThread?.quitSafely()
        try { wakeLock?.release() } catch (_: Exception) {}
        ttsHelper?.release()

        handlerThread = null
        wakeLock = null
        checker = null
        audioHelper = null
        ttsHelper = null
        checkHandler = null

        // 非用户主动停止时，安排重启
        if (!userRequestedStop) {
            Log.d(TAG, "Service destroyed unexpectedly, scheduling restart")
            scheduleRestart(1_000L)
        }
    }

    private var userRequestedStop = false

    private fun scheduleRestart(delayMs: Long) {
        try {
            val restartIntent = Intent(this, ReminderAlarmReceiver::class.java).apply {
                action = ReminderAlarmReceiver.ACTION_RESTART
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this, RESTART_REQUEST_CODE, restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerWallClock = System.currentTimeMillis() + delayMs
            val triggerElapsed = SystemClock.elapsedRealtime() + delayMs
            try {
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerWallClock, null),
                    pendingIntent
                )
                Log.d(TAG, "Restart scheduled in ${delayMs}ms via AlarmClock")
            } catch (e: Exception) {
                Log.e(TAG, "Restart AlarmClock failed, falling back to setExactAndAllowWhileIdle", e)
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerElapsed,
                    pendingIntent
                )
                Log.d(TAG, "Restart scheduled in ${delayMs}ms via setExactAndAllowWhileIdle")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule restart", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
