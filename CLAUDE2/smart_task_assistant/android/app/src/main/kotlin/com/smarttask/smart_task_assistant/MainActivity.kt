package com.smarttask.smart_task_assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.smarttask.smart_task_assistant/clipboard_service"
    private val EVENT_CHANNEL = "com.smarttask.smart_task_assistant/clipboard_monitor"
    
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    
    // 剪贴板变化广播接收器
    private val clipboardReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.smarttask.smart_task_assistant.CLIPBOARD_CHANGED") {
                val content = intent.getStringExtra("content")
                if (content != null) {
                    // 通过EventChannel发送到Flutter层
                    eventSink?.success(content)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 设置MethodChannel - 用于启动/停止服务
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        ClipboardMonitorService.startService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                    }
                }
                "stopService" -> {
                    try {
                        ClipboardMonitorService.stopService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop service: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // 设置EventChannel - 用于接收剪贴板变化事件
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // 注册广播接收器
                val filter = IntentFilter("com.smarttask.smart_task_assistant.CLIPBOARD_CHANGED")
                registerReceiver(clipboardReceiver, filter)
            }
            
            override fun onCancel(arguments: Any?) {
                eventSink = null
                // 注销广播接收器
                try {
                    unregisterReceiver(clipboardReceiver)
                } catch (e: Exception) {
                    // 忽略未注册的异常
                }
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        // 清理EventChannel
        eventChannel?.setStreamHandler(null)
        // 注销广播接收器
        try {
            unregisterReceiver(clipboardReceiver)
        } catch (e: Exception) {
            // 忽略未注册的异常
        }
    }
}