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

  TextRecognizer get _engine =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Pre-loads (and downloads, if needed) the on-device recognition model so
  /// the first card scan isn't delayed by a ~30s model download. Safe to call
  /// multiple times; subsequent calls are no-ops once the model is ready.
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
    final originalExt = image.path.split('.').last.toLowerCase();

    print('HelloScan OCR: input=${image.path} ext=$originalExt size=${bytes.length}');

    // Try enhanced image first, fall back to raw if it produces no text.
    String? enhancedText;
    List<OcrBlock>? enhancedBlocks;

    try {
      // The enhancer caps the long edge before ML Kit sees the image.
      // Running it in a worker isolate avoids blocking animation and touch handling.
      final enhancedBytes = await compute(enhanceInIsolate, <Object>[bytes, fast]);

      // If the input was HEIC and the enhancer couldn't decode it, it returns
      // raw HEIC bytes. ML Kit can't read HEIC from a .jpg file, so convert
      // to JPEG if possible, otherwise use the original extension.
      final ext = _isHeic(originalExt) ? 'jpg' : originalExt;
      final directory = await getTemporaryDirectory();
      final temp = File(
        '${directory.path}/helloscan_ocr_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );

      try {
        await temp.writeAsBytes(enhancedBytes, flush: false);
        final recognized = await _engine.processImage(
          InputImage.fromFilePath(temp.path),
        );

        enhancedText = recognized.text;
        enhancedBlocks = recognized.blocks.map((block) {
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

        print('HelloScan OCR: enhanced text="${enhancedText?.substring(0, enhancedText!.length.clamp(0, 200))}"');
      } finally {
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {
          // Best-effort cleanup.
        }
      }
    } catch (e) {
      print('HelloScan OCR: enhanced OCR failed: $e');
    }

    // If enhanced OCR produced nothing, try the original raw image as fallback.
    if ((enhancedText ?? '').trim().isEmpty) {
      print('HelloScan OCR: enhanced produced no text, trying original image…');
      try {
        final directory = await getTemporaryDirectory();
        final temp = File(
          '${directory.path}/helloscan_ocr_orig_${DateTime.now().microsecondsSinceEpoch}.$originalExt',
        );
        try {
          await temp.writeAsBytes(bytes, flush: false);
          final recognized = await _engine.processImage(
            InputImage.fromFilePath(temp.path),
          );
          if ((recognized.text ?? '').trim().isNotEmpty) {
            enhancedText = recognized.text;
            enhancedBlocks = recognized.blocks.map((block) {
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
            print('HelloScan OCR: original text="${recognized.text?.substring(0, recognized.text!.length.clamp(0, 200))}"');
          } else {
            print('HelloScan OCR: original also produced no text');
          }
        } finally {
          try {
            if (await temp.exists()) await temp.delete();
          } catch (_) {
            // Best-effort cleanup.
          }
        }
      } catch (e) {
        print('HelloScan OCR: original OCR failed: $e');
      }
    }

    return OcrDocument(
      text: enhancedText ?? '',
      blocks: enhancedBlocks ?? const <OcrBlock>[],
    );
  }

  bool _isHeic(String ext) {
    return ext == 'heic' || ext == 'heif';
  }

  @override
  Future<void> dispose() async {
    final recognizer = _recognizer;
    _recognizer = null;
    await recognizer?.close();
  }
}
