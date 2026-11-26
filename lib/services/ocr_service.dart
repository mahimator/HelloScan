import 'dart:io';

import '../models/ocr_document.dart';

/// Abstraction over an on-device recognizer so UI and tests can swap engines.
abstract class OcrService {
  /// Backwards-compatible plain-text API.
  Future<String> recognize(File image, {bool fast = false});

  /// Geometry-aware API. Implementations should preserve line and block bounds.
  /// The default keeps existing test doubles and alternative engines working.
  Future<OcrDocument> recognizeDocument(File image, {bool fast = false}) async {
    return OcrDocument(text: await recognize(image, fast: fast));
  }

  Future<void> dispose();

  /// Pre-loads the on-device model. Default implementation is a no-op.
  Future<void> prewarm() async {}
}
