import 'dart:io';

import '../models/ocr_document.dart';

/// Abstraction over an on-device text recognizer so UI and tests can swap
/// engines.
abstract class OcrService {
  /// Runs text recognition against [image] and returns the raw recognized text.
  ///
  /// When [fast] is true, skips image enhancement for faster (lower-quality)
  /// OCR on low-end devices.
  Future<String> recognize(File image, {bool fast = false});

  /// Geometry-aware API. Implementations should preserve line and block bounds.
  /// The default implementation keeps existing test doubles and alternative
  /// engines working by wrapping [recognize].
  Future<OcrDocument> recognizeDocument(File image, {bool fast = false}) async {
    return OcrDocument(text: await recognize(image, fast: fast));
  }

  /// Releases any native resources held by the recognizer.
  Future<void> dispose();

  /// Pre-loads the on-device model. Default implementation is a no-op.
  Future<void> prewarm() async {}
}
