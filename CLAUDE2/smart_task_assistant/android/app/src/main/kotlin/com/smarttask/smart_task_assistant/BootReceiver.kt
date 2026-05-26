package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 开机/解锁/升级后自动启动提醒前台服务
 * 监听多种系统事件，确保服务在各种场景下都能恢复运行
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received: action=${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_USER_PRESENT,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                startServiceIfNeeded(context)
            }
        }
    }

    private fun startServiceIfNeeded(context: Context) {
        // 检查用户是否已启用服务
        val prefs = context.getSharedPreferences("reminder_prefs", Context.MODE_PRIVATE)
        val serviceEnabled = prefs.getBoolean("service_enabled", true)

        if (!serviceEnabled) {
            Log.d(TAG, "Service disabled by user, not starting")
            return
        }

        // 如果服务已在运行，不重复启动
        if (ReminderForegroundService.isRunning) {
            Log.d(TAG, "Service already running, skip")
            return
        }

        // 获取 WakeLock，防止 CPU 在 Service 启动前回睡
        ReminderAlarmReceiver.acquireWakeLock(context)

        try {
            val serviceIntent = Intent(context, ReminderForegroundService::class.java).apply {
                action = ReminderForegroundService.ACTION_CHECK
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.d(TAG, "ReminderForegroundService started (trigger=${context.javaClass.simpleName})")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service", e)
            ReminderAlarmReceiver.releaseWakeLock()
        }
    }
}
