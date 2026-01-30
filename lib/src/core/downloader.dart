/// Developed by Hamas | dart_dlp Engine
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class DownloadProgress {
  final double percentage; // 0.0 to 100.0
  final double speedMBps;
  final Duration eta;

  DownloadProgress(this.percentage, this.speedMBps, this.eta);
}

class HamasDownloader {
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progress => _progressController.stream;

  /// Downloads a file using concurrent chunk requests.
  ///
  /// [url] Source URL.
  /// [savePath] Destination file path.
  /// [chunks] Number of concurrent chunks (default: 8).
  Future<void> download(String url, String savePath,
      {int chunks = 8, Map<String, String>? headers}) async {
    final file = File(savePath);
    final raf = await file.open(mode: FileMode.write);

    // 1. Get Content Length
    int bodyLength = 0;
    try {
      final headResponse = await http.head(Uri.parse(url), headers: headers);
      if (headResponse.statusCode == 200 || headResponse.statusCode == 206) {
        bodyLength =
            int.tryParse(headResponse.headers['content-length'] ?? '') ?? 0;
      }

      if (bodyLength <= 0) {
        // Fallback to GET with Range: bytes=0-0 (some signed URLs block HEAD)
        final getResponse = await http.get(Uri.parse(url), headers: {
          ...?headers,
          'Range': 'bytes=0-0',
        });
        if (getResponse.statusCode == 206 || getResponse.statusCode == 200) {
          final contentRange = getResponse.headers['content-range'];
          if (contentRange != null && contentRange.contains('/')) {
            bodyLength = int.tryParse(contentRange.split('/').last) ?? 0;
          } else {
            bodyLength =
                int.tryParse(getResponse.headers['content-length'] ?? '') ?? 0;
          }
        }
      }
    } catch (e) {
      print('Could not get content length: $e');
    }

    if (bodyLength <= 0) {
      // Direct Download Fallback
      await _downloadSingle(url, raf, headers: headers);
      await raf.close();
      _progressController.close();
      return;
    }

    // 2. Calculate Chunk Sizes
    final totalLength = bodyLength;
    final chunkSize = (totalLength / chunks).ceil();
    final futures = <Future<void>>[];

    int receivedBytes = 0;
    final startTime = DateTime.now();

    for (int i = 0; i < chunks; i++) {
      final start = i * chunkSize;
      var end = (i + 1) * chunkSize - 1;
      if (end >= totalLength) end = totalLength - 1;

      futures.add(_downloadChunk(url, start, end, raf, (bytes) {
        receivedBytes += bytes;
      }, headers: headers));
    }

    // 3. Monitor Progress
    final timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      final speed =
          elapsed > 0 ? (receivedBytes / (1024 * 1024)) / elapsed : 0.0;
      final percentage = (receivedBytes / totalLength) * 100;
      final remainingBytes = totalLength - receivedBytes;
      final etaSeconds =
          speed > 0 ? (remainingBytes / (1024 * 1024)) / speed : 0;

      _progressController.add(DownloadProgress(
        percentage,
        speed,
        Duration(seconds: etaSeconds.toInt()),
      ));
    });

    try {
      await Future.wait(futures);
    } finally {
      timer.cancel();
      await raf.close();
      _progressController.close();
    }
  }

  Future<void> _downloadChunk(String url, int start, int end,
      RandomAccessFile raf, Function(int) onBytes,
      {Map<String, String>? headers}) async {
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    request.headers['Range'] = 'bytes=$start-$end';

    final response = await request.send();
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception(
          'Failed to download chunk from $url: ${response.statusCode}');
    }

    // int offset = start; // Unused
    await response.stream.forEach((chunk) {
      // Locking might be needed for very high concurrency on some file systems,
      // but RandomAccessFile.setPositionSync is usually safe per handle if careful.
      // However, sharing one RAF across isolates/futures requires caution.
      // For simple Futures in same Isolate, sequential sync writing is safest.
      // Optimally, each chunk could write to a temp file and merge, but seeking is faster.

      // Since we are in the same isolate, we just need to ensure we write to the correct offset.
      // Note: RAF is stateful (position). We must set position before EVERY write in a concurrent setup.
      // Race condition danger: If two futures set position then write, they might overwrite.
      // Fix: Use separate RAF handles or synchronized access.
      // For this implementation, we will assume a simple lock or rely on OS buffering.
      // BETTER APPROACH for Dart single-isolate concurrency:
      // Actually, standard `await` yields. We cannot share one RAF safely without locking mechanism.
      // Simplified approach: Open a NEW RAF handle for each chunk to ensure thread-safety (OS file handle independent position).
    });

    // Re-implementation with separate RAF for safety:
    final chunkFile = await File(raf.path).open(mode: FileMode.write);
    try {
      final chunkRequest = http.Request('GET', Uri.parse(url));
      if (headers != null) chunkRequest.headers.addAll(headers);
      chunkRequest.headers['Range'] = 'bytes=$start-$end';
      final chunkResponse = await chunkRequest.send();

      int currentPos = start;
      await chunkResponse.stream.listen((data) async {
        chunkFile.setPositionSync(currentPos);
        chunkFile.writeFromSync(data);
        currentPos += data.length;
        onBytes(data.length);
      }).asFuture();
    } finally {
      await chunkFile.close();
    }
  }

  Future<void> _downloadSingle(String url, RandomAccessFile raf,
      {Map<String, String>? headers}) async {
    // Implementation for non-chunked fallback
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    final response = await request.send();
    int total = response.contentLength ?? 0;
    int received = 0;
    final startTime = DateTime.now();

    await response.stream.listen((data) {
      raf.writeFromSync(data);
      received += data.length;
      if (total > 0) _reportProgress(received, total, startTime);
    }).asFuture();
  }

  void _reportProgress(int received, int total, DateTime startTime) {
    final elapsed = DateTime.now().difference(startTime).inSeconds;
    final speed = elapsed > 0 ? (received / 1024 / 1024) / elapsed : 0.0;
    final percentage = (received / total) * 100;
    final remainingBytes = total - received;
    final etaSeconds = speed > 0 ? (remainingBytes / 1024 / 1024) / speed : 0;

    _progressController.add(DownloadProgress(
      percentage,
      speed,
      Duration(seconds: etaSeconds.toInt()),
    ));
  }
}
