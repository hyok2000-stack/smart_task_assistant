package com.smarttask.smart_task_assistant

import android.app.*
import android.content.*
import android.os.*
import android.content.ClipboardManager
import android.util.Log
import androidx.core.app.NotificationCompat

class ClipboardMonitorService : Service() {
    private val TAG = "ClipboardMonitorService"
    
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var lastClipboardContent: String? = null
    
    private val handler = Handler(Looper.getMainLooper())
    private var monitorRunnable: Runnable? = null
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "ClipboardMonitorService created")
        
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        
        // 创建剪贴板监听器
        clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
            handleClipboardChange()
        }
        
        // 显示前台服务通知
        startForegroundService()
    }
    
    private fun startForegroundService() {
        val channelId = "clipboard_monitor_channel"
        val channelName = "剪贴板监控服务"
        
        // 创建通知渠道（Android 8.0+）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "用于监控剪贴板变化，自动识别任务内容"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
        
        // 创建通知 - 使用 mipmap_launcher
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("剪贴板监控中")
            .setContentText("监控剪贴板变化，自动识别任务内容")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
        
        // 启动前台服务
        startForeground(1, notification)
    }
    
    private fun handleClipboardChange() {
        val clip = clipboardManager?.primaryClip
        if (clip != null && clip.itemCount > 0) {
            val text = clip.getItemAt(0).text?.toString()
            
            if (!text.isNullOrEmpty() && text != lastClipboardContent) {
                lastClipboardContent = text
                Log.d(TAG, "Clipboard changed: $text")
                
                // 发送广播通知 Flutter 层
                val intent = Intent("com.smarttask.smart_task_assistant.CLIPBOARD_CHANGED")
                intent.putExtra("content", text)
                sendBroadcast(intent)
            }
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "ClipboardMonitorService started")
        
        // 注册剪贴板监听器
        clipboardManager?.addPrimaryClipChangedListener(clipboardListener)
        
        // 启动定期检查（备用方案）
        startPeriodicCheck()
        
        return START_STICKY
    }
    
    private fun startPeriodicCheck() {
        monitorRunnable = object : Runnable {
            override fun run() {
                handleClipboardChange()
                handler.postDelayed(this, 2000) // 每2秒检查一次
            }
        }
        handler.post(monitorRunnable!!)
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "ClipboardMonitorService destroyed")
        
        // 移除监听器
        clipboardManager?.removePrimaryClipChangedListener(clipboardListener)
        
        // 停止定期检查
        monitorRunnable?.let { handler.removeCallbacks(it) }
    }
    
    companion object {
        fun startService(context: Context) {
            val intent = Intent(context, ClipboardMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, ClipboardMonitorService::class.java)
            context.stopService(intent)
        }
    }
}