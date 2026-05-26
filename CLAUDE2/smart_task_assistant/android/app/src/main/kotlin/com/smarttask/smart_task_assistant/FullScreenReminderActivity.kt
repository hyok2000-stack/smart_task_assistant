package com.smarttask.smart_task_assistant

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.text.format.DateFormat
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import android.app.Activity
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

/**
 * 全屏提醒页面：在锁屏/后台时全屏弹出显示任务或习惯提醒
 */
class FullScreenReminderActivity : Activity() {
    companion object {
        private const val TAG = "FullScreenReminder"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var dbHelper: ReminderChecker? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show over lock screen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }

        // Acquire screen wake lock
        acquireWakeLock()

        // Dismiss keyguard
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        }

        dbHelper = ReminderChecker(this)

        // Parse intent extras
        val id = intent.getStringExtra("id") ?: run { finish(); return }
        val type = intent.getStringExtra("type") ?: "task"
        val title = intent.getStringExtra("title") ?: ""
        val body = intent.getStringExtra("body") ?: ""
        val priority = intent.getIntExtra("priority", 1)
        val dueTime = intent.getStringExtra("dueTime") ?: ""
        val assignee = intent.getStringExtra("assignee") ?: ""
        val habitIconCode = intent.getIntExtra("habitIconCode", 0)
        val habitTargetCount = intent.getIntExtra("habitTargetCount", 0)
        val habitCurrentCount = intent.getIntExtra("habitCurrentCount", 0)
        val habitNeedsRecord = intent.getBooleanExtra("habitNeedsRecord", false)

        // Build and set content view
        val contentView = if (type == "task") {
            buildTaskView(id, title, body, priority, dueTime, assignee)
        } else {
            buildHabitView(id, title, body, habitIconCode, habitTargetCount, habitCurrentCount, habitNeedsRecord)
        }
        setContentView(contentView)
    }

    // --- WakeLock ---

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            wakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "FullScreenReminder::Screen"
            )
            wakeLock?.acquire(30_000L) // max 30s
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire screen wake lock", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        wakeLock?.release()
        // Reset isReminderShowing flag in service
        ReminderForegroundService.isReminderShowing = false
    }

    // --- Back press handling ---

    @Deprecated("Use onBackPressedDispatcher")
    override fun onBackPressed() {
        val id = intent.getStringExtra("id") ?: run {
            super.onBackPressed()
            return
        }
        val type = intent.getStringExtra("type") ?: "task"

        if (type == "task") {
            // For tasks: snooze 30 seconds (continual reminder)
            val snoozeUntil = System.currentTimeMillis() + 30_000
            dbHelper?.setSnooze(id, snoozeUntil)
            sendEvent(id, type, "snoozed", 1) // 1分钟≈30秒 continual
        }
        // For habits: just finish

        super.onBackPressed()
    }

    // --- UI Builders ---

    private fun buildTaskView(
        id: String, title: String, body: String,
        priority: Int, dueTime: String, assignee: String
    ): View {
        val context = this
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(48), dp(32), dp(48))
            // Gradient background
            background = createGradientBackground()
        }

        // Notification icon
        root.addView(ImageView(context).apply {
            setImageResource(R.mipmap.ic_launcher)
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56)).apply {
                bottomMargin = dp(24)
            }
        })

        // Priority badge
        val badgeText = when (priority) {
            2 -> "紧急"
            1 -> "中等"
            else -> "普通"
        }
        val badgeColor = when (priority) {
            2 -> Color.parseColor("#DC2626") // Red600
            1 -> Color.parseColor("#EA580C") // Orange600
            else -> Color.parseColor("#059669") // Emerald600
        }

        root.addView(TextView(context).apply {
            text = badgeText
            setTextColor(Color.WHITE)
            setBackgroundColor(badgeColor)
            setPadding(dp(12), dp(4), dp(12), dp(4))
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(16) }
        })

        // Task title (clickable → edit task in Flutter)
        root.addView(TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
            setOnClickListener { openTaskEdit(id, "task") }
        })

        // Due time
        if (dueTime.isNotEmpty()) {
            root.addView(TextView(context).apply {
                text = formatDueTime(dueTime)
                setTextColor(Color.parseColor("#B0BEC5"))
                textSize = 14f
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(4) }
            })
        }

        // Assignee
        if (assignee.isNotEmpty()) {
            root.addView(TextView(context).apply {
                text = "负责人: $assignee"
                setTextColor(Color.parseColor("#B0BEC5"))
                textSize = 14f
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(24) }
            })
        }

        // Spacer
        root.addView(View(context), LinearLayout.LayoutParams(0, dp(16)))

        // Action buttons
        val buttonContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Snooze buttons
        for ((label, minutes) in listOf("10分钟后" to 10, "30分钟后" to 30, "1小时后" to 60)) {
            buttonContainer.addView(createButton(label, Color.parseColor("#4F46E5")) {
                val snoozeUntil = System.currentTimeMillis() + minutes * 60_000L
                dbHelper?.setSnooze(id, snoozeUntil)
                sendEvent(id, "task", "snoozed", minutes)
                finish()
            })
        }

        root.addView(buttonContainer)

        // Dismiss button
        root.addView(createButton("不再提醒", Color.parseColor("#DC2626")) {
            dismissTaskReminder(id)
            sendEvent(id, "task", "dismissed", 0)
            finish()
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(12) })

        val scrollView = ScrollView(context)
        scrollView.addView(root)
        return scrollView
    }

    private fun buildHabitView(
        id: String, title: String, body: String,
        iconCode: Int, targetCount: Int, currentCount: Int,
        needsRecord: Boolean
    ): View {
        val context = this
        val isClockHabit = id == "habit_clock_in" || id == "habit_clock_out"

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(48), dp(32), dp(48))
            background = createGradientBackground()
        }

        // Habit icon with colored background
        val habitColor = when (id) {
            "habit_water" -> Color.parseColor("#3B82F6")    // Blue
            "habit_stretch" -> Color.parseColor("#10B981")  // Green
            "habit_clock_in" -> Color.parseColor("#F59E0B") // Amber
            "habit_clock_out" -> Color.parseColor("#EF4444")// Red
            else -> Color.parseColor("#6366F1")             // Indigo
        }

        val iconContainer = FrameLayout(context).apply {
            setBackgroundColor(habitColor)
            layoutParams = LinearLayout.LayoutParams(dp(64), dp(64)).apply {
                bottomMargin = dp(20)
            }
        }
        val emoji = String(Character.toChars(iconCode))
        iconContainer.addView(TextView(context).apply {
            text = emoji
            textSize = 32f
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        })
        root.addView(iconContainer)

        // Habit title (clickable → edit in Flutter)
        root.addView(TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
            setOnClickListener { openTaskEdit(id, "habit") }
        })

        // Reminder text (voice text or body)
        if (body.isNotEmpty()) {
            root.addView(TextView(context).apply {
                text = body
                setTextColor(Color.parseColor("#B0BEC5"))
                textSize = 16f
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(16) }
            })
        }

        // Progress bar for non-clock habits
        if (!isClockHabit && needsRecord && targetCount > 0) {
            val progressLayout = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(16) }
            }

            progressLayout.addView(TextView(context).apply {
                text = "今日进度: $currentCount/$targetCount"
                setTextColor(Color.WHITE)
                textSize = 14f
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(8) }
            })

            // Simple progress bar using ProgressBar
            val progressBar = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = targetCount
                progress = currentCount
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(8)
                )
            }
            progressLayout.addView(progressBar)
            root.addView(progressLayout)
        }

        // Action buttons
        if (isClockHabit) {
            // Clock habits: only "知道了"
            root.addView(createButton("知道了", Color.parseColor("#4F46E5")) {
                sendEvent(id, "habit", "shown", 0)
                finish()
            })
        } else if (needsRecord) {
            // Activity habits: "不再提醒" + "已完成" + snooze options

            // Top row: 不再提醒 + 已完成
            val topRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(12) }
            }

            topRow.addView(createButton("不再提醒", Color.parseColor("#DC2626")) {
                sendEvent(id, "habit", "dismissed", 0)
                finish()
            })

            topRow.addView(createButton("已完成", Color.parseColor("#059669")) {
                completeHabit(id)
                sendEvent(id, "habit", "completed", 0)
                finish()
            })
            root.addView(topRow)

            // Bottom row: snooze options
            val snoozeRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
            }
            for ((label, minutes) in listOf("5分钟后" to 5, "15分钟后" to 15, "30分钟后" to 30)) {
                snoozeRow.addView(createButton(label, Color.parseColor("#4F46E5")) {
                    val snoozeUntil = System.currentTimeMillis() + minutes * 60_000L
                    dbHelper?.setSnooze(id, snoozeUntil)
                    sendEvent(id, "habit", "snoozed", minutes)
                    finish()
                })
            }
            root.addView(snoozeRow)
        } else {
            // No-record non-clock habits: "知道了"
            root.addView(createButton("知道了", Color.parseColor("#4F46E5")) {
                finish()
            })
        }

        val scrollView = ScrollView(context)
        scrollView.addView(root)
        return scrollView
    }

    // --- Helpers ---

    private fun createButton(text: String, bgColor: Int, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            setBackgroundColor(bgColor)
            setPadding(dp(16), dp(8), dp(16), dp(8))
            textSize = 14f
            isAllCaps = false
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(4)
                marginEnd = dp(4)
            }
            setOnClickListener { onClick() }
        }
    }

    private fun createGradientBackground(): android.graphics.drawable.GradientDrawable {
        return android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.parseColor("#667EEA"), Color.parseColor("#764BA2"))
        )
    }

    private fun formatDueTime(dueTimeStr: String): String {
        return try {
            val inputFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            val date = inputFormat.parse(dueTimeStr) ?: return dueTimeStr
            val outputFormat = SimpleDateFormat("MM月dd日 HH:mm", Locale.getDefault())
            "截止时间: ${outputFormat.format(date)}"
        } catch (e: Exception) {
            try {
                val inputFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
                val date = inputFormat.parse(dueTimeStr) ?: return dueTimeStr
                val outputFormat = SimpleDateFormat("MM月dd日 HH:mm", Locale.getDefault())
                "截止时间: ${outputFormat.format(date)}"
            } catch (e2: Exception) {
                "截止时间: $dueTimeStr"
            }
        }
    }

    // --- DB operations ---

    private fun dismissTaskReminder(taskId: String) {
        try {
            val dbFile = getDatabasePath("smart_task_assistant.db")
            if (!dbFile.exists()) return
            val db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null,
                SQLiteDatabase.OPEN_READWRITE
            )
            db.use {
                it.execSQL("UPDATE tasks SET reminder_dismissed = 1 WHERE id = ?", arrayOf(taskId))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dismiss task reminder in DB", e)
        }
        dbHelper?.clearTaskState(taskId)
    }

    private fun completeHabit(habitId: String) {
        try {
            val dbFile = getDatabasePath("smart_task_assistant.db")
            if (!dbFile.exists()) return
            val db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null,
                SQLiteDatabase.OPEN_READWRITE
            )
            db.use {
                val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
                    .format(Date())
                it.execSQL(
                    "INSERT INTO habit_logs (id, habit_id, count, status, completed_at) VALUES (?, ?, 1, 0, ?)",
                    arrayOf("log_${System.currentTimeMillis()}", habitId, now)
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to log habit completion in DB", e)
        }
    }

    // --- Navigate to Flutter edit page ---

    /**
     * 点击标题：发送 edit 事件给 Flutter 并跳回 APP
     */
    private fun openTaskEdit(id: String, type: String) {
        // Send edit event to Flutter via bridge
        val json = JSONObject().apply {
            put("id", id)
            put("type", type)
            put("action", "edit")
        }
        ReminderBridge.getInstance().sendEvent(json.toString())

        // Bring Flutter app to foreground
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            launchIntent.putExtra("edit_id", id)
            launchIntent.putExtra("edit_type", type)
            startActivity(launchIntent)
        }

        finish()
    }

    // --- Event sending ---

    private fun sendEvent(id: String, type: String, action: String, snoozeMinutes: Int) {
        val json = JSONObject().apply {
            put("id", id)
            put("type", type)
            put("action", action)
            if (snoozeMinutes > 0) {
                put("snoozeMinutes", snoozeMinutes)
            }
        }
        ReminderBridge.getInstance().sendEvent(json.toString())
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
