/// Stub NativeMuxer for pure Dart environments (CLI).
class NativeMuxer {
  static Future<String> mux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    throw UnsupportedError(
        'NativeMuxer is not supported in pure Dart/CLI environments. '
        'It requires a Flutter environment with access to platform channels.');
  }
}
