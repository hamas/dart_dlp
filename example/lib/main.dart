import 'package:flutter/material.dart';
import 'package:dart_dlp/dart_dlp.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart DLP Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Dart DLP Extractor Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  final DlpEngine _engine = DlpEngine();
  String _status = 'Enter a URL to extract';
  bool _loading = false;
  VideoData? _videoData;

  Future<void> _extractVideo() async {
    if (_urlController.text.isEmpty) return;

    setState(() {
      _loading = true;
      _status = 'Extracting...';
      _videoData = null;
    });

    try {
      // 1. Extract Video Data
      final video = await _engine.extract(
        _urlController.text,
        onProgress: (p) {
          debugPrint('Extraction Progress: ${(p * 100).toStringAsFixed(0)}%');
        },
      );

      setState(() {
        _status = 'Success: ${video.title}';
        _videoData = video;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Video URL (YouTube, X, Instagram)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _extractVideo,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Extract Info'),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: TextStyle(
                color: _status.startsWith('Error') ? Colors.red : Colors.black,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_videoData != null) ...[
              Expanded(
                child: ListView(
                  children: [
                    if (_videoData!.metadata['thumbnail'] != null)
                      Image.network(
                        _videoData!.metadata['thumbnail']!,
                        height: 200,
                      ),
                    ListTile(
                      title: const Text('Title'),
                      subtitle: Text(_videoData!.title),
                    ),
                    ListTile(
                      title: const Text('Duration'),
                      subtitle: Text(
                        '${_videoData!.metadata['duration'] ?? 0}s',
                      ),
                    ),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Streams:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ..._videoData!.streams.map(
                      (s) => ListTile(
                        dense: true,
                        title: Text('Start Download ${s.quality}'),
                        subtitle: Text(s.url),
                        leading: const Icon(Icons.download),
                        onTap: () {
                          debugPrint('Selected stream: ${s.url}');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
