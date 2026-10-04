package com.smarttask.smart_task_assistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Vosk 离线语音识别（本地小模型，华为等无 GMS 设备的系统识别兜底）。
 *
 * 模型 zip 打包在 assets/models/，首次使用解压到内部存储（约 128MB），
 * 之后完全离线工作。识别事件（partial/result JSON）通过 EventChannel 推给 Flutter。
 */
class VoskSpeechHandler(private val context: Context) {
    companion object {
        private const val TAG = "VoskSpeechHandler"
        private const val MODEL_ASSET = "models/vosk-model-small-cn-0.22.zip"
        private const val MODEL_DIR = "vosk-model-small-cn-0.22"
        private const val SAMPLE_RATE = 16000.0f
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var speechService: SpeechService? = null
    private var eventSink: EventChannel.EventSink? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    /** 初始化：解压模型 + 加载（耗时秒级，后台线程执行）。result=true 表示就绪 */
    fun init(result: MethodChannel.Result) {
        executor.execute {
            try {
                if (model == null) {
                    val dir = File(context.filesDir, MODEL_DIR)
                    if (!File(dir, "final.mdl").exists()) {
                        Log.d(TAG, "Extracting vosk model from assets...")
                        context.assets.open(MODEL_ASSET).use { input ->
                            java.util.zip.ZipInputStream(input).use { zip ->
                                var entry = zip.nextEntry
                                val outRoot = context.filesDir
                                while (entry != null) {
                                    val outFile = File(outRoot, entry.name)
                                    if (entry.isDirectory) {
                                        outFile.mkdirs()
                                    } else {
                                        outFile.parentFile?.mkdirs()
                                        outFile.outputStream().use { zip.copyTo(it) }
                                    }
                                    zip.closeEntry()
                                    entry = zip.nextEntry
                                }
                            }
                        }
                        Log.d(TAG, "Vosk model extracted to ${dir.absolutePath}")
                    }
                    model = Model(dir.absolutePath)
                }
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                Log.e(TAG, "vosk init failed", e)
                mainHandler.post { result.success(false) }
            }
        }
    }

    /** 开始聆听（麦克风由 Vosk SpeechService 内部管理） */
    fun start() {
        val m = model ?: return
        if (speechService != null) return
        executor.execute {
            try {
                val recognizer = Recognizer(m, SAMPLE_RATE)
                recognizer.setWords(true)
                val service = SpeechService(recognizer, SAMPLE_RATE)
                val listener = object : RecognitionListener {
                    override fun onPartialResult(hypothesis: String?) {
                        emit(hypothesis ?: return)
                    }

                    override fun onResult(hypothesis: String?) {
                        // 中间轮询结果与 partial 相同，跳过避免重复
                    }

                    override fun onFinalResult(hypothesis: String?) {
                        emit(hypothesis ?: return)
                    }

                    override fun onError(e: Exception?) {
                        Log.e(TAG, "vosk recognize error", e)
                    }

                    override fun onTimeout() {
                        Log.d(TAG, "vosk timeout")
                    }
                }
                speechService = service
                service.startListening(listener)
                Log.d(TAG, "vosk listening started")
            } catch (e: Exception) {
                Log.e(TAG, "vosk start failed", e)
            }
        }
    }

    fun stop() {
        try {
            speechService?.stop()
        } catch (_: Exception) {}
        speechService = null
    }

    private fun emit(json: String) {
        mainHandler.post { eventSink?.success(json) }
    }
}
