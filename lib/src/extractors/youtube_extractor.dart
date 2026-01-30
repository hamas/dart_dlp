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
    final userAgent = UserAgentManager.random;
    onProgress?.call(0.1);
    final response = await http.get(Uri.parse(url), headers: {
      'User-Agent': userAgent, // Use real UA
    });

    if (response.statusCode != 200) {
      throw SiteChangeException(
          'Failed to load YouTube page: ${response.statusCode}');
    }
    final body = response.body;

    // Extract Cookies
    String cookieHeader = '';
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      // Simple parser: take everything before first semicolon of each cookie?
      // 'http' joins multiple Set-Cookie headers with comma.
      // But dates also have commas. This is messy.
      // Heuristic: generic regex for "name=value"
      final cookieMatches =
          RegExp(r'([a-zA-Z0-9_-]+)=([^;,\s]+)').allMatches(setCookie);
      final validCookies = <String>[];
      final attributes = {
        'path',
        'domain',
        'expires',
        'max-age',
        'secure',
        'httponly',
        'samesite',
        'priority'
      };

      for (final m in cookieMatches) {
        final key = m.group(1)!;
        final value = m.group(2)!;
        if (!attributes.contains(key.toLowerCase())) {
          validCookies.add('$key=$value');
        }
      }
      cookieHeader = validCookies.toSet().join('; ');
    }

    if (cookieHeader.isNotEmpty) {
      print('      [Debug] Extracted Cookies: ${cookieHeader.length} chars');
    }

    // Extract Video ID from URL first
    final id = _ytRegex.firstMatch(url)?.group(1) ?? 'unknown';

    // 1. Extract Player Response (ytInitialPlayerResponse)
    onProgress?.call(0.2);
    var playerResponse = await _extractPlayerResponse(body);

    // Check for availability
    if (playerResponse['playabilityStatus']?['status'] == 'ERROR' ||
        playerResponse['playabilityStatus']?['status'] == 'LOGIN_REQUIRED') {
      print(
          '      [Debug] Initial extraction unplayable. Trying Android client fallback...');
      // Attempt to fetch player response using Android Client API
      final androidResponse = await _fetchAndroidPlayerResponse(id, userAgent);
      if (androidResponse.isNotEmpty) {
        playerResponse = androidResponse;
      }
    }

    // Debug keys
    print(
        '      [Debug] playerResponse keys: ${playerResponse.keys.join(', ')}');

    final videoDetails = playerResponse['videoDetails'];
    if (videoDetails == null) {
      if (playerResponse.containsKey('playabilityStatus')) {
        final status = playerResponse['playabilityStatus']?['status'];
        final reason = playerResponse['playabilityStatus']?['reason'];
        print('      [Debug] Playability Status: $status, Reason: $reason');
      }
      throw ExtractionException(
          'Could not parse video details (Playability Error)');
    }

    final title = videoDetails['title'] ?? 'Unknown Title';
    final durationStr = videoDetails['lengthSeconds'];
    final duration =
        durationStr != null ? Duration(seconds: int.parse(durationStr)) : null;
    final thumb = videoDetails['thumbnail']?['thumbnails']?.last?['url'];

    // 3. Extract Streams & Check for Adaptive Formats
    onProgress?.call(0.3);
    var streamingData = playerResponse['streamingData'];
    var formats = <Map<String, dynamic>>[
      ...?streamingData?['formats'],
      ...?streamingData?['adaptiveFormats'],
    ];

    final hasAdaptive = streamingData != null &&
        streamingData['adaptiveFormats'] != null &&
        (streamingData['adaptiveFormats'] as List).isNotEmpty;

    if (!hasAdaptive) {
      print(
          '      [Debug] No adaptive formats in web response. Fetching Android fallback...');
      final androidResponse = await _fetchAndroidPlayerResponse(id, userAgent);
      if (androidResponse.isNotEmpty &&
          androidResponse['streamingData'] != null) {
        playerResponse = androidResponse;
        streamingData = androidResponse['streamingData'];
        formats = [
          ...?streamingData?['formats'],
          ...?streamingData?['adaptiveFormats'],
        ];
      }
    }

    if (formats.isEmpty) throw ExtractionException('No streaming data found');

    if (formats.isNotEmpty) {
      for (var f in formats) {
        final hasUrl = f['url'] != null;
        final hasCipher = f['signatureCipher'] != null || f['cipher'] != null;
        if (!hasUrl && !hasCipher) {
          // print('      [Debug] Missing URL/Cipher: itag ${f['itag']}, keys: ${f.keys.join(', ')}');
        }
      }

      final first = formats.first;
      final targetUrl =
          first['url'] ?? (first['signatureCipher'] ?? first['cipher']);
      if (targetUrl != null) {
        final uri = Uri.parse(targetUrl.toString().contains('url=')
            ? Uri.splitQueryString(targetUrl.toString())['url']!
            : targetUrl.toString());
        if (uri.queryParameters.containsKey('n')) {
          print(
              '      [Debug] Found "n" parameter in URL: ${uri.queryParameters['n']}');
        } else {
          print('      [Debug] No "n" parameter found in URL query.');
        }
      }
    }

    // 3. Resolve Cipher & N-Parameter (if needed)
    final playerUrl = _extractPlayerUrl(body);
    String? playerJsBody;

    if (playerUrl != null) {
      final playerJsResponse = await http.get(Uri.parse(playerUrl), headers: {
        'User-Agent': userAgent,
        'Referer': 'https://www.youtube.com/',
      });
      playerJsBody = playerJsResponse.body;
    }

    onProgress?.call(0.4);
    if (playerJsBody != null) {
      final cipherOps = _parseCipherOperations(playerJsBody);
      final decipherFuncName = _parseDecipherFunctionName(playerJsBody);
      final nFuncName = _findNFunctionName(playerJsBody);

      for (var f in formats) {
        String? targetUrl = f['url'];
        String sigParamName = 'sig';

        // Signature Cipher
        if (f['signatureCipher'] != null || f['cipher'] != null) {
          final cipher = f['signatureCipher'] ?? f['cipher'];
          final params = Uri.splitQueryString(cipher);
          final sig = params['s'];
          sigParamName = params['sp'] ?? 'sig';
          final urlBase = params['url'];

          if (sig != null &&
              urlBase != null &&
              cipherOps.isNotEmpty &&
              decipherFuncName != null) {
            final decryptedSig =
                _applyCipher(sig, cipherOps, decipherFuncName, playerJsBody);
            targetUrl = '$urlBase&$sigParamName=$decryptedSig';
          } else {
            print(
                '      [Debug] Cipher failed for itag ${f['itag']}: sig=$sig, urlBase=$urlBase, ops=${cipherOps.length}, func=$decipherFuncName');
          }
        }

        // N-Parameter Deciphering
        if (targetUrl != null && nFuncName != null) {
          final uri = Uri.parse(targetUrl);
          final n = uri.queryParameters['n'];
          if (n != null) {
            final decipheredN = _decipherN(n, nFuncName, playerJsBody);
            if (decipheredN != n) {
              final newParams = Map<String, String>.from(uri.queryParameters);
              newParams['n'] = decipheredN;
              targetUrl = uri.replace(queryParameters: newParams).toString();
            }
          }
        }
        f['url'] = targetUrl;
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
      final qualityLabel = f['qualityLabel'] ?? (f['quality'] ?? 'unknown');
      final url = f['url'];

      final stream = StreamInfo(
        url: url,
        quality: qualityLabel,
        format: mime.split(';').first,
        width: width is int
            ? width
            : (width != null ? int.tryParse(width.toString()) : null),
        height: height is int
            ? height
            : (height != null ? int.tryParse(height.toString()) : null),
      );

      streams.add(stream);

      if (mime.startsWith('video/')) {
        final isAdaptive = f['audioQuality'] == null;
        if (isAdaptive) {
          videoOnly.add(stream);
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
      httpHeaders: {
        'User-Agent': userAgent,
        'Referer': 'https://www.youtube.com/',
        if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
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

    // 4. ytInitialPlayerResponse in ytcfg.set
    regex = RegExp(r'ytcfg\.set\(\{.*?"player_response":\s*(\{.+?\})\}\);');
    match = regex.firstMatch(html);
    if (match != null) return extractJson(match.group(1)!);

    // Debug: Log snippet if failed
    print(
        '      [Debug] Player Response extraction failed. HTML length: ${html.length}');
    if (html.contains('playerResponse')) {
      print('      [Debug] Found "playerResponse" keyword but regex failed.');
    }

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

  Future<Map<String, dynamic>> _fetchAndroidPlayerResponse(
      String videoId, String userAgent) async {
    // TVHTML5 client is often the most permissive for adaptive streams
    final url =
        'https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlS9W6Sg6o5_6o5_6o5_6o5_6o5';
    final payload = {
      "context": {
        "client": {
          "clientName": "TVHTML5",
          "clientVersion": "7.20230405.08.01",
          "hl": "en",
          "gl": "US",
        }
      },
      "videoId": videoId,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': userAgent,
          'Referer': 'https://www.youtube.com/',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('      [Debug] TVHTML5 Innertube fallback failed: $e');
    }
    return {};
  }

  String? _findNFunctionName(String js) {
    // Pattern: .get("n")&&(b=b.get("n"),c=aL[0](b),a.set("n",c))
    // We look for the function call after .set("n",
    final regex = RegExp(r'\.set\("n",([a-zA-Z0-9$]+)\(');
    return regex.firstMatch(js)?.group(1);
  }

  String _decipherN(String n, String funcName, String js) {
    // For now, this is a placeholder. Implementing a full JS interpreter in Dart
    // for the 'n' parameter is complex. yt-dlp uses a mini-interpreter.
    // We will attempt to find simple patterns or log the body.
    print(
        '      [Debug] N-Parameter deciphering required for func: $funcName (N: ${n.substring(0, 5)}...)');

    // Fallback: until we have a pure-Dart JS interpreter, we return n
    // and attempt download. If 403 persists, the interpreter is mandatory.
    return n;
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
      final cleaned = raw.trim();
      return jsonDecode(cleaned);
    } catch (e) {
      return {};
    }
  }
}
