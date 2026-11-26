import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'image_enhancer.dart';
import 'ocr_service.dart';

/// On-device OCR backed by Google ML Kit.
///
/// ML Kit runs fully offline, which keeps card data on the device. The
/// recognizer is created lazily so widget tests never initialize a platform
/// channel.
class MlKitOcrService implements OcrService {
  MlKitOcrService();

  TextRecognizer? _recognizer;

  TextRecognizer get _engine =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Pre-loads (and downloads, if needed) the on-device recognition model so
  /// the first card scan isn't delayed by a ~30s model download. Safe to call
  /// multiple times; subsequent calls are no-ops once the model is ready.
  @override
  Future<void> prewarm() async {
    // Force lazy initialization of the recognizer (triggers model download).
    _engine;
  }

  @override
  Future<String> recognize(File image, {bool fast = false}) async {
    final bytes = await image.readAsBytes();
    // Run CPU-intensive image enhancement on a background isolate to prevent
    // "app not responding" (ANR) on large camera images.
    final enhanced = await compute(enhanceInIsolate, <Object>[bytes, fast]);

    final directory = await getTemporaryDirectory();
    final temp = File(
      '${directory.path}/helloscan_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    try {
      await temp.writeAsBytes(enhanced, flush: true);
      final input = InputImage.fromFilePath(temp.path);
      final result = await _engine.processImage(input);
      return result.text;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
