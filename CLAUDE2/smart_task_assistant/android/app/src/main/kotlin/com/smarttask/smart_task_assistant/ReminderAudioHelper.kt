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
    private val speechAudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val audioManager = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null

    private var savedAlarmVolume = -1

    fun setMaxAlarmVolume() {
        try {
            savedAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val halfVolume = max / 2
            if (savedAlarmVolume != halfVolume) {
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, halfVolume, 0)
                Log.d(TAG, "Alarm volume set to half: $savedAlarmVolume -> $halfVolume (max=$max)")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set alarm volume", e)
        }
    }

    fun restoreAlarmVolume() {
        if (savedAlarmVolume >= 0) {
            try {
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, savedAlarmVolume, 0)
                Log.d(TAG, "Alarm volume restored to: $savedAlarmVolume")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to restore alarm volume", e)
            }
            savedAlarmVolume = -1
        }
    }

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
     * 播放提醒通知音
     */
    fun playReminderSound(): MediaPlayer? {
        return try {
            val soundFile = ensureSoundFile()
            val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val mp = MediaPlayer()
            mp.setAudioAttributes(alarmAudioAttributes)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)

            if (soundFile != null) {
                mp.setDataSource(soundFile.absolutePath)
            } else if (defaultUri != null) {
                mp.setDataSource(context, defaultUri)
            } else {
                Log.w(TAG, "No notification sound available")
                return null
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
            Log.d(TAG, "Reminder sound started from ${if (soundFile != null) "asset" else "system notification"}")
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

            val pattern = longArrayOf(0, 300, 100, 300, 100, 300)
            val effect = VibrationEffect.createWaveform(pattern, -1)
            vibrator.vibrate(effect)
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
        // 将闹钟流音量调至最大，确保后台提醒声音能被听到
        setMaxAlarmVolume()
        if (soundEnabled) {
            playReminderSound()
        }
        if (vibrationEnabled) {
            playVibration()
        }
    }
}
