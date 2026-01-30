/// Developed by Hamas | dart_dlp Engine
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils.dart';
import '../models/video_data.dart';
import '../core/exceptions.dart';
import 'base.dart';

class InstagramExtractor extends BaseExtractor with JsonScraper {
  @override
  bool canHandle(String url) {
    return url.contains('instagram.com/') || url.contains('instagr.am/');
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
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );

    onProgress?.call(0.3);

    if (response.statusCode != 200) {
      throw SiteChangeException(
          'Failed to load Instagram: ${response.statusCode}');
    }

    // Attempt to find shared data
    Map<String, dynamic>? data;
    try {
      // Strategy 1: check for "additionalDataLoaded" (common in new React builds)
      // window.__additionalDataLoaded('/p/Code/', {...});
      final regex =
          RegExp(r'window\.__additionalDataLoaded\([^,]+,\s*(\{.+?\})\);');
      final match = regex.firstMatch(response.body);
      if (match != null) {
        data = jsonDecode(match.group(1)!);
      } else {
        // Strategy 2: legacy sharedData
        try {
          data = extractJsonFromVar(response.body, 'window._sharedData');
        } catch (_) {}
      }

      // Strategy 3: GraphQL Fallback (if initial parse failed or login wall)
      if (data == null) {
        // Fallback logic placeholder
      }
    } catch (e) {
      // Allow falling through to check if we found partial data
    }

    if (data == null) throw ExtractionException('Instagram data was null');

    final streams = <StreamInfo>[];

    try {
      // Handle both "graphql" wrapper and direct data
      dynamic media = data['graphql']?['shortcode_media'] ?? data['items']?[0];

      // sometimes it's in entry_data.PostPage[0]... for sharedData
      if (media == null && data['entry_data'] != null) {
        media =
            data['entry_data']?['PostPage']?[0]?['graphql']?['shortcode_media'];
      }

      if (media != null &&
          (media['is_video'] == true || media['video_versions'] != null)) {
        final videoUrl = media['video_url'];
        if (videoUrl != null) {
          streams.add(StreamInfo(url: videoUrl, quality: 'HD', format: 'mp4'));
        }

        // Check for video_versions array (common in internal API)
        final versions = media['video_versions'] as List?;
        if (versions != null) {
          for (var v in versions) {
            streams.add(StreamInfo(
                url: v['url'],
                quality: '${v['width']}x${v['height']}',
                format: 'mp4',
                width: v['width'],
                height: v['height']));
          }
        }
      }
    } catch (_) {}

    return VideoData(
      title: 'Instagram Post',
      id: 'ig_${DateTime.now().millisecondsSinceEpoch}',
      originalUrl: url,
      streams: streams,
      metadata: {
        'source': 'Instagram',
        'has_data': true,
      },
      httpHeaders: {
        'User-Agent': userAgent,
        'Referer': 'https://www.instagram.com/',
      },
    );
  }
}
