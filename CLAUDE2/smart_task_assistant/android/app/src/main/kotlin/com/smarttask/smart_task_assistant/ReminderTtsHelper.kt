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
        private const val IDLE_THRESHOLD_MS = 300_000L // 5 分钟空闲视为需要重新初始化
    }

    @Volatile
    private var tts: TextToSpeech? = null
    @Volatile
    private var ttsReady = false
    @Volatile
    private var lastSuccessfulSpeakTime = 0L // 上次成功 speak 的时间
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

    private var audioFocusRequest: AudioFocusRequest? = null
    private val mediaSpeechAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
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

    private var initRetryCount = 0

    private fun initTts() {
        initLatch = CountDownLatch(1)
        ttsReady = false
        try {
            tts = TextToSpeech(context.applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val result = tts?.setLanguage(Locale.CHINA)
                    if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                        Log.w(TAG, "Chinese language not supported, trying default")
                        tts?.language = Locale.getDefault()
                    }
                    ttsReady = true
                    initRetryCount = 0
                    setupUtteranceListener()
                    Log.d(TAG, "TTS initialized successfully")
                } else {
                    Log.e(TAG, "TTS initialization failed: status=$status, retryCount=$initRetryCount")
                }
                initLatch.countDown()
            }
        } catch (e: Exception) {
            Log.e(TAG, "TTS constructor exception", e)
            initLatch.countDown()
        }
    }

    /**
     * 重新初始化 TTS 引擎（Doze 模式下引擎可能被挂起，speak 返回 ERROR 时调用）
     */
    private fun reinitTts() {
        initRetryCount++
        Log.d(TAG, "Reinitializing TTS engine... (retry #$initRetryCount)")
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        ttsReady = false
        // shutdown() 是异步的，等待旧引擎完全释放后再创建新实例，
        // 避免部分 ROM 上 TTS 服务单例冲突导致新引擎初始化失败
        try { Thread.sleep(1500L) } catch (_: InterruptedException) {}
        initTts()
    }

    /**
     * 请求音频焦点（确保后台播报不被静音）
     * 使用 USAGE_MEDIA / STREAM_MUSIC（与 Flutter TTS 一致）
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
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
            }
            Log.d(TAG, "Audio focus requested (STREAM_MUSIC, GAIN_TRANSIENT)")
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
    // 文件合成播报：utteranceId → 合成完成闩锁（onDone/onError 触发）
    private val utteranceDoneLatchMap = mutableMapOf<String, CountDownLatch>()
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
                utteranceDoneLatchMap.remove(utteranceId)?.countDown()
                Log.d(TAG, "TTS onDone: $text, pending=${utteranceTextMap.size}")
                if (utteranceTextMap.isEmpty() && utteranceDoneLatchMap.isEmpty()) {
                    nextSpeakShouldFlush = true
                    abandonAudioFocus()
                    releaseTtsWakeLock()
                }
            }
            override fun onError(utteranceId: String?) {
                val text = utteranceTextMap.remove(utteranceId) ?: "?"
                utteranceStartLatchMap.remove(utteranceId)
                utteranceDoneLatchMap.remove(utteranceId)?.countDown()
                Log.e(TAG, "TTS onError: $text, pending=${utteranceTextMap.size}")
                if (utteranceTextMap.isEmpty() && utteranceDoneLatchMap.isEmpty()) {
                    nextSpeakShouldFlush = true
                    abandonAudioFocus()
                    releaseTtsWakeLock()
                }
            }
        })
    }

    private fun waitForInit(): Boolean {
        if (ttsReady) return true
        return try {
            // 首次等待：10 秒
            if (initLatch.await(10, TimeUnit.SECONDS) && ttsReady) return true
            // 重试 1：shutdown + 重新 init
            Log.w(TAG, "TTS not ready after 10s, retrying init...")
            reinitTts()
            if (initLatch.await(15, TimeUnit.SECONDS) && ttsReady) return true
            // 重试 2：再次 reinit（某些 ROM 首次绑定 TTS 服务会失败）
            if (initRetryCount < 3) {
                Log.w(TAG, "TTS not ready after 25s, retrying again...")
                reinitTts()
                initLatch.await(10, TimeUnit.SECONDS)
            }
            if (!ttsReady) {
                Log.e(TAG, "TTS not ready after all retries (total ~35s)")
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
     * 文件合成播报：先让 TTS 引擎把文本合成为音频文件，再用 MediaPlayer 播放。
     *
     * 为什么不用直接 speak()：部分 ROM（华为/荣耀等）在后台会限制 TTS 引擎的
     * 实时音频输出——onStart 照常回调、speak 返回成功，但物理上无声。
     * 文件合成不依赖引擎的实时输出通路，合成出的 WAV 由我们自己的 MediaPlayer
     * 在闹钟音量流上播放（与已验证可用的提示音同一路径），可靠性显著更高。
     *
     * @return true 表示音频文件已开始播放（音频确实存在的诚实信号）
     */
    fun speakViaFile(
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
                acquireTtsWakeLock()

                // 自定义语音文件优先，直接播放（不经 TTS）
                if (!customVoicePath.isNullOrBlank()) {
                    val file = File(customVoicePath)
                    if (file.exists()) {
                        accepted.set(playCustomVoiceFile(file))
                        return@post
                    }
                    Log.w(TAG, "Custom voice file not found: $customVoicePath, falling back to TTS")
                }

                if (!waitForInit() || tts == null) {
                    Log.e(TAG, "speakViaFile: TTS not ready (ttsReady=$ttsReady)")
                    return@post
                }

                // 音调/语速与 speak() 保持一致
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
                val rate = when (speed) {
                    "slow" -> 0.8f
                    "fast" -> 1.4f
                    else -> 1.0f
                }
                tts?.setPitch(pitch)
                tts?.setSpeechRate(rate)

                // 合成为 WAV 文件（覆盖同一文件，避免缓存堆积）
                val wavFile = File(context.cacheDir, "reminder_tts.wav")
                try { if (wavFile.exists()) wavFile.delete() } catch (_: Exception) {}
                val utteranceId = "ttsfile_${System.currentTimeMillis()}"
                val doneLatch = CountDownLatch(1)
                utteranceDoneLatchMap[utteranceId] = doneLatch
                val result = tts?.synthesizeToFile(text, Bundle(), wavFile, utteranceId)
                val synthesized = result != TextToSpeech.ERROR &&
                    doneLatch.await(15, TimeUnit.SECONDS) &&
                    wavFile.exists() && wavFile.length() > 100
                utteranceDoneLatchMap.remove(utteranceId)
                if (!synthesized) {
                    Log.e(TAG, "speakViaFile: synthesis failed (result=$result, file=${wavFile.length()} bytes)")
                    return@post
                }
                Log.d(TAG, "speakViaFile: synthesized ${wavFile.length()} bytes, playing via MediaPlayer")

                lastSuccessfulSpeakTime = System.currentTimeMillis()
                accepted.set(playSynthesizedFile(wavFile))
            } catch (e: Exception) {
                Log.e(TAG, "speakViaFile failed", e)
                accepted.set(false)
            } finally {
                if (utteranceTextMap.isEmpty() && utteranceDoneLatchMap.isEmpty()) {
                    abandonAudioFocus()
                    releaseTtsWakeLock()
                }
                acceptedLatch.countDown()
            }
        }
        return try {
            // 上限：init 重试(~35s) + 合成(15s) + 富余
            acceptedLatch.await(60, TimeUnit.SECONDS)
            accepted.get()
        } catch (e: InterruptedException) {
            Log.e(TAG, "speakViaFile wait interrupted", e)
            false
        }
    }

    /**
     * 播放合成出的音频文件。音量流自适应：闹钟流静音时改走媒体音量。
     */
    private fun playSynthesizedFile(file: File): Boolean {
        return try {
            requestAudioFocus()
            val alarmVol = try {
                audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            } catch (_: Exception) { 1 }
            val attrs = if (alarmVol > 0) {
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            } else {
                Log.w(TAG, "STREAM_ALARM muted, playing synthesized voice on media stream")
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            }
            val mp = MediaPlayer()
            mp.setAudioAttributes(attrs)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener {
                abandonAudioFocus()
                it.release()
            }
            mp.setOnErrorListener { player, what, extra ->
                Log.e(TAG, "Synthesized voice playback error: what=$what extra=$extra")
                abandonAudioFocus()
                player.release()
                true
            }
            mp.prepare()
            mp.start()
            Log.d(TAG, "Synthesized voice playing (alarmStream=${alarmVol > 0})")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play synthesized voice file", e)
            abandonAudioFocus()
            false
        }
    }

    /**
     * 播放语音提醒
     * 调用方（triggerReminder）已做屏幕唤醒 + 5s 延迟，此处不再重复等待
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
                acquireTtsWakeLock()
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
                    playFallbackNotification()
                    return@post
                }

                // 空闲超过 5 分钟（深度 Doze 后 TTS 引擎进程可能已被冻结/杀死）
                // 强制重新初始化，确保引擎处于可用状态
                val now = System.currentTimeMillis()
                if (lastSuccessfulSpeakTime > 0 && now - lastSuccessfulSpeakTime > IDLE_THRESHOLD_MS) {
                    Log.w(TAG, "TTS idle for ${(now - lastSuccessfulSpeakTime) / 1000}s, forcing reinit")
                    reinitTts()
                    if (!waitForInit() || tts == null) {
                        Log.e(TAG, "TTS reinit after idle failed, playing fallback")
                        playFallbackNotification()
                        return@post
                    }
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

                val rate = when (speed) {
                    "slow" -> 0.8f
                    "fast" -> 1.4f
                    else -> 1.0f
                }

                // 先设置 pitch/rate，再设置 audioAttributes
                // 部分 TTS 引擎在 setPitch/setSpeechRate 时会重置 audioAttributes
                tts?.setPitch(pitch)
                tts?.setSpeechRate(rate)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    tts?.setAudioAttributes(alarmSpeechAttributes)
                }
                val speakParams = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, DEFAULT_TTS_VOLUME)
                    putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_ALARM)
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
                    utteranceTextMap.remove(utteranceId)
                    utteranceStartLatchMap.remove(utteranceId)
                    accepted.set(doRetrySpeak(text, pitch, rate, speakParams))
                } else {
                    val started = startLatch.await(5, TimeUnit.SECONDS)
                    if (!started) {
                        // TTS 引擎可能已被系统杀死但 ttsReady 仍为 true（过期）
                        // onStart 从未触发 → 引擎无响应 → 重新初始化并重试
                        Log.w(TAG, "TTS start timed out for '$text', engine likely dead, reinitializing...")
                        utteranceTextMap.remove(utteranceId)
                        utteranceStartLatchMap.remove(utteranceId)
                        accepted.set(doRetrySpeak(text, pitch, rate, speakParams))
                    } else {
                        accepted.set(true)
                        lastSuccessfulSpeakTime = System.currentTimeMillis()
                        Log.d(TAG, "TTS speak started: '$text' (pitch=$pitch, rate=$rate)")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "TTS speak failed, playing fallback notification sound", e)
                playFallbackNotification()
            } finally {
                // 仅在没有待播放语音时释放资源（正常流程由 onDone/onError 释放）
                if (utteranceTextMap.isEmpty()) {
                    abandonAudioFocus()
                    releaseTtsWakeLock()
                }
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

    /**
     * TTS speak 失败或超时后的重试逻辑：重新初始化引擎并重新播放
     */
    private fun doRetrySpeak(text: String, pitch: Float, rate: Float, speakParams: Bundle): Boolean {
        reinitTts()
        if (!waitForInit() || tts == null) {
            Log.e(TAG, "TTS reinit failed, playing fallback notification sound")
            playFallbackNotification()
            return false
        }
        tts?.setPitch(pitch)
        tts?.setSpeechRate(rate)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            tts?.setAudioAttributes(alarmSpeechAttributes)
        }
        val retryId = "reminder_retry_${System.currentTimeMillis()}"
        utteranceTextMap[retryId] = text
        val retryStartLatch = CountDownLatch(1)
        utteranceStartLatchMap[retryId] = retryStartLatch
        val retryResult = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, speakParams, retryId)
        if (retryResult == TextToSpeech.ERROR) {
            utteranceTextMap.remove(retryId)
            utteranceStartLatchMap.remove(retryId)
            Log.e(TAG, "TTS retry also failed, playing fallback notification sound")
            playFallbackNotification()
            return false
        }
        val retryStarted = retryStartLatch.await(8, TimeUnit.SECONDS)
        if (!retryStarted) {
            utteranceTextMap.remove(retryId)
            utteranceStartLatchMap.remove(retryId)
            Log.e(TAG, "TTS retry start timed out, playing fallback notification sound")
            playFallbackNotification()
            return false
        }
        Log.d(TAG, "TTS retry succeeded: '$text'")
        return true
    }

    private fun playCustomVoiceFile(file: File): Boolean {
        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(alarmSpeechAttributes)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener {
                abandonAudioFocus()
                it.release()
            }
            mp.setOnErrorListener { player, _, _ ->
                Log.e(TAG, "Custom voice playback error")
                abandonAudioFocus()
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
            false
        }
    }

    /**
     * TTS 完全失败时的兜底方案：使用 MediaPlayer 播放闹钟铃声
     * TYPE_ALARM + USAGE_ALARM 在 Doze 模式下最可靠，确保至少有声音提醒
     */
    private fun playFallbackNotification() {
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(alarmSoundAttributes)
            mp.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            // 优先使用闹钟铃声（比通知铃声更响、Doze 下更可靠）
            val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
                ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
            if (uri == null) {
                Log.w(TAG, "No fallback sound available")
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
