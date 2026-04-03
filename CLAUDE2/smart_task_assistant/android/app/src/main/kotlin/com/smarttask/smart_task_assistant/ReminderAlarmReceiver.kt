package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * AlarmManager 闹钟接收器：在手机休眠/Doze 模式下唤醒 CPU 并触发提醒检查
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ReminderAlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Alarm received, triggering check in ReminderForegroundService")

        // Forward to the service as ACTION_CHECK
        val serviceIntent = Intent(context, ReminderForegroundService::class.java).apply {
            action = ReminderForegroundService.ACTION_CHECK
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service from alarm", e)
        }
    }
}
