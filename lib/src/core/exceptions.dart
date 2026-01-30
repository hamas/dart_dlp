/// Developed by Hamas | dart_dlp Engine
library dart_dlp_exceptions;

abstract class DlpException implements Exception {
  final String message;
  final String? code;

  DlpException(this.message, [this.code]);

  @override
  String toString() =>
      'DlpException: $message ${code != null ? "($code)" : ""}';
}

class SiteNotSupportedException extends DlpException {
  SiteNotSupportedException(String url)
      : super(
            'URL not valid or site not supported: $url', 'SITE_NOT_SUPPORTED');
}

class EncryptionFailedException extends DlpException {
  EncryptionFailedException(String detail)
      : super(
            'Failed to decrypt media signature: $detail', 'ENCRYPTION_FAILED');
}

class MuxingErrorException extends DlpException {
  MuxingErrorException(String detail)
      : super('Native muxing failed: $detail', 'MUX_ERROR');
}

class NetworkTimeoutException extends DlpException {
  NetworkTimeoutException(String url)
      : super('Network request timed out for: $url', 'TIMEOUT');
}

class ExtractionException extends DlpException {
  ExtractionException(String detail)
      : super('Extraction failed: $detail', 'EXTRACTION_ERROR');
}

class SiteChangeException extends DlpException {
  SiteChangeException(String detail)
      : super('Site layout changed: $detail', 'SITE_CHANGE');
}
