package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 开机自启动接收器：设备启动后自动启动提醒前台服务
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            Log.d(TAG, "Boot completed, starting ReminderForegroundService")

            // 检查用户是否已启用服务（通过 SharedPreferences 记录）
            val prefs = context.getSharedPreferences("reminder_prefs", Context.MODE_PRIVATE)
            val serviceEnabled = prefs.getBoolean("service_enabled", true) // 默认开启

            if (serviceEnabled) {
                val serviceIntent = Intent(context, ReminderForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.d(TAG, "ReminderForegroundService started after boot")
            } else {
                Log.d(TAG, "Service disabled by user, not starting after boot")
            }
        }
    }
}
