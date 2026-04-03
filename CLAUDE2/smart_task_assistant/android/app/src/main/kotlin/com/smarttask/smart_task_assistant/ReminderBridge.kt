package com.smarttask.smart_task_assistant

import android.util.Log
import org.json.JSONObject

/**
 * 单例桥接器：用于 Service/Activity 与 Flutter EventChannel 之间的事件传递
 * 支持缓冲（最多 10 条），在 Flutter 未监听时暂存事件
 */
class ReminderBridge {
    companion object {
        private const val TAG = "ReminderBridge"
        private const val MAX_BUFFER = 10

        @Volatile
        private var instance: ReminderBridge? = null

        fun getInstance(): ReminderBridge {
            return instance ?: synchronized(this) {
                instance ?: ReminderBridge().also { instance = it }
            }
        }
    }

    private val buffer = mutableListOf<String>()

    @Volatile
    var eventSink: ((String) -> Unit)? = null

    /**
     * 发送事件到 Flutter 层；如果 Flutter 未监听，存入缓冲
     */
    fun sendEvent(eventJson: String) {
        synchronized(buffer) {
            if (eventSink != null) {
                try {
                    eventSink!!(eventJson)
                    return
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to send event directly, buffering", e)
                }
            }
            // Buffer for later
            if (buffer.size >= MAX_BUFFER) {
                buffer.removeAt(0)
            }
            buffer.add(eventJson)
        }
    }

    /**
     * 当 Flutter EventChannel 重新连接时，回放缓冲事件
     */
    fun drainBuffer(): List<String> {
        synchronized(buffer) {
            val events = buffer.toList()
            buffer.clear()
            return events
        }
    }

    fun clearBuffer() {
        synchronized(buffer) {
            buffer.clear()
        }
    }
}
