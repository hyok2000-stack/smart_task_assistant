package com.smarttask.smart_task_assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
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
            val mp = MediaPlayer()
            mp.setAudioAttributes(alarmAudioAttributes)

            if (soundFile != null) {
                mp.setDataSource(soundFile.absolutePath)
            } else {
                // Fallback to system default notification sound
                val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                if (defaultUri != null) {
                    mp.setDataSource(context, defaultUri)
                } else {
                    Log.w(TAG, "No notification sound available")
                    return null
                }
            }

            mp.setOnCompletionListener { it.release() }
            mp.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error: what=$what extra=$extra")
                false
            }
            mp.prepare()
            mp.start()
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
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener { it.release() }
            mp.prepare()
            mp.start()
            mp
        } catch (e: Exception) {
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
