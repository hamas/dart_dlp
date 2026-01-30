/// Developed by Hamas | dart_dlp Engine
import 'package:test/test.dart';
import 'package:dart_dlp/src/core/dlp_engine.dart';
import 'package:dart_dlp/src/extractors/base.dart';
import 'package:dart_dlp/src/models/video_data.dart';

// Mock Extractor
class MockExtractor extends BaseExtractor {
  @override
  bool canHandle(String url) => url.contains('mock');

  @override
  Future<VideoData> extract(String url,
      {Function(double p)? onProgress}) async {
    return VideoData(
      title: 'Mock Video',
      id: '123',
      originalUrl: url,
      streams: [],
      metadata: {},
    );
  }
}

void main() {
  group('DlpEngine Tests', () {
    late DlpEngine engine;

    setUp(() {
      engine = DlpEngine();
      engine.registerExtractor(MockExtractor());
    });

    test('analyze finds correct extractor', () {
      final extractor = engine.analyze('https://mock.com/video');
      expect(extractor, isA<MockExtractor>());
    });

    test('analyze throws exception for unknown URL', () {
      expect(
        () => engine.analyze('https://unknown.com'),
        throwsA(isA<Exception>()),
      );
    });

    test('extract calls extractor logic', () async {
      final data = await engine.extract('https://mock.com/video');
      expect(data.title, 'Mock Video');
      expect(data.id, '123');
    });
  });
}
