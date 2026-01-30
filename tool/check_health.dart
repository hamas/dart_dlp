/// Developed by Hamas | Health Monitor
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:dart_dlp/src/core/dlp_engine.dart';
import 'package:dart_dlp/src/extractors/youtube_extractor.dart';
import 'package:dart_dlp/src/extractors/tiktok_extractor.dart';
import 'package:dart_dlp/src/extractors/instagram_extractor.dart';
import 'package:dart_dlp/src/extractors/facebook_extractor.dart';
import 'package:dart_dlp/src/extractors/twitter_extractor.dart';
import 'package:dart_dlp/src/extractors/reddit_extractor.dart';
import 'package:dart_dlp/src/extractors/pinterest_extractor.dart';

void main() async {
  print('================================================================');
  print('               HAMAS-DLP MASS HEALTH MONITOR                    ');
  print('================================================================');
  print('| SITE           | STATUS | DETAILS                            |');
  print('|----------------|--------|------------------------------------|');

  // 1. Load Registry
  final samplesFile = File('test/samples.json');
  if (!samplesFile.existsSync()) {
    print('Error: test/samples.json not found.');
    exit(1);
  }
  final Map<String, dynamic> samples =
      jsonDecode(samplesFile.readAsStringSync());

  // 2. Initialize Engine & Register ALL Extractors
  final engine = DlpEngine();
  engine.registerExtractor(YouTubeExtractor());
  engine.registerExtractor(TikTokExtractor());
  engine.registerExtractor(InstagramExtractor());
  engine.registerExtractor(FacebookExtractor());
  engine.registerExtractor(TwitterExtractor());
  engine.registerExtractor(RedditExtractor());
  engine.registerExtractor(PinterestExtractor());

  int passed = 0;
  int failed = 0;
  final stopwatch = Stopwatch()..start();

  // 3. Concurrent Execution (Batch size: 10)
  final keys = samples.keys.toList();
  const batchSize = 10;

  for (var i = 0; i < keys.length; i += batchSize) {
    final end = (i + batchSize < keys.length) ? i + batchSize : keys.length;
    final batch = keys.sublist(i, end);

    final futures = batch.map((site) async {
      final url = samples[site]!;
      return await _checkSite(engine, site, url);
    });

    final results = await Future.wait(futures);

    for (var result in results) {
      if (result)
        passed++;
      else
        failed++;
    }
  }

  stopwatch.stop();

  // 4. Final Summary
  print('================================================================');
  print('Total Sites: ${samples.length}');
  print('\x1B[32mPASSED:      $passed\x1B[0m'); // Green
  print('\x1B[31mFAILED:      $failed\x1B[0m'); // Red
  print('Duration:    ${stopwatch.elapsed.inSeconds}s');
  print('================================================================');

  if (failed > 0) exit(1);
}

Future<bool> _checkSite(DlpEngine engine, String site, String url) async {
  // Pad site name for table alignment (max 14 chars)
  final siteName = site.padRight(14).substring(0, 14);

  try {
    final videoData = await engine.extract(url);

    if (videoData.streams.isEmpty &&
        videoData.videoOnlyStreams.isEmpty &&
        videoData.audioOnlyStreams.isEmpty) {
      throw Exception('No streams found');
    }

    // Success Row
    print(
        '| $siteName | \x1B[32m[PASS]\x1B[0m | ${videoData.title.padRight(34).substring(0, 34)} |');
    return true;
  } catch (e) {
    // Failure Row
    String errorMsg = e.toString().replaceAll('\n', ' ');
    if (errorMsg.length > 34) errorMsg = errorMsg.substring(0, 31) + '...';

    print('| $siteName | \x1B[31m[FAIL]\x1B[0m | $errorMsg |');
    return false;
  }
}
