/// Developed by Hamas | dart_dlp Engine
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'downloader.dart';
import 'exceptions.dart';

import '../models/video_data.dart';
import '../muxer/native_muxer.dart';

enum DlpStatus { idle, extracting, downloading, merging, completed, error }

class DlpState {
  final DlpStatus status;
  final String message;
  final DownloadProgress? progress;
  final dynamic error;

  DlpState(this.status, {this.message = '', this.progress, this.error});
}

class DlpController {
  // final DlpEngine _engine = DlpEngine(); // Removed: extraction is decoupled
  // final NativeMuxer _muxer = NativeMuxer(); // Removed: uses static methods
  final HamasDownloader _downloader = HamasDownloader();

  final StreamController<DlpState> _stateController =
      StreamController<DlpState>.broadcast();
  Stream<DlpState> get state => _stateController.stream;

  DlpController() {
    _downloader.progress.listen((progress) {
      if (!_stateController.isClosed) {
        _stateController.add(DlpState(DlpStatus.downloading,
            message: 'Downloading...', progress: progress));
      }
    });
  }

  /// Downloads the media described by [data].
  ///
  /// *   **Standard (720p-)**: Downloads the single best stream directly.
  /// *   **HD (1080p+)**: Downloads video and audio streams separately, then merges them using `NativeMuxer`.
  ///
  /// [outputDir] is the folder where the final file will be saved.
  /// Returns the path to the final file.
  Future<String> startDownload(VideoData data, String outputDir) async {
    try {
      final safeTitle = data.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final finalPath = p.join(outputDir, '$safeTitle.mp4');

      _updateState(
          DlpStatus.downloading, 'Starting download for ${data.title}');

      // Strategy A: Split Streams (HD / 4K)
      // We prioritize this if available, as it offers the highest quality.
      if (data.videoOnlyStreams.isNotEmpty &&
          data.audioOnlyStreams.isNotEmpty) {
        // 1. Select Best Streams (Naive: First item is usually highest quality in our extractors)
        final videoStream = data.videoOnlyStreams.first;
        final audioStream = data.audioOnlyStreams.first;

        final vPath = p.join(outputDir, 'temp_video_${data.id}.mp4');
        final aPath = p.join(outputDir, 'temp_audio_${data.id}.m4a');

        // 2. Download Video
        _updateState(DlpStatus.downloading,
            'Downloading Video Track (${videoStream.quality})...');
        await _downloader.download(videoStream.url, vPath);

        // 3. Download Audio
        _updateState(DlpStatus.downloading, 'Downloading Audio Track...');
        await _downloader.download(audioStream.url, aPath);

        // 4. Native Muxing
        _updateState(
            DlpStatus.merging, 'Merging streams (Native Passthrough)...');

        try {
          // NativeMuxer.mux throws if it fails or platform unsupported
          await NativeMuxer.mux(
              videoPath: vPath, audioPath: aPath, outputPath: finalPath);

          // 5. Cleanup
          _tryDelete(vPath);
          _tryDelete(aPath);

          _updateState(DlpStatus.completed, 'Finished: $finalPath');
          return finalPath;
        } catch (e) {
          // Muxing Failed (e.g., Desktop or OS error)
          // Return both paths so user can handle them
          final msg = 'Muxing failed ($e). Kept separate files.';
          _updateState(DlpStatus.completed, msg);
          return 'SPLIT_FILES|$vPath|$aPath';
        }
      }
      // Strategy B: Single Stream (Standard Definition)
      else if (data.streams.isNotEmpty) {
        final stream = data.streams.first;
        _updateState(DlpStatus.downloading,
            'Downloading Single Stream (${stream.quality})...');
        await _downloader.download(stream.url, finalPath);
        _updateState(DlpStatus.completed, 'Finished: $finalPath');
        return finalPath;
      } else {
        throw SiteNotSupportedException('No suitable streams found');
      }
    } catch (e) {
      _updateState(DlpStatus.error, e.toString());
      rethrow;
    }
  }

  Future<void> _tryDelete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  void _updateState(DlpStatus status, String msg) {
    if (!_stateController.isClosed) {
      _stateController.add(DlpState(status, message: msg));
    }
  }

  void dispose() {
    _stateController.close();
  }
}
