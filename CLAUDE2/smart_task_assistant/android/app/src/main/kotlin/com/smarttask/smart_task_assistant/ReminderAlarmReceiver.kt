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
            Log.e(TAG, "Failed to start service (will retry in 30s via safety net alarm)", e)
            // 不释放 WakeLock——让安全网闹钟在 30 秒后重试
            // WakeLock 会在 60 秒后自动超时释放
        }
    }
}
