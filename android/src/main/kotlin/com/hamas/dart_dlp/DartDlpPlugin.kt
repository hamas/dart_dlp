package com.hamas.dart_dlp

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.nio.ByteBuffer

/** DartDlpPlugin */
class DartDlpPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "hamas_dlp/muxer")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "mergeVideoAudio") {
      val videoPath = call.argument<String>("videoPath")
      val audioPath = call.argument<String>("audioPath")
      val outputPath = call.argument<String>("outputPath")

      if (videoPath == null || audioPath == null || outputPath == null) {
        result.error("INVALID_ARGS", "Paths cannot be null", null)
        return
      }

      Thread {
        try {
          mux(videoPath, audioPath, outputPath)
          result.success(outputPath)
        } catch (e: Exception) {
          result.error("MUX_FIALED", e.message, null)
        }
      }.start()

    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  private fun mux(videoFile: String, audioFile: String, outFile: String) {
    val muxer = MediaMuxer(outFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    val videoExtractor = MediaExtractor()
    val audioExtractor = MediaExtractor()

    videoExtractor.setDataSource(videoFile)
    audioExtractor.setDataSource(audioFile)

    var videoTrackIndex = -1
    var audioTrackIndex = -1
    var muxerVideoTrackIndex = -1
    var muxerAudioTrackIndex = -1

    // 1. Select Video Track
    for (i in 0 until videoExtractor.trackCount) {
      val format = videoExtractor.getTrackFormat(i)
      val mime = format.getString(MediaFormat.KEY_MIME)
      if (mime?.startsWith("video/") == true) {
        videoExtractor.selectTrack(i)
        videoTrackIndex = i
        muxerVideoTrackIndex = muxer.addTrack(format)
        break
      }
    }

    // 2. Select Audio Track
    for (i in 0 until audioExtractor.trackCount) {
      val format = audioExtractor.getTrackFormat(i)
      val mime = format.getString(MediaFormat.KEY_MIME)
      if (mime?.startsWith("audio/") == true) {
        audioExtractor.selectTrack(i)
        audioTrackIndex = i
        muxerAudioTrackIndex = muxer.addTrack(format)
        break
      }
    }

    muxer.start()

    val bufferInfo = MediaCodec.BufferInfo()
    val buffer = ByteBuffer.allocate(10 * 1024 * 1024) // 10MB Buffer

    // 3. Write Video
    if (videoTrackIndex >= 0) {
      while (true) {
        val sampleSize = videoExtractor.readSampleData(buffer, 0)
        if (sampleSize < 0) break
        bufferInfo.offset = 0
        bufferInfo.size = sampleSize
        bufferInfo.presentationTimeUs = videoExtractor.sampleTime
        bufferInfo.flags = videoExtractor.sampleFlags
        muxer.writeSampleData(muxerVideoTrackIndex, buffer, bufferInfo)
        videoExtractor.advance()
      }
    }

    // 4. Write Audio
    if (audioTrackIndex >= 0) {
      while (true) {
        val sampleSize = audioExtractor.readSampleData(buffer, 0)
        if (sampleSize < 0) break
        bufferInfo.offset = 0
        bufferInfo.size = sampleSize
        bufferInfo.presentationTimeUs = audioExtractor.sampleTime
        bufferInfo.flags = audioExtractor.sampleFlags
        muxer.writeSampleData(muxerAudioTrackIndex, buffer, bufferInfo)
        audioExtractor.advance()
      }
    }

    muxer.stop()
    muxer.release()
    videoExtractor.release()
    audioExtractor.release()
  }
}
