package com.smarttask.smart_task_assistant

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 提醒通知快捷操作接收器：完成 / 延后10分钟。
 *
 * 用户无需解锁进入 APP 即可处理提醒——直接写任务数据库
 * （Flutter 回前台时 _reloadData 会重新加载），并清除原生提醒状态，
 * 避免已处理的任务继续响铃。
 *
 * 已知边界：周期任务的"完成后自动创建下一期"逻辑在 Flutter 层，
 * 从通知完成不会生成下一期（下次打开 APP 时由该任务的重复规则再触发）。
 */
class ReminderActionReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ReminderActionReceiver"
        const val ACTION_COMPLETE = "com.smarttask.smart_task_assistant.ACTION_REMINDER_COMPLETE"
        const val ACTION_SNOOZE = "com.smarttask.smart_task_assistant.ACTION_REMINDER_SNOOZE10"

        fun completePendingIntent(context: Context, taskId: String): PendingIntent =
            actionPendingIntent(context, ACTION_COMPLETE, taskId)

        fun snoozePendingIntent(context: Context, taskId: String): PendingIntent =
            actionPendingIntent(context, ACTION_SNOOZE, taskId)

        private fun actionPendingIntent(
            context: Context,
            action: String,
            taskId: String
        ): PendingIntent {
            val intent = Intent(context, ReminderActionReceiver::class.java).apply {
                this.action = action
                putExtra("id", taskId)
            }
            return PendingIntent.getBroadcast(
                context,
                (action.hashCode() * 31 + taskId.hashCode()) and 0x7FFFFFFF,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun nowIso(): String =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())
    }

    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("id") ?: return
        when (intent.action) {
            ACTION_COMPLETE -> {
                try {
                    // 与 Flutter sqflite 同一数据库文件（databases/smart_task_assistant.db）
                    val db = context.openOrCreateDatabase(
                        "smart_task_assistant.db", Context.MODE_PRIVATE, null
                    )
                    db.execSQL(
                        "UPDATE tasks SET status = 2, completed_at = ?, updated_at = ? WHERE id = ?",
                        arrayOf<Any>(nowIso(), nowIso(), taskId)
                    )
                    db.close()
                    Log.d(TAG, "Task completed via notification action: $taskId")
                } catch (e: Exception) {
                    Log.e(TAG, "Complete via notification failed", e)
                }
                // 清除原生提醒状态，停止持续提醒
                try {
                    ReminderChecker(context).clearTaskState(taskId)
                } catch (e: Exception) {
                    Log.w(TAG, "Clear task state failed", e)
                }
            }
            ACTION_SNOOZE -> {
                try {
                    ReminderChecker(context).setSnooze(
                        taskId, System.currentTimeMillis() + 10 * 60_000L
                    )
                    Log.d(TAG, "Task snoozed 10min via notification action: $taskId")
                } catch (e: Exception) {
                    Log.e(TAG, "Snooze via notification failed", e)
                }
            }
        }
        // 收起该提醒通知并刷新桌面小组件
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(taskId.hashCode())
        } catch (_: Exception) {
        }
        TodayWidgetProvider.updateAll(context)
    }
}
