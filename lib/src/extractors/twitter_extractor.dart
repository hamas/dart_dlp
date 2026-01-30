/// Developed by Hamas | dart_dlp Engine
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils.dart';
import '../models/video_data.dart';
import '../core/exceptions.dart';
import 'base.dart';

class TwitterExtractor extends BaseExtractor with JsonScraper {
  static const _guestTokenUrl =
      'https://api.twitter.com/1.1/guest/activate.json';
  static const _bearerToken =
      'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'; // Standard guest bearer

  @override
  bool canHandle(String url) {
    return url.contains('twitter.com/') || url.contains('x.com/');
  }

  @override
  Future<VideoData> extract(String url,
      {Function(double p1)? onProgress}) async {
    onProgress?.call(0.1);

    // 1. Get Guest Token
    final guestToken = await _getGuestToken();
    onProgress?.call(0.3);

    // 2. Extract Tweet ID
    final id = _extractTweetId(url);

    // 3. Call GraphQL API
    // Correct URL structure with variables
    final variables = jsonEncode({
      'tweetId': id,
      'withCommunity': false,
      'includePromotedContent': false,
      'withVoice': false,
    });

    final features = jsonEncode({
      'creator_subscriptions_tweet_preview_api_enabled': true,
      'tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled':
          true,
      'video_content_playability_can_show_pixels_true_enabled': true,
      'longform_notetweets_consumption_enabled': true,
      'responsive_web_graphql_audio_mute_enabled': true,
      'responsive_web_graphql_timeline_navigation_enabled': true,
      'responsive_web_media_download_video_enabled': false,
    });

    final query = Uri.encodeQueryComponent(variables);
    final feats = Uri.encodeQueryComponent(features);

    final endpoint =
        'https://twitter.com/i/api/graphql/TweetResultByRestId?variables=$query&features=$feats';

    final userAgent = UserAgentManager.random;
    final apiResponse = await http.get(
      Uri.parse(endpoint),
      headers: {
        ...RequestFactory.commonHeaders,
        'Authorization': 'Bearer $_bearerToken',
        'x-guest-token': guestToken,
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
      },
    );

    if (apiResponse.statusCode != 200) {
      // Fallback to legacy scraping if API fails (often 403 on server IP)
      // return _fallbackScrape(url);
      throw SiteChangeException(
          'Twitter API refused connection: ${apiResponse.statusCode}');
    }

    onProgress?.call(0.6);
    final json = jsonDecode(apiResponse.body);

    final streams = <StreamInfo>[];
    try {
      final result = json['data']?['tweetResult']?['result'];
      final legacy = result?['legacy'];
      final entities = legacy?['extended_entities'] ??
          result?['core']?['user_results']?['result']?['legacy']
              ?['extended_entities'];

      final media = entities?['media'] as List?;
      if (media != null && media.isNotEmpty) {
        final variants = media.first['video_info']?['variants'] as List?;
        if (variants != null) {
          for (var v in variants) {
            final ct = v['content_type'];
            if (ct == 'video/mp4') {
              streams.add(StreamInfo(
                url: v['url'],
                quality: '${v['bitrate'] ?? 0}kbps',
                format: 'mp4',
              ));
            }
          }
        }
      }
    } catch (_) {
      // Silent fail on deep traverse, streams will be empty
    }

    streams.sort((a, b) => b.quality!.compareTo(a.quality!)); // Best first

    return VideoData(
      title: 'X Video $id',
      id: id,
      originalUrl: url,
      streams: streams,
      metadata: {'source': 'X', 'guest_token': guestToken},
      httpHeaders: {
        'User-Agent': userAgent,
        'Authorization': 'Bearer $_bearerToken',
        'x-guest-token': guestToken,
      },
    );
  }

  Future<String> _getGuestToken() async {
    final response = await http.post(
      Uri.parse(_guestTokenUrl),
      headers: {'Authorization': 'Bearer $_bearerToken'},
    );
    if (response.statusCode != 200)
      throw SiteChangeException('Failed to get Guest Token');
    final json = jsonDecode(response.body);
    return json['guest_token'];
  }

  String _extractTweetId(String url) {
    // https://x.com/user/status/123456789...
    final regex = RegExp(r'status\/(\d+)');
    return regex.firstMatch(url)?.group(1) ?? 'unknown';
  }
}
