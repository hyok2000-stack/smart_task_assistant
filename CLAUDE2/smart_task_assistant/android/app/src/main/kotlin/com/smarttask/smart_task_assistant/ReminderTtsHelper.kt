package com.smarttask.smart_task_assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.io.File
import java.util.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 提醒 TTS 辅助：使用 Android 原生 TextToSpeech 播放语音提醒
 * 参数映射与 Flutter 层 TTSService / HabitService 一致
 */
class ReminderTtsHelper(private val context: Context) {
    companion object {
        private const val TAG = "ReminderTtsHelper"
    }

    @Volatile
    private var tts: TextToSpeech? = null
    @Volatile
    private var ttsReady = false
    private val initLatch = CountDownLatch(1)
    private val handlerThread = HandlerThread("TtsHelperThread").apply { start() }
    private val handler = Handler(handlerThread.looper)

    init {
        initTts()
    }

    private fun initTts() {
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

    // Map utteranceId → speak text for logging
    private val utteranceTextMap = mutableMapOf<String, String>()

    private fun setupUtteranceListener() {
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                val text = utteranceTextMap[utteranceId] ?: "?"
                Log.d(TAG, "TTS onStart: $text")
            }
            override fun onDone(utteranceId: String?) {
                val text = utteranceTextMap.remove(utteranceId) ?: "?"
                Log.d(TAG, "TTS onDone: $text")
            }
            override fun onError(utteranceId: String?) {
                val text = utteranceTextMap.remove(utteranceId) ?: "?"
                Log.e(TAG, "TTS onError: $text")
            }
        })
    }

    private fun waitForInit(): Boolean {
        if (ttsReady) return true
        return try {
            initLatch.await(5, TimeUnit.SECONDS)
            if (!ttsReady) {
                Log.e(TAG, "TTS not ready after 5s wait")
            }
            ttsReady
        } catch (e: InterruptedException) {
            Log.e(TAG, "TTS init wait interrupted", e)
            false
        }
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
    ) {
        handler.post {
            // Wait for notification sound to finish before speaking
            try { Thread.sleep(1500L) } catch (_: InterruptedException) {}

            // Custom voice file takes priority
            if (!customVoicePath.isNullOrBlank()) {
                val file = File(customVoicePath)
                if (file.exists()) {
                    playCustomVoiceFile(file)
                    return@post
                }
                Log.w(TAG, "Custom voice file not found: $customVoicePath, falling back to TTS")
            }

            if (!waitForInit() || tts == null) {
                Log.e(TAG, "TTS not ready, cannot speak: ttsReady=$ttsReady, tts=$tts")
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

            try {
                tts?.setPitch(pitch)
                tts?.setSpeechRate(rate)

                val utteranceId = "reminder_${System.currentTimeMillis()}"
                utteranceTextMap[utteranceId] = text
                val result = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
                if (result == TextToSpeech.ERROR) {
                    Log.e(TAG, "TTS speak returned ERROR for: '$text'")
                } else {
                    Log.d(TAG, "TTS speak queued: '$text' (pitch=$pitch, rate=$rate)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "TTS speak failed", e)
            }
        }
    }

    private fun playCustomVoiceFile(file: File) {
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener { it.release() }
            mp.setOnErrorListener { _, _, _ ->
                Log.e(TAG, "Custom voice playback error")
                false
            }
            mp.prepare()
            mp.start()
            Log.d(TAG, "Playing custom voice file: ${file.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play custom voice file", e)
        }
    }

    fun stop() {
        handler.post {
            tts?.stop()
        }
    }

    fun release() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
        handlerThread.quitSafely()
    }
}
