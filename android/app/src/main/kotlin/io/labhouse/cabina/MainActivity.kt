package io.labhouse.cabina

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity: FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val jobs = ConcurrentHashMap<String, AtomicBoolean>()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cabina/audio_chunks")
            .setMethodCallHandler { call, result ->
                val id = call.argument<String>("id")
                if (id == null) {
                    result.error("invalid_arguments", "Missing job ID", null)
                } else if (call.method == "cancel") {
                    jobs[id]?.set(true)
                    result.success(null)
                } else if (call.method == "extract") {
                    val source = call.argument<String>("sourcePath")
                    val output = call.argument<String>("outputPath")
                    val start = call.argument<Number>("startUs")?.toLong()
                    if (source == null || output == null || start == null) {
                        result.error("invalid_arguments", "Missing audio paths", null)
                    } else {
                        val cancelled = AtomicBoolean(false)
                        jobs[id] = cancelled
                        worker.execute {
                            try {
                                val value = AudioChunkExtractor.extract(source, output, start, cancelled)
                                main.post { result.success(value) }
                            } catch (_: Exception) {
                                main.post { result.error("audio_preparation_failed",
                                    "Audio preparation failed or was cancelled", null) }
                            } finally { jobs.remove(id) }
                        }
                    }
                } else { result.notImplemented() }
            }
    }

    override fun onDestroy() {
        jobs.values.forEach { it.set(true) }
        worker.shutdown()
        super.onDestroy()
    }
}
