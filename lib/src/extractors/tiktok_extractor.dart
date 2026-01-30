import 'package:http/http.dart' as http;
import 'base.dart';
import '../models/video_data.dart';
import '../core/utils.dart';
import '../core/exceptions.dart';

class TikTokExtractor extends BaseExtractor with JsonScraper {
  static final RegExp _regex = RegExp(
    r'^https?:\/\/(?:www\.|vm\.|vt\.)?tiktok\.com\/',
    caseSensitive: false,
  );

  @override
  bool canHandle(String url) {
    return _regex.hasMatch(url);
  }

  @override
  Future<VideoData> extract(String url,
      {Function(double progress)? onProgress}) async {
    onProgress?.call(0.1);

    // 1. Fetch HTML
    final headers = {
      'User-Agent': UserAgentManager.random,
      'Referer': 'https://www.tiktok.com/',
    };

    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      if (response.statusCode == 404)
        throw SiteNotSupportedException('TikTok video not found: $url');
      throw NetworkTimeoutException(
          'Failed to load TikTok page: ${response.statusCode}');
    }

    // 2. Locate Rehydration Script
    final data = extractJsonFromScript(
        response.body, '__UNIVERSAL_DATA_FOR_REHYDRATION__');

    onProgress?.call(0.5);

    // 3. Traverse JSON Path
    // Path: webapp.video-detail -> itemInfo -> itemStruct -> video -> downloadAddr
    // Note: Structure varies. Often it's in defaultScope -> webapp.video-detail ...

    try {
      final defaultScope = data['__DEFAULT_SCOPE__'] as Map<String, dynamic>?;
      if (defaultScope == null) throw Exception('Missing default scope');

      final videoDetail = defaultScope['webapp.video-detail'];
      if (videoDetail == null) throw Exception('Missing video detail');

      final itemInfo = videoDetail['itemInfo'];
      final itemStruct = itemInfo['itemStruct'];

      final video = itemStruct['video'];
      final id = itemStruct['id'] as String;
      final desc = itemStruct['desc'] as String;

      String downloadAddr = video['downloadAddr']; // Usually clean
      final playAddr = video['playAddr']; // Raw stream

      // Fallback logic
      if (downloadAddr.isEmpty && playAddr != null) {
        downloadAddr = playAddr;
      }

      final format = video['format'] ?? 'mp4';
      final height = video['height'];
      final width = video['width'];

      onProgress?.call(1.0);

      final streamInfo = StreamInfo(
        url: downloadAddr,
        quality: '${height}p',
        format: format,
        height: height is int ? height : int.tryParse(height.toString()),
        width: width is int ? width : int.tryParse(width.toString()),
      );

      return VideoData(
        title: desc.isNotEmpty ? desc : 'TikTok Video $id',
        id: id,
        originalUrl: url,
        streams: [streamInfo],
        videoOnlyStreams: [], // TikTok usually sends mixed streams
        audioOnlyStreams: [], // Unless dynamic playback is on, but simple extraction usually gets single file.
        metadata: {'author': itemStruct['author']['uniqueId']},
      );
    } catch (e) {
      throw SiteNotSupportedException(
          'Failed to traverse TikTok JSON structure: $e');
    }
  }
}
