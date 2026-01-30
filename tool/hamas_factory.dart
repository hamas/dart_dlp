/// Developed by Hamas | dart_dlp Engine
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run bin/factory.dart <site_name>');
    return;
  }

  final siteName = args[0].toLowerCase();
  final className =
      '${siteName[0].toUpperCase()}${siteName.substring(1)}Extractor';
  final fileName = '${siteName}_extractor.dart';
  final filePath = 'lib/src/extractors/$fileName';

  final content = '''
/// Developed by Hamas | dart_dlp Engine
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'base.dart';
import '../models/video_data.dart';
import '../core/utils.dart'; 
import '../core/exceptions.dart';

class $className extends BaseExtractor with JsonScraper {
  // TODO: Update regex for $className
  static final RegExp _regex = RegExp(
    r'^https?:\/\/(?:www\.)?$siteName\.com\/',
    caseSensitive: false,
  );

  @override
  bool canHandle(String url) {
    return _regex.hasMatch(url);
  }

  @override
  Future<VideoData> extract(String url, {Function(double progress)? onProgress}) async {
    onProgress?.call(0.1);
    
    final headers = {'User-Agent': UserAgentManager.random};
    
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw NetworkTimeoutException('Failed to load page: \${response.statusCode}');
    }

    // TODO: Implement parsing logic for $siteName
    // Hint: Use extractJsonFromScript(response.body, 'script-id') if applicable
    
    onProgress?.call(1.0);

    return VideoData(
      title: '$siteName Video',
      id: 'unknown',
      originalUrl: url,
      streams: [],
      metadata: {},
    );
  }
}
''';

  final file = File(filePath);
  if (file.existsSync()) {
    print('Error: $filePath already exists.');
    exit(1);
  }

  file.createSync(recursive: true);
  file.writeAsStringSync(content);
  print('Factory: Generated $className in $filePath');
}
