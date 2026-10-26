package io.labhouse.cabina

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.RandomAccessFile
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Bounded PCM decoding; all positions are on the original source timeline. */
object AudioChunkExtractor {
    fun extract(source: String, destination: String, startUs: Long,
                cancelled: AtomicBoolean): Map<String, Any> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var success = false
        try {
            check(!cancelled.get())
            require(startUs >= 0)
            extractor.setDataSource(source)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio track")
            val format = extractor.getTrackFormat(track)
            val duration = if (format.containsKey(MediaFormat.KEY_DURATION))
                format.getLong(MediaFormat.KEY_DURATION) else Long.MAX_VALUE
            extractor.selectTrack(track)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            val stopUs = min(startUs + 120_000_000L, duration)
            var rate = 0
            var channels = 0
            var bytes = 0
            var firstUs: Long? = null
            var endUs = startUs
            var inputEnded = false
            var outputEnded = false
            var atLimit = false
            var lastProgress = System.nanoTime()
            val info = MediaCodec.BufferInfo()
            RandomAccessFile(destination, "rw").use { file ->
                file.setLength(0)
                file.write(ByteArray(44))
                while (!outputEnded && !atLimit) {
                    check(!cancelled.get())
                    check(System.nanoTime() - lastProgress < 30_000_000_000L) { "Decoder stalled" }
                    if (!inputEnded) {
                        val index = decoder.dequeueInputBuffer(10_000)
                        if (index >= 0) {
                            val buffer = decoder.getInputBuffer(index)!!
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputEnded = true
                            } else {
                                decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                            lastProgress = System.nanoTime()
                        }
                    }
                    val index = decoder.dequeueOutputBuffer(info, 10_000)
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val output = decoder.outputFormat
                        rate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        val encoding = if (output.containsKey(MediaFormat.KEY_PCM_ENCODING))
                            output.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                        require(rate > 0 && channels in 1..2 && encoding == AudioFormat.ENCODING_PCM_16BIT)
                    } else if (index >= 0) {
                        try {
                            lastProgress = System.nanoTime()
                            if (info.size > 0) {
                                require(rate > 0 && channels > 0)
                                val frameSize = channels * 2
                                val frames = info.size / frameSize
                                val skip = min(frames.toLong(), max(0L,
                                    ceil((startUs - info.presentationTimeUs) * rate / 1_000_000.0).toLong())).toInt()
                                val untilEnd = max(0L, (stopUs - info.presentationTimeUs) * rate / 1_000_000L)
                                val available = max(0, min(frames.toLong(), untilEnd).toInt() - skip)
                                val count = min(available, (20_000_000 - 44 - bytes) / frameSize)
                                if (count > 0) {
                                    val buffer = decoder.getOutputBuffer(index)!!
                                    buffer.position(info.offset + skip * frameSize)
                                    val data = ByteArray(count * frameSize)
                                    buffer.get(data)
                                    file.write(data)
                                    val sampleStart = info.presentationTimeUs + skip * 1_000_000L / rate
                                    if (firstUs == null) firstUs = sampleStart
                                    endUs = sampleStart + count * 1_000_000L / rate
                                    bytes += data.size
                                }
                                atLimit = count < available || untilEnd <= frames ||
                                    (20_000_000 - 44 - bytes) < frameSize
                            }
                            outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        } finally { decoder.releaseOutputBuffer(index, false) }
                    }
                }
                check(!cancelled.get())
                require(bytes > 0 && firstUs != null)
                val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                header.put("RIFF".toByteArray()).putInt(bytes + 36).put("WAVEfmt ".toByteArray())
                    .putInt(16).putShort(1.toShort()).putShort(channels.toShort()).putInt(rate)
                    .putInt(rate * channels * 2).putShort((channels * 2).toShort()).putShort(16.toShort())
                    .put("data".toByteArray()).putInt(bytes)
                file.seek(0)
                file.write(header.array())
                file.fd.sync()
            }
            success = true
            return mapOf("startUs" to firstUs!!, "endUs" to endUs,
                "sourceDurationUs" to (if (duration == Long.MAX_VALUE) 0L else duration),
                "isLast" to (outputEnded || endUs >= duration - 50_000L))
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            codec?.release()
            extractor.release()
            if (!success) File(destination).delete()
        }
    }
}
