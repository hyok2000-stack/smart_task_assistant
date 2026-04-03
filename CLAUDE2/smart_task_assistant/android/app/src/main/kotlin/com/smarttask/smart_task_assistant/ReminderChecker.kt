package com.smarttask.smart_task_assistant

import android.content.Context
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File
import android.text.TextUtils
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.*
import java.util.regex.Pattern

/**
 * 提醒检查器：从 SQLite 数据库查询任务和习惯，判断是否需要触发提醒
 */
class ReminderChecker(private val context: Context) {
    companion object {
        private const val TAG = "ReminderChecker"
        private const val SP_NAME = "reminder_state"
        private const val KEY_FIRST_SENT = "first_sent_%s"
        private const val KEY_LAST_REMIND = "last_remind_%s"
        private const val KEY_SNOOZE = "snooze_%s"
        private const val KEY_HABIT_FIXED = "habit_fixed_%s_%s"
        private const val KEY_HABIT_LAST = "habit_last_%s"
        private const val KEY_LAST_CLEANUP = "last_cleanup"
        private const val CONTINUAL_INTERVAL = 30_000L // 30s
        private const val DEADLINE_CUTOFF = 3_600_000L // 1h after deadline
    }

    private val sp: SharedPreferences =
        context.getSharedPreferences(SP_NAME, Context.MODE_PRIVATE)

    // Flutter SharedPreferences uses "FlutterSharedPreferences" file with "flutter." prefix
    private val flutterPrefs: SharedPreferences? =
        try { context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE) } catch (_: Exception) { null }

    // --- Data classes ---

    data class TaskRow(
        val id: String,
        val title: String,
        val content: String?,
        val status: Int,
        val priority: Int,
        val dueTime: String?,
        val reminderMinutes: Int?,
        val reminderDismissed: Int,
        val voiceEnabled: Int,
        val voiceType: String?,
        val voiceStyle: String?,
        val voiceSpeed: String?,
        val customVoicePath: String?,
        val assignee: String?,
        val soundEnabled: Boolean,
        val vibrationEnabled: Boolean
    )

    data class HabitRow(
        val id: String,
        val title: String,
        val targetCount: Int,
        val unit: String,
        val triggerType: String,
        val intervalMinutes: Int?,
        val fixedTime: String?,
        val scheduleType: String,
        val iconCode: Int,
        val soundEnabled: Int,
        val vibrationEnabled: Int,
        val voiceEnabled: Int,
        val voiceText: String?,
        val voiceType: String?,
        val voiceStyle: String?,
        val voiceSpeed: String?,
        val customVoicePath: String?,
        val referenceTime: String?,
        val advanceMinutes: Int?
    )

    data class ReminderItem(
        val id: String,
        val type: String, // "task" or "habit"
        val title: String,
        val body: String?,
        val priority: Int, // for tasks; for habits default 1
        val dueTime: String?,
        val assignee: String?,
        val habitIconCode: Int,
        val habitTargetCount: Int,
        val habitCurrentCount: Int,
        val habitNeedsRecord: Boolean,
        val voiceEnabled: Boolean,
        val voiceText: String?,
        val voiceType: String?,
        val voiceStyle: String?,
        val voiceSpeed: String?,
        val customVoicePath: String?,
        val soundEnabled: Boolean,
        val vibrationEnabled: Boolean
    )

    // --- DB access ---

    private fun openDb(): SQLiteDatabase? {
        return try {
            val dbFile = context.getDatabasePath("smart_task_assistant.db")
            if (!dbFile.exists()) {
                Log.w(TAG, "Database file not found: ${dbFile.absolutePath}")
                return null
            }
            SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null,
                SQLiteDatabase.OPEN_READONLY
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open database", e)
            null
        }
    }

    // --- Queries ---

    fun queryActiveTasks(db: SQLiteDatabase): List<TaskRow> {
        val tasks = mutableListOf<TaskRow>()
        // Read global sound/vibration settings from Flutter SharedPreferences
        val soundEnabled = flutterPrefs?.getBoolean("flutter.reminderSoundEnabled", true) ?: true
        val vibrationEnabled = flutterPrefs?.getBoolean("flutter.reminderVibrationEnabled", true) ?: true
        Log.d(TAG, "Global reminder settings: sound=$soundEnabled, vibration=$vibrationEnabled")
        val cursor = db.rawQuery(
            """SELECT id, title, content, status, priority, due_time, reminder_minutes,
               reminder_dismissed, reminder_voice_enabled, reminder_voice_type,
               reminder_voice_style, reminder_voice_speed, reminder_custom_voice_path, assignee
               FROM tasks
               WHERE status IN (0, 1)
                 AND reminder_dismissed = 0
                 AND reminder_minutes IS NOT NULL
                 AND due_time IS NOT NULL""",
            null
        )
        cursor.use {
            while (it.moveToNext()) {
                tasks.add(
                    TaskRow(
                        id = it.getString(0),
                        title = it.getString(1),
                        content = it.getString(2),
                        status = it.getInt(3),
                        priority = it.getInt(4),
                        dueTime = it.getString(5),
                        reminderMinutes = if (it.isNull(6)) null else it.getInt(6),
                        reminderDismissed = it.getInt(7),
                        voiceEnabled = it.getInt(8),
                        voiceType = it.getString(9),
                        voiceStyle = it.getString(10),
                        voiceSpeed = it.getString(11),
                        customVoicePath = it.getString(12),
                        assignee = it.getString(13),
                        soundEnabled = soundEnabled,
                        vibrationEnabled = vibrationEnabled
                    )
                )
            }
        }
        return tasks
    }

    fun queryEnabledHabits(db: SQLiteDatabase): List<HabitRow> {
        val habits = mutableListOf<HabitRow>()
        val cursor = db.rawQuery("SELECT * FROM habits WHERE is_enabled = 1", null)
        cursor.use {
            while (it.moveToNext()) {
                habits.add(
                    HabitRow(
                        id = it.getString(it.getColumnIndexOrThrow("id")),
                        title = it.getString(it.getColumnIndexOrThrow("title")),
                        targetCount = it.getInt(it.getColumnIndexOrThrow("target_count")),
                        unit = it.getString(it.getColumnIndexOrThrow("unit")),
                        triggerType = it.getString(it.getColumnIndexOrThrow("trigger_type")),
                        intervalMinutes = if (it.isNull(it.getColumnIndexOrThrow("interval_minutes"))) null else it.getInt(it.getColumnIndexOrThrow("interval_minutes")),
                        fixedTime = it.getString(it.getColumnIndexOrThrow("fixed_time")),
                        scheduleType = it.getString(it.getColumnIndexOrThrow("schedule_type")),
                        iconCode = it.getInt(it.getColumnIndexOrThrow("icon_code")),
                        soundEnabled = it.getInt(it.getColumnIndexOrThrow("sound_enabled")),
                        vibrationEnabled = it.getInt(it.getColumnIndexOrThrow("vibration_enabled")),
                        voiceEnabled = it.getInt(it.getColumnIndexOrThrow("voice_enabled")),
                        voiceText = it.getString(it.getColumnIndexOrThrow("voice_text")),
                        voiceType = it.getString(it.getColumnIndexOrThrow("voice_type")),
                        voiceStyle = it.getString(it.getColumnIndexOrThrow("voice_style")),
                        voiceSpeed = it.getString(it.getColumnIndexOrThrow("voice_speed")),
                        customVoicePath = it.getString(it.getColumnIndexOrThrow("custom_voice_path")),
                        referenceTime = it.getString(it.getColumnIndexOrThrow("reference_time")),
                        advanceMinutes = if (it.isNull(it.getColumnIndexOrThrow("advance_minutes"))) null else it.getInt(it.getColumnIndexOrThrow("advance_minutes"))
                    )
                )
            }
        }
        return habits
    }

    fun queryWorkTimeRange(db: SQLiteDatabase): Pair<Int, Int> {
        // Query clock_in and clock_out habits for reference_time
        var startHour = 9
        var endHour = 18
        val cursor = db.rawQuery(
            "SELECT id, reference_time FROM habits WHERE id IN ('habit_clock_in', 'habit_clock_out') AND reference_time IS NOT NULL",
            null
        )
        cursor.use {
            while (it.moveToNext()) {
                val id = it.getString(0)
                val refTime = it.getString(1) ?: continue
                val parts = refTime.split(":")
                if (parts.size >= 2) {
                    val hour = parts[0].toIntOrNull() ?: continue
                    if (id == "habit_clock_in") startHour = hour
                    if (id == "habit_clock_out") endHour = hour
                }
            }
        }
        return Pair(startHour, endHour)
    }

    private fun queryHabitTodayCount(db: SQLiteDatabase, habitId: String): Int {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val cursor = db.rawQuery(
            "SELECT COUNT(*) FROM habit_logs WHERE habit_id = ? AND date(completed_at) = ?",
            arrayOf(habitId, today)
        )
        cursor.use {
            if (it.moveToFirst()) return it.getInt(0)
        }
        return 0
    }

    // --- Time helpers ---

    /**
     * ISO 8601 日期时间正则：提取年月日时分秒，忽略小数位数和时区后缀
     * 兼容 Dart DateTime.toIso8601String() 的所有输出格式：
     * - 2024-01-15T10:30:00.000
     * - 2024-01-15T10:30:00.123456
     * - 2024-01-15T10:30:00
     * - 2024-01-15T10:30:00.000Z
     * - 2024-01-15T10:30:00.000+08:00
     * - 2024-01-15 10:30:00
     */
    private val ISO_DATETIME_REGEX: Pattern =
        Pattern.compile("""(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})""")

    private fun parseDueTimeMillis(dueTimeStr: String): Long? {
        // ---- 首选：正则提取，忽略小数秒和时区后缀 ----
        val matcher = ISO_DATETIME_REGEX.matcher(dueTimeStr)
        if (matcher.find()) {
            try {
                val year = matcher.group(1)!!.toInt()
                val month = matcher.group(2)!!.toInt()
                val day = matcher.group(3)!!.toInt()
                val hour = matcher.group(4)!!.toInt()
                val minute = matcher.group(5)!!.toInt()
                val second = matcher.group(6)!!.toInt()
                val cal = Calendar.getInstance().apply {
                    set(Calendar.YEAR, year)
                    set(Calendar.MONTH, month - 1)
                    set(Calendar.DAY_OF_MONTH, day)
                    set(Calendar.HOUR_OF_DAY, hour)
                    set(Calendar.MINUTE, minute)
                    set(Calendar.SECOND, second)
                    set(Calendar.MILLISECOND, 0)
                }
                return cal.timeInMillis
            } catch (e: Exception) {
                Log.w(TAG, "Regex extraction failed for due_time: $dueTimeStr", e)
            }
        }

        // ---- 降级：原有 SimpleDateFormat 链 ----
        val formats = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
        )
        for (pattern in formats) {
            try {
                val sdf = SimpleDateFormat(pattern, Locale.US)
                sdf.timeZone = TimeZone.getDefault()
                sdf.isLenient = false
                val pos = ParsePosition(0)
                val date = sdf.parse(dueTimeStr, pos)
                if (date != null && pos.index == dueTimeStr.length) {
                    return date.time
                }
            } catch (_: Exception) {
                // try next format
            }
        }
        // Last resort: lenient parsing
        try {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            sdf.timeZone = TimeZone.getDefault()
            sdf.isLenient = true
            return sdf.parse(dueTimeStr)?.time
        } catch (_: Exception) {}

        Log.w(TAG, "Cannot parse due_time: $dueTimeStr")
        return null
    }

    private fun parseTimeToTodayMillis(timeStr: String): Long? {
        return try {
            val parts = timeStr.split(":")
            if (parts.size < 2) return null
            val hour = parts[0].toIntOrNull() ?: return null
            val minute = parts[1].toIntOrNull() ?: return null
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, hour)
            cal.set(Calendar.MINUTE, minute)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            cal.timeInMillis
        } catch (e: Exception) {
            null
        }
    }

    private fun isTodayScheduleMatch(scheduleType: String, now: Calendar): Boolean {
        val dow = now.get(Calendar.DAY_OF_WEEK)
        return when (scheduleType) {
            "weekdays" -> dow in Calendar.MONDAY..Calendar.FRIDAY
            "daily" -> true
            else -> true
        }
    }

    // --- Task reminder logic ---

    fun shouldTriggerTask(task: TaskRow, now: Long): Boolean {
        val dueTime = parseDueTimeMillis(task.dueTime ?: return false) ?: run {
            Log.d(TAG, "shouldTriggerTask[${task.title}]: parseDueTime FAILED, raw=${task.dueTime}")
            return false
        }

        // Check snooze first
        val snoozeUntil = sp.getLong(String.format(KEY_SNOOZE, task.id), 0)
        if (snoozeUntil > 0 && now < snoozeUntil) {
            Log.d(TAG, "shouldTriggerTask[${task.title}]: snoozing until $snoozeUntil")
            return false // still snoozing
        }

        // Calculate reminder time
        val reminderTime = dueTime - (task.reminderMinutes?.toLong()?.times(60_000) ?: return false)

        // Already past deadline + cutoff
        if (now > dueTime + DEADLINE_CUTOFF) {
            Log.d(TAG, "shouldTriggerTask[${task.title}]: past deadline+cutoff, due=${dueTime}, now=${now}")
            return false
        }

        val firstSentKey = String.format(KEY_FIRST_SENT, task.id)
        val lastRemindKey = String.format(KEY_LAST_REMIND, task.id)

        // First reminder check
        if (!sp.contains(firstSentKey)) {
            val trigger = now >= reminderTime
            Log.d(TAG, "shouldTriggerTask[${task.title}]: first check, reminderTime=${reminderTime}, now=${now}, trigger=${trigger}")
            return trigger
        }

        // Continual reminder check (every 30s)
        val lastRemind = sp.getLong(lastRemindKey, 0)
        val trigger = now >= lastRemind + CONTINUAL_INTERVAL
        Log.d(TAG, "shouldTriggerTask[${task.title}]: continual check, lastRemind=${lastRemind}, trigger=${trigger}")
        return trigger
    }

    // --- Habit fixed-time logic ---

    fun shouldTriggerFixedHabit(habit: HabitRow, now: Long): Boolean {
        val cal = Calendar.getInstance().apply { timeInMillis = now }
        if (!isTodayScheduleMatch(habit.scheduleType, cal)) return false

        val triggerTimeStr: String
        if (habit.id == "habit_clock_in" || habit.id == "habit_clock_out") {
            // Clock habits: reference_time + advance_minutes
            val refTime = habit.referenceTime ?: return false
            val parts = refTime.split(":")
            if (parts.size < 2) return false
            val hour = parts[0].toIntOrNull() ?: return false
            val minute = parts[1].toIntOrNull() ?: return false
            val advance = habit.advanceMinutes ?: 0
            val totalMinutes = hour * 60 + minute - advance
            val triggerHour = totalMinutes / 60
            val triggerMinute = totalMinutes % 60
            triggerTimeStr = String.format("%02d:%02d", triggerHour, triggerMinute)
        } else {
            triggerTimeStr = habit.fixedTime ?: return false
        }

        val triggerMillis = parseTimeToTodayMillis(triggerTimeStr) ?: return false

        // ±1 minute window
        if (now < triggerMillis - 60_000 || now > triggerMillis + 60_000) return false

        // Today-already-triggered guard
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
        val fixedKey = String.format(KEY_HABIT_FIXED, habit.id, today)
        if (sp.getBoolean(fixedKey, false)) return false

        return true
    }

    // --- Habit interval logic ---

    fun shouldTriggerIntervalHabit(habit: HabitRow, workStart: Int, workEnd: Int, now: Long): Boolean {
        val cal = Calendar.getInstance().apply { timeInMillis = now }
        if (!isTodayScheduleMatch(habit.scheduleType, cal)) return false

        val interval = habit.intervalMinutes ?: return false
        if (interval <= 0) return false

        val currentHour = cal.get(Calendar.HOUR_OF_DAY)
        if (currentHour < workStart || currentHour >= workEnd) return false

        // Generate trigger times: workStart:00, workStart:00 + interval, ...
        val workStartMinutes = workStart * 60
        val currentMinutes = currentHour * 60 + cal.get(Calendar.MINUTE)
        val intervalsPassed = (currentMinutes - workStartMinutes) / interval
        val triggerMinutes = workStartMinutes + intervalsPassed * interval

        if (triggerMinutes < workStartMinutes) return false

        val triggerCal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, triggerMinutes / 60)
            set(Calendar.MINUTE, triggerMinutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val triggerMillis = triggerCal.timeInMillis

        // ±1 minute window
        if (now < triggerMillis - 60_000 || now > triggerMillis + 60_000) return false

        // SP guard: check if already triggered for this interval
        val lastKey = String.format(KEY_HABIT_LAST, habit.id)
        val lastTrigger = sp.getLong(lastKey, 0)
        if (lastTrigger > 0 && Math.abs(lastTrigger - triggerMillis) < 60_000) {
            return false // already triggered at this interval
        }

        return true
    }

    // --- SP state management ---

    fun markFirstSent(id: String) {
        sp.edit().putLong(String.format(KEY_FIRST_SENT, id), System.currentTimeMillis()).apply()
    }

    fun markLastRemind(id: String) {
        sp.edit().putLong(String.format(KEY_LAST_REMIND, id), System.currentTimeMillis()).apply()
    }

    fun setSnooze(id: String, snoozeUntil: Long) {
        sp.edit().putLong(String.format(KEY_SNOOZE, id), snoozeUntil).apply()
    }

    fun clearTaskState(id: String) {
        val keys = listOf(
            String.format(KEY_FIRST_SENT, id),
            String.format(KEY_LAST_REMIND, id),
            String.format(KEY_SNOOZE, id),
            String.format(KEY_HABIT_LAST, id)
        )
        sp.edit().apply {
            keys.forEach { remove(it) }
            // Also remove habit_fixed_{id}_* entries
            for ((key, _) in sp.all) {
                if (key.startsWith("habit_fixed_${id}_")) {
                    remove(key)
                }
            }
            apply()
        }
    }

    fun markHabitTriggered(id: String) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        sp.edit()
            .putBoolean(String.format(KEY_HABIT_FIXED, id, today), true)
            .putLong(String.format(KEY_HABIT_LAST, id), System.currentTimeMillis())
            .apply()
    }

    fun isHabitTriggeredInWindow(id: String): Boolean {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        return sp.getBoolean(String.format(KEY_HABIT_FIXED, id, today), false)
    }

    fun cleanupStaleState() {
        val lastCleanup = sp.getLong(KEY_LAST_CLEANUP, 0)
        val now = System.currentTimeMillis()
        if (now - lastCleanup < 3_600_000) return // hourly

        val dayAgo = now - 86_400_000L
        sp.edit().apply {
            for ((key, value) in sp.all) {
                if (value is Long && value < dayAgo) {
                    remove(key)
                }
            }
            putLong(KEY_LAST_CLEANUP, now)
            apply()
        }
    }

    fun refreshData(type: String, id: String?) {
        if (type == "all") {
            sp.edit().clear().apply()
        } else if (id != null) {
            clearTaskState(id)
        }
    }

    // --- Main entry ---

    fun checkAll(): List<ReminderItem> {
        val items = mutableListOf<ReminderItem>()
        val db = openDb() ?: return items

        try {
            val now = System.currentTimeMillis()

            // Cleanup stale state periodically
            cleanupStaleState()

            // Check tasks
            val tasks = queryActiveTasks(db)
            Log.d(TAG, "Found ${tasks.size} active tasks for reminder check")
            for (task in tasks) {
                if (shouldTriggerTask(task, now)) {
                    markFirstSent(task.id)
                    markLastRemind(task.id)
                    items.add(
                        ReminderItem(
                            id = task.id,
                            type = "task",
                            title = task.title,
                            body = task.content,
                            priority = task.priority,
                            dueTime = task.dueTime,
                            assignee = task.assignee,
                            habitIconCode = 0,
                            habitTargetCount = 0,
                            habitCurrentCount = 0,
                            habitNeedsRecord = false,
                            voiceEnabled = task.voiceEnabled == 1,
                            voiceText = null,
                            voiceType = task.voiceType,
                            voiceStyle = task.voiceStyle,
                            voiceSpeed = task.voiceSpeed,
                            customVoicePath = task.customVoicePath,
                            soundEnabled = task.soundEnabled,
                            vibrationEnabled = task.vibrationEnabled
                        )
                    )
                }
            }

            // Check habits
            val habits = queryEnabledHabits(db)
            val (workStart, workEnd) = queryWorkTimeRange(db)

            for (habit in habits) {
                val triggered = when (habit.triggerType) {
                    "fixed" -> shouldTriggerFixedHabit(habit, now)
                    "interval" -> shouldTriggerIntervalHabit(habit, workStart, workEnd, now)
                    else -> false
                }

                if (triggered) {
                    markHabitTriggered(habit.id)
                    val needsRecord = habit.id != "habit_clock_in" && habit.id != "habit_clock_out"
                    val currentCount = if (needsRecord) queryHabitTodayCount(db, habit.id) else 0

                    items.add(
                        ReminderItem(
                            id = habit.id,
                            type = "habit",
                            title = habit.title,
                            body = habit.voiceText,
                            priority = 1,
                            dueTime = null,
                            assignee = null,
                            habitIconCode = habit.iconCode,
                            habitTargetCount = habit.targetCount,
                            habitCurrentCount = currentCount,
                            habitNeedsRecord = needsRecord,
                            voiceEnabled = habit.voiceEnabled == 1,
                            voiceText = habit.voiceText,
                            voiceType = habit.voiceType,
                            voiceStyle = habit.voiceStyle,
                            voiceSpeed = habit.voiceSpeed,
                            customVoicePath = habit.customVoicePath,
                            soundEnabled = habit.soundEnabled == 1,
                            vibrationEnabled = habit.vibrationEnabled == 1
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in checkAll()", e)
        } finally {
            db.close()
        }

        return items
    }
}
