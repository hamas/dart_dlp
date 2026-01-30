/// Developed by Hamas | dart_dlp Engine
import '../extractors/base.dart';
import '../models/video_data.dart';

class DlpEngine {
  final List<BaseExtractor> _extractors = [];
  final String? _proxy;

  /// Creates a new engine instance, optionally routed through a [proxy].
  DlpEngine({String? proxy}) : _proxy = proxy;

  /// Registers a new extractor dynamically.
  void registerExtractor(BaseExtractor extractor) {
    // Auto-configure proxy if set globally
    if (_proxy != null) extractor.setProxy(_proxy);
    _extractors.add(extractor);
  }

  /// Finds a matching extractor for the given URL.
  BaseExtractor analyze(String url) {
    for (final extractor in _extractors) {
      if (extractor.canHandle(url)) {
        return extractor;
      }
    }
    throw Exception('No extractor found for URL: $url');
  }

  /// Finds a matching extractor and retrieves video data.
  ///
  /// [url] is the video URL to process.
  /// [onProgress] optional callback for tracking extraction progress.
  Future<VideoData> extract(String url,
      {Function(double progress)? onProgress}) async {
    final extractor = analyze(url);
    return await extractor.extract(url, onProgress: onProgress);
  }
}
