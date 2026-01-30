/// Developed by Hamas | dart_dlp Engine
library dart_dlp;

class VideoData {
  final String title;
  final String id;
  final String originalUrl;
  final List<StreamInfo> streams;
  final List<StreamInfo> videoOnlyStreams;
  final List<StreamInfo> audioOnlyStreams;
  final Map<String, dynamic> metadata;

  VideoData({
    required this.title,
    required this.id,
    required this.originalUrl,
    required this.streams,
    this.videoOnlyStreams = const [],
    this.audioOnlyStreams = const [],
    required this.metadata,
    this.httpHeaders = const {},
  });

  final Map<String, String> httpHeaders;
}

class StreamInfo {
  final String url;
  final String? quality;
  final String format;
  final int? height;
  final int? width;

  StreamInfo({
    required this.url,
    required this.quality,
    required this.format,
    this.height,
    this.width,
  });
}
