import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils.dart'; // For UserAgentManager & JsonScraper
import '../core/exceptions.dart';
import '../models/video_data.dart';
import 'base.dart';

class YouTubeExtractor extends BaseExtractor with JsonScraper {
  static final RegExp _ytRegex = RegExp(
    r'^https?:\/\/(?:www\.)?(?:youtube\.com\/(?:watch\?v=|embed\/|v\/)|youtu\.be\/)([\w-]{11})',
    caseSensitive: false,
  );

  static final RegExp _playerJsRegex = RegExp(
      r'\/s\/player\/([a-zA-Z0-9_.-]+)\/player_ias.vflset\/[a-zA-Z0-9_.-]+\/base\.js');

  // Regex to capture the definition of the transformation function
  // e.g. var a={...} or a={...}
  // This is highly heuristic and depends on common minification patterns.

  @override
  bool canHandle(String url) {
    return _ytRegex.hasMatch(url);
  }

  @override
  @override
  Future<VideoData> extract(String url,
      {Function(double progress)? onProgress}) async {
    onProgress?.call(0.1);
    final response = await http.get(Uri.parse(url), headers: {
      'User-Agent': UserAgentManager.random, // Use real UA
    });

    if (response.statusCode != 200) {
      throw SiteChangeException(
          'Failed to load YouTube page: ${response.statusCode}');
    }
    final body = response.body;

    // 1. Extract Player Response (ytInitialPlayerResponse)
    onProgress?.call(0.2);
    final playerResponse = await _extractPlayerResponse(body);
    final videoDetails = playerResponse['videoDetails'];
    if (videoDetails == null)
      throw ExtractionException('Could not parse video details');

    final title = videoDetails['title'] ?? 'Unknown Title';
    final id = videoDetails['videoId'] ??
        _ytRegex.firstMatch(url)?.group(1) ??
        'unknown';
    final durationStr = videoDetails['lengthSeconds'];
    final duration =
        durationStr != null ? Duration(seconds: int.parse(durationStr)) : null;
    final thumb = videoDetails['thumbnail']?['thumbnails']?.last?['url'];

    // 2. Extract Streams
    onProgress?.call(0.3);
    final streamingData = playerResponse['streamingData'];
    if (streamingData == null)
      throw ExtractionException('No streaming data found');

    final formats = <Map<String, dynamic>>[
      ...?streamingData['formats'],
      ...?streamingData['adaptiveFormats'],
    ];

    // 3. Resolve Cipher (if needed)
    final cipherFormats = formats
        .where((f) => f['signatureCipher'] != null || f['cipher'] != null)
        .toList();

    if (cipherFormats.isNotEmpty) {
      onProgress?.call(0.4);
      final playerUrl = _extractPlayerUrl(body);
      if (playerUrl != null) {
        // Fetch and Parse Player JS for Decryption
        final playerJs = await http.get(Uri.parse(playerUrl));
        final cipherOps = _parseCipherOperations(playerJs.body);
        final decipherFuncName = _parseDecipherFunctionName(playerJs.body);

        if (cipherOps.isNotEmpty && decipherFuncName != null) {
          for (var f in cipherFormats) {
            final cipher = f['signatureCipher'] ?? f['cipher'];
            final params = Uri.splitQueryString(cipher);
            final sig = params['s'];
            final sp = params['sp'] ?? 'sig';
            final urlBase = params['url'];

            if (sig != null && urlBase != null) {
              final decryptedSig =
                  _applyCipher(sig, cipherOps, decipherFuncName, playerJs.body);
              f['url'] = '$urlBase&$sp=$decryptedSig';
            }
          }
        }
      }
    }

    // 4. Build VideoData
    onProgress?.call(0.8);
    final streams = <StreamInfo>[];
    final videoOnly = <StreamInfo>[];
    final audioOnly = <StreamInfo>[];

    for (var f in formats) {
      if (f['url'] == null) continue; // Skip if decryption failed

      final mime = f['mimeType'] ?? '';
      final width = f['width'];
      final height = f['height'];
      final quality = f['qualityLabel'] ?? 'unknown';
      final url = f['url'];

      final stream = StreamInfo(
        url: url,
        quality: quality,
        format: mime.split(';').first,
        width: width,
        height: height,
      );

      streams.add(stream);

      if (mime.startsWith('video/')) {
        if (f['audioQuality'] == null) {
          videoOnly.add(stream); // Adaptive Video
        } else {
          // Muxed content (usually 720p or lower)
        }
      } else if (mime.startsWith('audio/')) {
        audioOnly.add(stream);
      }
    }

    return VideoData(
      title: title,
      id: id,
      originalUrl: url,
      streams: streams,
      videoOnlyStreams: videoOnly,
      audioOnlyStreams: audioOnly,
      metadata: {
        'duration': duration?.inSeconds,
        'thumbnail': thumb,
      },
    );
  }

  // --- Helpers ---

  // --- Helpers ---

  Future<Map<String, dynamic>> _extractPlayerResponse(String html) async {
    // 1. Standard var assignment
    var regex = RegExp(r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\});',
        multiLine: true);
    var match = regex.firstMatch(html);
    if (match != null) return extractJson(match.group(1)!);

    // 2. Window assignment
    regex = RegExp(r'window\["ytInitialPlayerResponse"\]\s*=\s*(\{.+?\});');
    match = regex.firstMatch(html);
    if (match != null) return extractJson(match.group(1)!);

    // 3. Fallback: ytInitialPlayerResponse = (no var)
    regex = RegExp(r'(?:^|;)ytInitialPlayerResponse\s*=\s*(\{.+?\});');
    match = regex.firstMatch(html);
    if (match != null) return extractJson(match.group(1)!);

    throw ExtractionException('Could not locate player response');
  }

  String? _extractPlayerUrl(String html) {
    // 1. Direct Regex
    var match = _playerJsRegex.firstMatch(html);
    if (match != null) return 'https://www.youtube.com${match.group(0)}';

    // 2. Script Src Regex
    final regex = RegExp(r'<script\s+src="([^"]+base\.js)"');
    final m = regex.firstMatch(html);
    if (m != null) return 'https://www.youtube.com${m.group(1)}';

    return null;
  }

  // --- Cipher Logic ---

  String? _parseDecipherFunctionName(String js) {
    // Pattern: a=a.split("");B.C(a,3);B.D(a,2);...
    // matches `var a` or just `a`
    final regex = RegExp(
        r'\b([a-zA-Z0-9$]+)=function\([a-zA-Z0-9$]+\)\{([a-zA-Z0-9$]+)=\2\.split\(""\);(.+?);return \2\.join\(""\)\}');
    return regex.firstMatch(js)?.group(1);
  }

  List<Function(List<String>)> _parseCipherOperations(String js) {
    final decipherFuncBody = _extractDecipherFuncBody(js);
    if (decipherFuncBody == null) return [];

    // Find called object name: "B.C(a,3)"
    final calledObjectName = RegExp(r'([a-zA-Z0-9$]+)\.[a-zA-Z0-9$]+\(')
        .firstMatch(decipherFuncBody)
        ?.group(1);
    if (calledObjectName == null) return [];

    // Extract helper object definition
    // Matches: var B={...};  OR  B={...};
    // Note: The "var" might be missing or separated.
    final helperObjRegex = RegExp(
        // Capture group 1: Body of the object
        // Allow optional 'var ', logic name, equals, brace
        '(?:var\\s+)?$calledObjectName\\s*=\\s*\\{(.*?)\\};',
        multiLine: true,
        dotAll: true);

    final helperObjMatch = helperObjRegex.firstMatch(js);
    if (helperObjMatch == null) return [];

    final helperBody = helperObjMatch.group(1)!;

    // Parse methods - Robust regexes handling whitespace
    final reverseRegex =
        RegExp(r'([a-zA-Z0-9$]+)\s*:\s*function\(\w+\)\{\w+\.reverse\(\)\}');
    final sliceRegex = RegExp(
        r'([a-zA-Z0-9$]+)\s*:\s*function\(\w+,(\w+)\)\{\w+\.splice\(0,\2\)\}');
    final swapRegex = RegExp(
        r'([a-zA-Z0-9$]+)\s*:\s*function\(\w+,(\w+)\)\{var\s+\w+=\w+\[0\];\w+\[0\]=\w+\[\2%[\w+\.]*length\];\w+\[\2%[\w+\.]*length\]=\w+\}');

    final reverseMethod = reverseRegex.firstMatch(helperBody)?.group(1);
    final sliceMethod = sliceRegex.firstMatch(helperBody)?.group(1);
    final swapMethod = swapRegex.firstMatch(helperBody)?.group(1);

    final operations = <Function(List<String>)>[];

    // Parse the calls in order from decipher body
    final callRegex = RegExp(
        // Escape object name
        '${RegExp.escape(calledObjectName)}\\.([a-zA-Z0-9\$]+)\\(a,(\\d+)\\)');
    final matches = callRegex.allMatches(decipherFuncBody);

    for (var m in matches) {
      final method = m.group(1);
      final param = int.parse(m.group(2)!);

      if (method == reverseMethod) {
        operations.add((list) {
          final reversed = list.reversed.toList();
          list.clear();
          list.addAll(reversed);
        });
      } else if (method == sliceMethod) {
        operations.add((list) => list.removeRange(0, param));
      } else if (method == swapMethod) {
        operations.add((list) {
          final c = list[0];
          final index = param % list.length;
          list[0] = list[index];
          list[index] = c;
        });
      }
    }

    return operations;
  }

  String? _extractDecipherFuncBody(String js) {
    // Find the main function that splits, joins, and has intermediate calls
    final regex = RegExp(
        r'[a-zA-Z0-9$]+=function\([a-zA-Z0-9$]+\)\{([a-zA-Z0-9$]+)=\1\.split\(""\);(.+?);return \1\.join\(""\)\}');
    return regex
        .firstMatch(js)
        ?.group(2); // Group 2 is the body calls "B.C(a,3)..."
  }

  String _applyCipher(String sig, List<Function(List<String>)> ops,
      String funcName, String js) {
    var chars = sig.split('');
    for (var op in ops) {
      op(chars);
    }
    return chars.join('');
  }

  Map<String, dynamic> extractJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (e) {
      return {};
    }
  }
}
