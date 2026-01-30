/// Developed by Hamas | dart_dlp Engine
import '../models/video_data.dart';

abstract class BaseExtractor {
  /// Optional proxy URL for stealth rotation (http://user:pass@host:port).
  String? proxy;

  /// Returns true if the URL matches the site handled by this extractor.
  bool canHandle(String url);

  /// The main extraction logic to retrieve video data.
  Future<VideoData> extract(String url,
      {Function(double progress)? onProgress});

  /// Sets the proxy for this extractor instance.
  void setProxy(String? proxyUrl) => proxy = proxyUrl;
}
