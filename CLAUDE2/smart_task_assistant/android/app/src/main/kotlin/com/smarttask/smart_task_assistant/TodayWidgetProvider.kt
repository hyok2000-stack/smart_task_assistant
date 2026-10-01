package com.smarttask.smart_task_assistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import android.widget.RemoteViews

/**
 * 今日任务桌面小组件：
 * - 显示今天到期（无则显示接下来 5 个未完成）的任务，最多 5 条
 * - 点任务行直接标记完成（复用 ReminderActionReceiver），点头部打开 APP
 * - 刷新时机：系统定时（30 分钟）/ 开机 / APP 回前台 / 数据变更 / 完成操作
 */
class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateAll(context)
    }

    companion object {
        private const val TAG = "TodayWidgetProvider"
        private const val MAX_ROWS = 5

        /** 刷新所有小组件实例（任何时机调用都安全） */
        fun updateAll(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                val widget = ComponentName(context, TodayWidgetProvider::class.java)
                val ids = manager.getAppWidgetIds(widget) ?: return
                if (ids.isEmpty()) return

                val views = buildRemoteViews(context)
                for (id in ids) {
                    manager.updateAppWidget(id, views)
                }
            } catch (e: Exception) {
                Log.w(TAG, "updateAll failed", e)
            }
        }

        private fun openDb(context: Context): SQLiteDatabase? =
            try {
                context.openOrCreateDatabase(
                    "smart_task_assistant.db", Context.MODE_PRIVATE, null
                )
            } catch (e: Exception) {
                Log.w(TAG, "openDb failed", e)
                null
            }

        private fun buildRemoteViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_today)

            val tasks = queryTasks(context)
            val count = tasks.size

            // 头部：今日任务 / 接下来的任务
            val isToday = tasks.isNotEmpty() && tasks.first().third == true
            views.setTextViewText(
                R.id.widget_header_title,
                if (isToday) "今日任务" else "接下来的任务"
            )
            views.setTextViewText(R.id.widget_header_count, "$count 项")

            // 头部点击 → 打开 APP
            val openIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (openIntent != null) {
                val pi = PendingIntent.getActivity(
                    context, 0, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_header, pi)
            }

            // 任务行：最多 MAX_ROWS 条，点击 = 标记完成
            for (i in 0 until MAX_ROWS) {
                val viewId = when (i) {
                    0 -> R.id.widget_task_0
                    1 -> R.id.widget_task_1
                    2 -> R.id.widget_task_2
                    3 -> R.id.widget_task_3
                    else -> R.id.widget_task_4
                }
                if (i < count) {
                    val (id, title, _) = tasks[i]
                    views.setTextViewText(viewId, "○  $title")
                    views.setViewVisibility(viewId, android.view.View.VISIBLE)
                    views.setOnClickPendingIntent(
                        viewId,
                        ReminderActionReceiver.completePendingIntent(context, id)
                    )
                } else {
                    views.setViewVisibility(viewId, android.view.View.GONE)
                }
            }

            // 空状态
            if (count == 0) {
                views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                views.setTextViewText(R.id.widget_empty, "今日没有任务，点击打开 APP 创建")
            } else {
                views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
            }
            return views
        }

        /**
         * 查询小组件任务：优先今天到期的未完成任务；
         * 没有则取接下来（due_time >= 现在）的 5 个未完成任务。
         * 返回 (id, title, isToday) 列表。
         */
        private fun queryTasks(context: Context): List<Triple<String, String, Boolean>> {
            val db = openDb(context) ?: return emptyList()
            return try {
                val todaySql = """
                    SELECT id, title FROM tasks
                    WHERE status IN (0, 1) AND archived_at IS NULL
                      AND reminder_dismissed = 0 AND due_time IS NOT NULL
                      AND date(due_time) = date('now','localtime')
                    ORDER BY priority DESC, due_time ASC LIMIT $MAX_ROWS
                """.trimIndent()
                var rows = queryRows(db, todaySql, isToday = true)
                if (rows.isEmpty()) {
                    val upcomingSql = """
                        SELECT id, title FROM tasks
                        WHERE status IN (0, 1) AND archived_at IS NULL
                          AND reminder_dismissed = 0 AND due_time IS NOT NULL
                          AND due_time >= datetime('now','localtime')
                        ORDER BY due_time ASC LIMIT $MAX_ROWS
                    """.trimIndent()
                    rows = queryRows(db, upcomingSql, isToday = false)
                }
                rows
            } catch (e: Exception) {
                Log.w(TAG, "queryTasks failed", e)
                emptyList()
            } finally {
                db.close()
            }
        }

        private fun queryRows(
            db: SQLiteDatabase,
            sql: String,
            isToday: Boolean
        ): MutableList<Triple<String, String, Boolean>> {
            val result = mutableListOf<Triple<String, String, Boolean>>()
            val cursor = db.rawQuery(sql, null)
            cursor.use {
                while (it.moveToNext() && result.size < MAX_ROWS) {
                    val id = it.getString(0)
                    val title = it.getString(1) ?: continue
                    result.add(Triple(id, title, isToday))
                }
            }
            return result
        }
    }
}
