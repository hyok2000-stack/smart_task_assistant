package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * AlarmManager 闹钟接收器：在手机休眠/Doze 模式下唤醒 CPU 并触发提醒检查
 *
 * 关键设计：AlarmManager 的 PendingIntent 目标是此 Receiver 而非 Service。
 * 因为在国产 ROM 上，APP 被滑掉后 PendingIntent.getForegroundService() 的 alarm
 * 可能被系统取消；而 targeting BroadcastReceiver 更可靠——Receiver 再负责启动 Service。
 *
 * 重要：Receiver 在 onReceive() 中持有 WakeLock，防止 CPU 在 Service handler
 * 线程处理前回睡。Service 完成检查后负责释放该锁。
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ReminderAlarmReceiver"

        /** Action: 周期性检查 */
        const val ACTION_CHECK = "com.smarttask.smart_task_assistant.ACTION_ALARM_CHECK"

        /** Action: 服务重启 */
        const val ACTION_RESTART = "com.smarttask.smart_task_assistant.ACTION_ALARM_RESTART"

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
                startServiceSafely(context, serviceIntent)
            }
            else -> {
                // 来自其他源（如 BootReceiver 转发）也启动服务
                startServiceSafely(context, serviceIntent)
            }
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
            Log.e(TAG, "Failed to start service", e)
            // 服务启动失败，立即释放 WakeLock 避免浪费
            releaseWakeLock()
        }
    }
}
