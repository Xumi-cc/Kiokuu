package com.kiokuu.app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity: AudioServiceActivity() {
    private val AUDIO_DECODER_CHANNEL = "com.kiokuu/audio_decoder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Audio decoder channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_DECODER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeAudio" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val decoded = decodeAudioFile(filePath)
                            if (decoded != null) {
                                result.success(decoded)
                            } else {
                                result.error("DECODE_FAILED", "Failed to decode audio file", null)
                            }
                        } catch (e: Exception) {
                            result.error("DECODE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "File path is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun decodeAudioFile(filePath: String): Map<String, Any>? {
        val file = File(filePath)
        if (!file.exists()) return null

        val extractor = MediaExtractor()
        extractor.setDataSource(filePath)

        // Find audio track
        var audioTrackIndex = -1
        var format: MediaFormat? = null
        
        for (i in 0 until extractor.trackCount) {
            val trackFormat = extractor.getTrackFormat(i)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("audio/") == true) {
                audioTrackIndex = i
                format = trackFormat
                break
            }
        }

        if (audioTrackIndex == -1 || format == null) {
            extractor.release()
            return null
        }

        extractor.selectTrack(audioTrackIndex)

        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val duration = if (format.containsKey(MediaFormat.KEY_DURATION)) {
            (format.getLong(MediaFormat.KEY_DURATION) / 1000000).toInt()
        } else {
            0
        }

        val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val samples = mutableListOf<Short>()
        val bufferInfo = MediaCodec.BufferInfo()
        var sawInputEOS = false
        var sawOutputEOS = false
        
        // Limit samples to ~30 seconds at 44100Hz mono for fingerprinting
        val maxSamples = 44100 * 30

        while (!sawOutputEOS && samples.size < maxSamples) {
            // Feed input
            if (!sawInputEOS) {
                val inputBufferIndex = codec.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = codec.getInputBuffer(inputBufferIndex)
                    if (inputBuffer != null) {
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEOS = true
                        } else {
                            codec.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
            }

            // Get output
            val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
            if (outputBufferIndex >= 0) {
                val outputBuffer = codec.getOutputBuffer(outputBufferIndex)
                if (outputBuffer != null && bufferInfo.size > 0) {
                    // Convert to 16-bit PCM samples
                    val shortBuffer = outputBuffer.order(ByteOrder.nativeOrder()).asShortBuffer()
                    val shortArray = ShortArray(shortBuffer.remaining())
                    shortBuffer.get(shortArray)
                    
                    // Convert to mono if stereo
                    if (channelCount == 2) {
                        for (i in 0 until shortArray.size step 2) {
                            if (i + 1 < shortArray.size) {
                                val mono = ((shortArray[i].toInt() + shortArray[i + 1].toInt()) / 2).toShort()
                                samples.add(mono)
                            }
                        }
                    } else {
                        samples.addAll(shortArray.toList())
                    }
                }
                
                codec.releaseOutputBuffer(outputBufferIndex, false)
                
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    sawOutputEOS = true
                }
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        // Convert to ByteArray for Flutter
        val byteBuffer = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        samples.forEach { byteBuffer.putShort(it) }

        return mapOf(
            "samples" to byteBuffer.array(),
            "sampleRate" to sampleRate,
            "duration" to duration
        )
    }
}
