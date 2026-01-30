import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// A pure-native muxer that bridges to Android/iOS media APIs.
/// This allows merging video and audio without FFmpeg or external binaries.
class NativeMuxer {
  static const MethodChannel _channel = MethodChannel('hamas_dlp/muxer');

  /// Merges a video file and an audio file into a single output file.
  ///
  /// Uses [MediaMuxer] on Android and [AVAssetExportSession] on iOS.
  /// Performs a "Passthrough" export (Zero-Encoding) for maximum speed.
  ///
  /// Returns the [outputPath] on success.
  static Future<String> mux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    // 1. Platform Check
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
          'NativeMuxer is only supported on Android and iOS.');
    }

    // 2. File Validation
    if (!File(videoPath).existsSync())
      throw FileSystemException('Video file not found', videoPath);
    if (!File(audioPath).existsSync())
      throw FileSystemException('Audio file not found', audioPath);

    try {
      // 3. Invoke Native Method
      final String? result =
          await _channel.invokeMethod<String>('mergeVideoAudio', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });

      if (result == null)
        throw Exception('Muxing failed: Native returned null');
      return result;
    } on PlatformException catch (e) {
      throw Exception('Native Muxing Failed: ${e.message} (Code: ${e.code})');
    }
  }
}
