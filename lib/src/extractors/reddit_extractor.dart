/// Developed by Hamas | dart_dlp Engine
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils.dart';
import '../models/video_data.dart';
import 'base.dart';

// Reddit is great: just append .json
class RedditExtractor extends BaseExtractor {
  @override
  bool canHandle(String url) {
    return url.contains('reddit.com/r/') || url.contains('redd.it/');
  }

  @override
  Future<VideoData> extract(String url,
      {Function(double p1)? onProgress}) async {
    onProgress?.call(0.1);

    // Normalize URL
    var jsonUrl = url.split('?')[0];
    if (!jsonUrl.endsWith('.json')) {
      if (jsonUrl.endsWith('/')) {
        jsonUrl += '.json';
      } else {
        jsonUrl += '/.json';
      }
    }

    final response = await http.get(
      Uri.parse(jsonUrl),
      headers: {'User-Agent': UserAgentManager.random},
    );

    onProgress?.call(0.5);

    if (response.statusCode != 200)
      throw Exception('Failed to fetch Reddit JSON');

    final json = jsonDecode(response.body);
    // Structure: [0].data.children[0].data
    final postData = json[0]['data']['children'][0]['data'];

    final title = postData['title'] ?? 'Reddit Video';
    final isVideo = postData['is_video'] ?? false;

    if (!isVideo) throw Exception('Post is not a video');

    final media = postData['secure_media']?['reddit_video'];
    if (media == null) throw Exception('No secure media found');

    final fallbackUrl = media['fallback_url'];
    // Reddit separates audio usually (Dash). fallback_url is often video only or combined.
    // Usually need DASH playlist for full quality.

    return VideoData(
      title: title,
      id: postData['id'],
      originalUrl: url,
      streams: [StreamInfo(url: fallbackUrl, quality: 'auto', format: 'mp4')],
      metadata: {'source': 'Reddit', 'jsonUrl': jsonUrl},
    );
  }
}
