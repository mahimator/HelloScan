import 'dart:io';

/// Abstraction over an on-device text recognizer so the UI (and tests) can
/// swap in a fake implementation without touching platform code.
abstract class OcrService {
  /// Runs text recognition against [image] and returns the raw recognized text.
  ///
  /// When [fast] is true, skips image enhancement for faster (lower-quality)
  /// OCR on low-end devices.
  Future<String> recognize(File image, {bool fast = false});

  /// Releases any native resources held by the recognizer.
  Future<void> dispose();

  /// Pre-loads the recognition model so the first scan is not delayed by a
  /// model download. Default implementation is a no-op.
  Future<void> prewarm() async {}
}
