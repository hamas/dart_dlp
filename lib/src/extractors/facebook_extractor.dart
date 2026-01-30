/// Developed by Hamas | dart_dlp Engine
import 'package:http/http.dart' as http;
import '../core/utils.dart';
import '../models/video_data.dart';
import 'base.dart';

class FacebookExtractor extends BaseExtractor with JsonScraper {
  @override
  bool canHandle(String url) {
    return url.contains('facebook.com/') || url.contains('fb.watch/');
  }

  @override
  Future<VideoData> extract(String url,
      {Function(double p1)? onProgress}) async {
    onProgress?.call(0.1);
    final userAgent = UserAgentManager.random;
    final response = await http.get(
      Uri.parse(url),
      headers: {
        ...RequestFactory.commonHeaders,
        'User-Agent': userAgent,
      },
    );

    onProgress?.call(0.5);

    // Facebook video parsing involves finding "hd_src" or "sd_src" in the massive HTML blob.
    // Often inside separate script blocks.
    final hdMatch = RegExp(r'hd_src:"([^"]+)"').firstMatch(response.body);
    final sdMatch = RegExp(r'sd_src:"([^"]+)"').firstMatch(response.body);

    final streams = <StreamInfo>[];
    if (hdMatch != null) {
      streams.add(
          StreamInfo(url: hdMatch.group(1)!, quality: 'HD', format: 'mp4'));
    }
    if (sdMatch != null) {
      streams.add(
          StreamInfo(url: sdMatch.group(1)!, quality: 'SD', format: 'mp4'));
    }

    onProgress?.call(0.9);

    if (streams.isEmpty) {
      // Might be a private video or different layout
      // Basic MVP implementation
      throw Exception('No video streams found. Video might be private.');
    }

    return VideoData(
      title: 'Facebook Video',
      id: 'fb_unknown',
      originalUrl: url,
      streams: streams,
      metadata: {'source': 'Facebook'},
      httpHeaders: {'User-Agent': userAgent},
    );
  }
}
