import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocr_document.dart';
import 'image_enhancer.dart';
import 'ocr_service.dart';

/// Offline ML Kit OCR with bounded image preprocessing and spatial output.
class MlKitOcrService implements OcrService {
  MlKitOcrService();

  TextRecognizer? _recognizer;
  Future<void>? _prewarmFuture;

  TextRecognizer get _engine =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<void> prewarm() async {
    // Initializing ML Kit is cheap and does not block the UI isolate.
    // Keep it lazy until the first actual scan to avoid wasting memory.
    _engine;
  }

  @override
  Future<String> recognize(File image, {bool fast = false}) async {
    return (await recognizeDocument(image, fast: fast)).text;
  }

  @override
  Future<OcrDocument> recognizeDocument(File image, {bool fast = false}) async {
    final bytes = await image.readAsBytes();

    // The enhancer caps the long edge before ML Kit sees the image. Running
    // it in a worker isolate avoids blocking animation and touch handling.
    final enhanced = await compute(enhanceInIsolate, <Object>[bytes, fast]);
    final directory = await getTemporaryDirectory();
    final temp = File(
      '${directory.path}/helloscan_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    try {
      await temp.writeAsBytes(enhanced, flush: false);
      final recognized = await _engine.processImage(
        InputImage.fromFilePath(temp.path),
      );

      final blocks = recognized.blocks.map((block) {
        final lines = block.lines.map((line) {
          final rect = line.boundingBox;
          return OcrLine(
            text: line.text,
            left: rect.left.round(),
            top: rect.top.round(),
            right: rect.right.round(),
            bottom: rect.bottom.round(),
          );
        }).toList(growable: false);
        return OcrBlock(text: block.text, lines: lines);
      }).toList(growable: false);

      return OcrDocument(text: recognized.text, blocks: blocks);
    } finally {
      // Delete promptly: bulk scanning must not accumulate temporary images.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  @override
  Future<void> dispose() async {
    final recognizer = _recognizer;
    _recognizer = null;
    await recognizer?.close();
  }
}
