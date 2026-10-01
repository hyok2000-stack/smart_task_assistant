package com.smarttask.smart_task_assistant

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.database.sqlite.SQLiteDatabase
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
 * 已知边界：
 * - 周期任务的"完成后自动创建下一期"逻辑在 Flutter 层，从通知完成不会生成下一期
 * - 子任务→父任务的自动完成联动（autoCompleteParentTask）同样在 Flutter 层，
 *   从通知完成最后一个子任务时父任务不会自动完成
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

        /**
         * 把延后合并进 Flutter SharedPreferences 的 snoozed_tasks_v1
         * （{id: 毫秒时间戳} 的 JSON），Flutter 回前台时会重新加载该键。
         */
        private fun mergeFlutterSnooze(context: Context, taskId: String, until: Long) {
            try {
                val sp = context.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                )
                val key = "flutter.snoozed_tasks_v1"
                val existing = sp.getString(key, null)
                val map = HashMap<String, Long>()
                if (!existing.isNullOrBlank()) {
                    // Dart 侧格式：jsonEncode({id: 毫秒}) 对象
                    val obj = org.json.JSONObject(existing)
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        map[k] = obj.optLong(k)
                    }
                }
                map[taskId] = until
                val entries = map.entries.joinToString(
                    ",", prefix = "{", postfix = "}"
                ) { "\"" + it.key + "\":" + it.value }
                sp.edit().putString(key, entries).apply()
                Log.d(TAG, "Flutter snooze merged for $taskId")
            } catch (e: Exception) {
                Log.w(TAG, "mergeFlutterSnooze failed (non-fatal)", e)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("id") ?: return
        when (intent.action) {
            ACTION_COMPLETE -> {
                var db: SQLiteDatabase? = null
                try {
                    // 与 Flutter sqflite 同一数据库文件（databases/smart_task_assistant.db）。
                    // 前置条件 status IN (0,1)：陈旧通知对已取消/已完成任务不再改写状态。
                    db = context.openOrCreateDatabase(
                        "smart_task_assistant.db", Context.MODE_PRIVATE, null
                    )
                    val rows = db.update(
                        "tasks",
                        android.content.ContentValues().apply {
                            put("status", 2)
                            put("completed_at", nowIso())
                            put("updated_at", nowIso())
                        },
                        "id = ? AND status IN (0, 1)",
                        arrayOf(taskId)
                    )
                    Log.d(TAG, "Complete via notification: $taskId, rows=$rows")
                } catch (e: Exception) {
                    Log.e(TAG, "Complete via notification failed", e)
                } finally {
                    try { db?.close() } catch (_: Exception) {}
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
                    // 同步到 Flutter 层的 snoozed_tasks_v1（JSON map）——否则 APP
                    // 回前台后 Flutter 检查链无此记录，会立即再次弹窗/响铃
                    mergeFlutterSnooze(context, taskId,
                        System.currentTimeMillis() + 10 * 60_000L)
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
