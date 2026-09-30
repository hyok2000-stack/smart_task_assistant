package com.smarttask.smart_task_assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * 提醒音频辅助：播放通知音、振动、自定义语音文件
 */
class ReminderAudioHelper(private val context: Context) {
    companion object {
        private const val TAG = "ReminderAudioHelper"
        private const val SOUND_DIR = "sounds"
        private const val SOUND_FILE = "notification.mp3"
    }

    private val alarmAudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    // STREAM_ALARM 被静音时的兜底：走媒体音量（用户听音乐/视频的音量）
    private val mediaAudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    private val speechAudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val audioManager = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null

    private fun requestAlarmAudioFocus() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(alarmAudioAttributes)
                    .setOnAudioFocusChangeListener { }
                    .build()
                audioManager.requestAudioFocus(audioFocusRequest!!)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
            }
            Log.d(TAG, "Alarm audio focus requested")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to request alarm audio focus", e)
        }
    }

    private fun abandonAlarmAudioFocus() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                audioManager.abandonAudioFocusRequest(audioFocusRequest!!)
                audioFocusRequest = null
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
        } catch (_: Exception) {}
    }

    /**
     * 提取 assets/sounds/notification.mp3 到 filesDir/sounds/（仅首次）
     * 返回目标文件路径，如果不存在返回 null
     */
    private fun ensureSoundFile(): File? {
        val soundDir = File(context.filesDir, SOUND_DIR)
        val targetFile = File(soundDir, SOUND_FILE)
        if (targetFile.exists() && targetFile.length() > 0) return targetFile

        try {
            soundDir.mkdirs()
            context.assets.open("sounds/$SOUND_FILE").use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            Log.d(TAG, "Extracted notification sound to ${targetFile.absolutePath}")
            return targetFile
        } catch (e: Exception) {
            Log.w(TAG, "Failed to extract notification sound from assets", e)
            return null
        }
    }

    /**
     * 播放提醒通知音。
     * 声音来源多级兜底：assets 自定义铃声 → 系统闹钟铃声 → 系统通知铃声 → 系统来电铃声。
     * 音量流自适应：STREAM_ALARM 音量为 0 时（用户把闹钟音量调零/部分 ROM 默认静音），
     * 改用 USAGE_MEDIA 走媒体音量——否则 MediaPlayer "播放成功"但无声，
     * 表现为"有震动没声音"。
     */
    fun playReminderSound(): MediaPlayer? {
        return try {
            val soundFile = ensureSoundFile()

            // 选择音频属性：闹钟流被静音时改走媒体流，保证可闻
            val attrs = if (try {
                    audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                } catch (_: Exception) { 1 } > 0
            ) {
                alarmAudioAttributes
            } else {
                Log.w(TAG, "STREAM_ALARM volume is 0, falling back to USAGE_MEDIA (media volume)")
                mediaAudioAttributes
            }

            // 铃声来源逐级兜底，任何一级可用即可发声
            val sourceUri: android.net.Uri? = soundFile?.let { android.net.Uri.fromFile(it) }
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (sourceUri == null) {
                Log.w(TAG, "No notification sound available")
                return null
            }

            val mp = MediaPlayer()
            mp.setAudioAttributes(attrs)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)

            if (soundFile != null && sourceUri == android.net.Uri.fromFile(soundFile)) {
                mp.setDataSource(soundFile.absolutePath)
            } else {
                mp.setDataSource(context, sourceUri)
            }

            mp.setOnCompletionListener {
                it.release()
            }
            mp.setOnErrorListener { player, what, extra ->
                Log.e(TAG, "MediaPlayer error: what=$what extra=$extra")
                player.release()
                true
            }
            mp.prepare()
            mp.start()
            Log.d(TAG, "Reminder sound started (source=$sourceUri, alarmStream=${attrs === alarmAudioAttributes})")
            mp
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play reminder sound", e)
            null
        }
    }

    /**
     * 播放振动：[0, 300, 100, 300, 100, 300] — 3 pulses of 300ms with 100ms gaps
     */
    fun playVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            } ?: return

            if (!vibrator.hasVibrator()) {
                Log.w(TAG, "Device has no vibrator")
                return
            }

            val pattern = longArrayOf(0, 300, 100, 300, 100, 300)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createWaveform(pattern, -1)
                vibrator.vibrate(effect)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
            Log.d(TAG, "Reminder vibration started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play vibration", e)
        }
    }

    /**
     * 播放自定义语音文件（替代 TTS）
     */
    fun playCustomVoice(path: String): MediaPlayer? {
        return try {
            val file = File(path)
            if (!file.exists()) {
                Log.w(TAG, "Custom voice file not found: $path")
                return null
            }

            val mp = MediaPlayer()
            mp.setAudioAttributes(speechAudioAttributes)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setDataSource(file.absolutePath)
            requestAlarmAudioFocus()
            mp.setOnCompletionListener {
                abandonAlarmAudioFocus()
                it.release()
            }
            mp.setOnErrorListener { player, what, extra ->
                Log.e(TAG, "Custom voice MediaPlayer error: what=$what extra=$extra")
                abandonAlarmAudioFocus()
                player.release()
                true
            }
            mp.prepare()
            mp.start()
            mp
        } catch (e: Exception) {
            abandonAlarmAudioFocus()
            Log.e(TAG, "Failed to play custom voice", e)
            null
        }
    }

    /**
     * 播放完整序列：声音 + 振动同时进行，延迟 1s 后返回（给调用方播放 TTS）
     */
    fun playSequence(soundEnabled: Boolean, vibrationEnabled: Boolean) {
        if (soundEnabled) {
            playReminderSound()
        }
        if (vibrationEnabled) {
            playVibration()
        }
    }
}
