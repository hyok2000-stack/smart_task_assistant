package com.smarttask.smart_task_assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.io.File
import java.util.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 提醒 TTS 辅助：使用 Android 原生 TextToSpeech 播放语音提醒
 * 支持 Doze 模式下 TTS 引擎恢复：speak 失败时自动重新初始化并重试
 */
class ReminderTtsHelper(private val context: Context) {
    companion object {
        private const val TAG = "ReminderTtsHelper"
        private const val DEFAULT_TTS_VOLUME = 1.0f
    }

    @Volatile
    private var tts: TextToSpeech? = null
    @Volatile
    private var ttsReady = false
    private var initLatch = CountDownLatch(1)
    private val handlerThread = HandlerThread("TtsHelperThread").apply { start() }
    private val handler = Handler(handlerThread.looper)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var ttsWakeLock: PowerManager.WakeLock? = null

    /**
     * 获取 TTS 专用的 WakeLock，确保休眠时 CPU 保持唤醒直到语音播放完成
     */
    private fun acquireTtsWakeLock() {
        try {
            if (ttsWakeLock?.isHeld == true) return
            ttsWakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ReminderTts::Speak"
            ).apply {
                setReferenceCounted(false)
                acquire(60_000L)
            }
            Log.d(TAG, "TTS WakeLock acquired")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire TTS WakeLock", e)
        }
    }

    private fun releaseTtsWakeLock() {
        try {
            ttsWakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Exception) {}
        ttsWakeLock = null
    }

    /**
     * 将闹钟流音量调至最大，确保后台语音提醒能被听到
     * 保存原始音量，播放结束后恢复
     */
    private var savedAlarmVolume = -1

    private fun setMaxAlarmVolume() {
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

    private fun restoreAlarmVolume() {
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
    private var audioFocusRequest: AudioFocusRequest? = null
    private val alarmSpeechAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val alarmSoundAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    init {
        initTts()
    }

    private fun initTts() {
        initLatch = CountDownLatch(1)
        ttsReady = false
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale.CHINA)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.w(TAG, "Chinese language not supported, trying default")
                    tts?.language = Locale.getDefault()
                }
                ttsReady = true
                setupUtteranceListener()
                Log.d(TAG, "TTS initialized successfully")
            } else {
                Log.e(TAG, "TTS initialization failed: status=$status")
            }
            initLatch.countDown()
        }
    }

    /**
     * 重新初始化 TTS 引擎（Doze 模式下引擎可能被挂起，speak 返回 ERROR 时调用）
     */
    private fun reinitTts() {
        Log.d(TAG, "Reinitializing TTS engine...")
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        ttsReady = false
        initTts()
    }

    /**
     * 请求音频焦点（确保后台播报不被静音）
     * 使用 STREAM_MUSIC（与 Flutter TTS 一致），AUDIOFOCUS_GAIN_TRANSIENT 获取完整焦点
     */
    private fun requestAudioFocus() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(alarmSpeechAttributes)
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
            Log.d(TAG, "Audio focus requested (STREAM_ALARM, GAIN_TRANSIENT)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to request audio focus", e)
        }
    }

    private fun abandonAudioFocus() {
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

    // Map utteranceId → speak text for logging
    private val utteranceTextMap = mutableMapOf<String, String>()
    private val utteranceStartLatchMap = mutableMapOf<String, CountDownLatch>()
    private var nextSpeakShouldFlush = true

    private fun setupUtteranceListener() {
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                val text = utteranceTextMap[utteranceId] ?: "?"
                utteranceStartLatchMap.remove(utteranceId)?.countDown()
                Log.d(TAG, "TTS onStart: $text")
            }
            override fun onDone(utteranceId: String?) {
                val text = utteranceTextMap.remove(utteranceId) ?: "?"
                utteranceStartLatchMap.remove(utteranceId)
                Log.d(TAG, "TTS onDone: $text")
                if (utteranceTextMap.isEmpty()) {
                    nextSpeakShouldFlush = true
                }
                abandonAudioFocus()
                restoreAlarmVolume()
                releaseTtsWakeLock()
            }
            override fun onError(utteranceId: String?) {
                val text = utteranceTextMap.remove(utteranceId) ?: "?"
                utteranceStartLatchMap.remove(utteranceId)
                Log.e(TAG, "TTS onError: $text")
                if (utteranceTextMap.isEmpty()) {
                    nextSpeakShouldFlush = true
                }
                abandonAudioFocus()
                restoreAlarmVolume()
                releaseTtsWakeLock()
            }
        })
    }

    private fun waitForInit(): Boolean {
        if (ttsReady) return true
        return try {
            // 服务重启后 TTS 引擎需要更长时间绑定，分阶段等待
            if (initLatch.await(10, TimeUnit.SECONDS) && ttsReady) return true
            Log.w(TAG, "TTS not ready after 10s, retrying init...")
            reinitTts()
            initLatch.await(15, TimeUnit.SECONDS)
            if (!ttsReady) {
                Log.e(TAG, "TTS not ready after total 25s wait")
            }
            ttsReady
        } catch (e: InterruptedException) {
            Log.e(TAG, "TTS init wait interrupted", e)
            false
        }
    }

    /**
     * 等待 TTS 引擎就绪（阻塞调用，供外部在 HandlerThread 上调用）
     */
    fun waitForReady() {
        waitForInit()
    }

    /**
     * 播放语音提醒
     * 内部会延迟 1.5 秒等待通知音结束再播放
     * @param text 提醒文本
     * @param voiceType male=0.7, female=1.3, neutral=1.0
     * @param voiceStyle gentle=-0.1, lively=+0.1, standard=0.0
     * @param speed slow=0.8, normal=1.0, fast=1.4
     * @param customVoicePath 自定义语音文件路径（如果存在则跳过 TTS）
     */
    fun speak(
        text: String,
        voiceType: String? = "neutral",
        voiceStyle: String? = "standard",
        speed: String? = "normal",
        customVoicePath: String? = null
    ): Boolean {
        val accepted = AtomicBoolean(false)
        val acceptedLatch = CountDownLatch(1)
        handler.post {
            try {
            // 持有 WakeLock 确保 CPU 在整个播放过程中保持唤醒（防止休眠回睡）
            acquireTtsWakeLock()
            // 从 Doze 恢复后需要更长延迟让音频系统和 TTS 引擎恢复
            try { Thread.sleep(3000L) } catch (_: InterruptedException) {}
            // 将闹钟流音量调至一半
            setMaxAlarmVolume()
            // 请求音频焦点，确保后台播报不被静音
            requestAudioFocus()

            // Custom voice file takes priority
            if (!customVoicePath.isNullOrBlank()) {
                val file = File(customVoicePath)
                if (file.exists()) {
                    accepted.set(playCustomVoiceFile(file))
                    return@post
                }
                Log.w(TAG, "Custom voice file not found: $customVoicePath, falling back to TTS")
            }

            if (!waitForInit() || tts == null) {
                Log.e(TAG, "TTS not ready, cannot speak: ttsReady=$ttsReady, tts=$tts")
                abandonAudioFocus()
                playFallbackNotification()
                return@post
            }

            // Calculate pitch (matching Flutter _getPitch())
            val basePitch = when (voiceType) {
                "male" -> 0.7f
                "female" -> 1.3f
                else -> 1.0f
            }
            val styleAdjustment = when (voiceStyle) {
                "gentle" -> -0.1f
                "lively" -> 0.1f
                else -> 0.0f
            }
            val pitch = (basePitch + styleAdjustment).coerceIn(0.5f, 2.0f)

            // Calculate speech rate (matching Flutter perceived speed)
            val rate = when (speed) {
                "slow" -> 0.8f
                "fast" -> 1.4f
                else -> 1.0f
            }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    tts?.setAudioAttributes(alarmSpeechAttributes)
                }
                tts?.setPitch(pitch)
                tts?.setSpeechRate(rate)
                val speakParams = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, DEFAULT_TTS_VOLUME)
                }

                val utteranceId = "reminder_${System.currentTimeMillis()}"
                val queueMode =
                    if (nextSpeakShouldFlush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                if (nextSpeakShouldFlush) {
                    utteranceTextMap.clear()
                    utteranceStartLatchMap.clear()
                }
                utteranceTextMap[utteranceId] = text
                val startLatch = CountDownLatch(1)
                utteranceStartLatchMap[utteranceId] = startLatch
                nextSpeakShouldFlush = false
                val result = tts?.speak(text, queueMode, speakParams, utteranceId)
                if (result == TextToSpeech.ERROR) {
                    Log.e(TAG, "TTS speak returned ERROR, reinitializing and retrying...")
                    reinitTts()
                    if (waitForInit()) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            tts?.setAudioAttributes(alarmSpeechAttributes)
                        }
                        tts?.setPitch(pitch)
                        tts?.setSpeechRate(rate)
                        val retryId = "reminder_retry_${System.currentTimeMillis()}"
                        utteranceTextMap[retryId] = text
                        val retryStartLatch = CountDownLatch(1)
                        utteranceStartLatchMap[retryId] = retryStartLatch
                        val retryResult = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, speakParams, retryId)
                        if (retryResult == TextToSpeech.ERROR) {
                            Log.e(TAG, "TTS retry also failed, playing fallback notification sound")
                            playFallbackNotification()
                        } else {
                            accepted.set(retryStartLatch.await(5, TimeUnit.SECONDS))
                            Log.d(TAG, "TTS retry succeeded: '$text'")
                        }
                    } else {
                        Log.e(TAG, "TTS reinit failed, playing fallback notification sound")
                        playFallbackNotification()
                    }
                } else {
                    accepted.set(startLatch.await(5, TimeUnit.SECONDS))
                    Log.d(TAG, "TTS speak queued: '$text' (pitch=$pitch, rate=$rate)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "TTS speak failed, playing fallback notification sound", e)
                playFallbackNotification()
            }
            finally {
                releaseTtsWakeLock()
                acceptedLatch.countDown()
            }
        }
        return try {
            acceptedLatch.await(30, TimeUnit.SECONDS)
            accepted.get()
        } catch (e: InterruptedException) {
            Log.e(TAG, "TTS speak wait interrupted", e)
            false
        }
    }

    private fun playCustomVoiceFile(file: File): Boolean {
        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(alarmSpeechAttributes)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener {
                abandonAudioFocus()
                restoreAlarmVolume()
                it.release()
            }
            mp.setOnErrorListener { player, _, _ ->
                Log.e(TAG, "Custom voice playback error")
                abandonAudioFocus()
                restoreAlarmVolume()
                player.release()
                true
            }
            mp.prepare()
            mp.start()
            Log.d(TAG, "Playing custom voice file: ${file.name}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play custom voice file", e)
            abandonAudioFocus()
            restoreAlarmVolume()
            false
        }
    }

    /**
     * TTS 完全失败时的兜底方案：使用 MediaPlayer 播放系统通知音
     * USAGE_ALARM 在 Doze 模式下可靠，确保至少有声音提醒
     */
    private fun playFallbackNotification() {
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(alarmSoundAttributes)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
            if (uri == null) {
                Log.w(TAG, "No fallback notification sound available")
                abandonAudioFocus()
                return
            }
            mp.setDataSource(context, uri)
            mp.setOnCompletionListener {
                abandonAudioFocus()
                it.release()
            }
            mp.setOnErrorListener { mp_, _, _ ->
                abandonAudioFocus()
                mp_.release()
                true
            }
            mp.prepare()
            mp.start()
            Log.d(TAG, "Playing fallback notification sound (TTS unavailable)")
        } catch (e: Exception) {
            Log.e(TAG, "Fallback notification also failed", e)
        }
    }

    fun release() {
        releaseTtsWakeLock()
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
        handlerThread.quitSafely()
    }
}
