package com.smarttask.smart_task_assistant

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.os.PowerManager
import android.util.Log

/**
 * AlarmManager 闹钟接收器：在手机休眠/Doze 模式下唤醒 CPU 并触发提醒检查
 *
 * 关键设计：AlarmManager 的 PendingIntent 目标是此 Receiver 而非 Service。
 * 因为在国产 ROM 上，APP 被滑掉后 PendingIntent.getForegroundService() 的 alarm
 * 可能被系统取消；而 targeting BroadcastReceiver 更可靠——Receiver 再负责启动 Service。
 *
 * 重要：Receiver 在 onReceive() 中先调度下次闹钟（安全网），
 * 再启动 Service。确保即使 Service 启动失败（Android 12+ 后台限制），
 * 闹钟链也不会断裂。
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ReminderAlarmReceiver"

        /** Action: 周期性检查 */
        const val ACTION_CHECK = "com.smarttask.smart_task_assistant.ACTION_ALARM_CHECK"

        /** Action: 服务重启 */
        const val ACTION_RESTART = "com.smarttask.smart_task_assistant.ACTION_ALARM_RESTART"

        /** 与 Service 的 CHECK_REQUEST_CODE 保持一致 */
        private const val CHECK_REQUEST_CODE = 1001

        private const val CHECK_INTERVAL = 30_000L

        /** 服务启动失败时兜底通知的渠道/ID */
        private const val FALLBACK_CHANNEL_ID = "reminder_alarm_v3"
        private const val FALLBACK_REQUEST_CODE = 3001
        private const val FALLBACK_NOTIFICATION_ID = 3002

        /**
         * 静态 WakeLock：由 Receiver 获取，由 Service 在检查完成后释放。
         * 确保从 AlarmManager 唤醒到语音播放完毕，CPU 始终保持运行。
         */
        @Volatile
        private var alarmWakeLock: PowerManager.WakeLock? = null

        fun acquireWakeLock(context: Context) {
            synchronized(this) {
                if (alarmWakeLock?.isHeld == true) {
                    Log.d(TAG, "Alarm WakeLock already held, skipping")
                    return
                }
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                alarmWakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "ReminderAlarm::Wake"
                ).apply {
                    setReferenceCounted(false)
                    acquire(60_000L)
                }
                Log.d(TAG, "Alarm WakeLock acquired (60s timeout)")
            }
        }

        fun releaseWakeLock() {
            synchronized(this) {
                try {
                    alarmWakeLock?.let {
                        if (it.isHeld) {
                            it.release()
                            Log.d(TAG, "Alarm WakeLock released")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to release alarm WakeLock", e)
                }
                alarmWakeLock = null
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Alarm received: action=${intent.action}")

        // 立即获取 WakeLock，防止 CPU 在启动 Service 前回睡
        acquireWakeLock(context)

        // ★ 关键修复：先调度下次闹钟（安全网），再启动 Service。
        // 如果 Service 启动失败（Android 12+ 后台限制 / ROM 杀后台），
        // 闹钟链不会断裂，30 秒后会再次尝试。
        scheduleSafetyNetAlarm(context)

        val serviceIntent = Intent(context, ReminderForegroundService::class.java)

        when (intent.action) {
            ACTION_CHECK -> {
                // 周期性检查：转发给 Service
                serviceIntent.action = ReminderForegroundService.ACTION_CHECK
                startServiceSafely(context, serviceIntent)
            }
            ACTION_RESTART -> {
                // 服务重启：直接启动 Service
                Log.d(TAG, "Restarting ReminderForegroundService via alarm")
                serviceIntent.action = ReminderForegroundService.ACTION_CHECK
                startServiceSafely(context, serviceIntent)
            }
            else -> {
                serviceIntent.action = ReminderForegroundService.ACTION_CHECK
                startServiceSafely(context, serviceIntent)
            }
        }
    }

    /**
     * 安全网闹钟：在 Receiver 中预调度下次闹钟
     * 确保即使 Service 启动失败（Android 12+ 后台限制 / ROM 杀后台），
     * 30 秒后闹钟仍会再次触发，闹钟链不会断裂。
     * Service 成功启动后会调用 scheduleNextCheck() 覆盖此闹钟（更精确的调度）。
     */
    private fun scheduleSafetyNetAlarm(context: Context) {
        try {
            val nextIntent = Intent(context, ReminderAlarmReceiver::class.java).apply {
                action = ACTION_CHECK
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, CHECK_REQUEST_CODE, nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerWallClock = System.currentTimeMillis() + CHECK_INTERVAL
            val triggerElapsed = SystemClock.elapsedRealtime() + CHECK_INTERVAL

            try {
                val alarmInfo = AlarmManager.AlarmClockInfo(triggerWallClock, null)
                alarmManager.setAlarmClock(alarmInfo, pendingIntent)
                Log.d(TAG, "Safety net alarm scheduled in ${CHECK_INTERVAL}ms via AlarmClock")
            } catch (e: Exception) {
                Log.w(TAG, "Safety net AlarmClock failed, falling back", e)
                try {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerElapsed,
                        pendingIntent
                    )
                    Log.d(TAG, "Safety net alarm scheduled via setExactAndAllowWhileIdle")
                } catch (e2: Exception) {
                    Log.e(TAG, "Safety net alarm scheduling also failed", e2)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule safety net alarm", e)
        }
    }

    private fun startServiceSafely(context: Context, intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(TAG, "Service started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service, posting fallback alarm notification", e)
            // 服务启动失败（Android 12+ 后台限制 / ROM 杀后台）时，
            // 闹钟已把 CPU 唤醒、WakeLock 在手——直接用通知系统兜底：
            // 通知渠道带铃声+振动，不依赖前台服务，保证用户至少能听到/感到提醒。
            postFallbackNotification(context)
            // 通知渠道声音常被国产 ROM 在后台压制，再直接播放一次铃声
            // （与振动并行的第三重保障，WakeLock 60s 覆盖播放时长）
            playFallbackSound(context)
        }
    }

    /**
     * 直接通过 MediaPlayer 播放系统闹钟铃声（不依赖通知系统与前台服务）。
     * STREAM_ALARM 音量为 0 时改走媒体音量，避免"播放成功但无声"。
     */
    private fun playFallbackSound(context: Context) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
            val attrs = if (try {
                    audioManager?.getStreamVolume(android.media.AudioManager.STREAM_ALARM) ?: 1
                } catch (_: Exception) { 1 } > 0
            ) {
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            } else {
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }

            val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
                ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
                ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
            if (uri == null) {
                Log.w(TAG, "No fallback ringtone available")
                return
            }

            val mp = android.media.MediaPlayer()
            mp.setAudioAttributes(attrs)
            mp.setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setDataSource(context, uri)
            mp.setOnCompletionListener { it.release() }
            mp.setOnErrorListener { player, what, extra ->
                Log.e(TAG, "Fallback sound error: what=$what extra=$extra")
                player.release()
                true
            }
            mp.prepare()
            mp.start()
            Log.d(TAG, "Fallback ringtone playing")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play fallback ringtone", e)
        }
    }

    /**
     * 服务启动失败时的兜底通知：铃声渠道（闹钟级别）+ 直接振动。
     * 不尝试全屏跳转之外的任何 UI，通知本身可携带 fullScreenIntent，
     * 系统在锁屏/免安装弹窗权限允许时仍会弹出全屏提醒页。
     */
    private fun postFallbackNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager

            // 渠道：铃声 + 振动 + 闹钟音频属性 + 绕过勿扰（渠道创建幂等）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val soundUri = android.media.RingtoneManager.getDefaultUri(
                    android.media.RingtoneManager.TYPE_ALARM)
                    ?: android.media.RingtoneManager.getDefaultUri(
                        android.media.RingtoneManager.TYPE_NOTIFICATION)
                val alarmAttributes = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val channel = android.app.NotificationChannel(
                    FALLBACK_CHANNEL_ID, "紧急提醒（兜底）",
                    android.app.NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "后台服务不可用时的兜底提醒通知"
                    if (soundUri != null) setSound(soundUri, alarmAttributes)
                    enableVibration(true)
                    enableLights(true)
                    setBypassDnd(true)
                }
                nm.createNotificationChannel(channel)
            }

            // 直接振动一次（与 ReminderAudioHelper 相同的节奏），不依赖通知渠道设置
            try {
                val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? android.os.VibratorManager)
                        ?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
                }
                val pattern = longArrayOf(0, 300, 100, 300, 100, 300)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(android.os.VibrationEffect.createWaveform(pattern, -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(pattern, -1)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Fallback vibration failed", e)
            }

            // 点击通知打开全屏提醒页（fullScreenIntent 由系统决定是否弹出）
            val contentIntent = Intent(context, FullScreenReminderActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("title", "任务提醒")
            }
            val pendingIntent = PendingIntent.getActivity(
                context, FALLBACK_REQUEST_CODE, contentIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = androidx.core.app.NotificationCompat.Builder(context, FALLBACK_CHANNEL_ID)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle("任务提醒")
                .setContentText("有任务需要处理，点击查看")
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_MAX)
                .setCategory(androidx.core.app.NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setTimeoutAfter(60_000L)
                .setFullScreenIntent(pendingIntent, true)
                .build()

            nm.notify(FALLBACK_NOTIFICATION_ID, notification)
            Log.d(TAG, "Fallback alarm notification posted")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post fallback notification", e)
        }
    }
}
