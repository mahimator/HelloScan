import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device OCR service backed by a small quantized TFLite model.
///
/// Drop a quantized (INT8) text-recognition model into
/// `assets/models/ocr.tflite` (and an optional `assets/models/labels.txt`)
/// then call [init] before [recognize].
///
/// The service is intentionally defensive: if the model isn't bundled yet,
/// [recognize] returns an empty list and the UI falls back to manual entry.
class OcrService {
  static final OcrService instance = OcrService._();
  OcrService._();

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _initialized = false;

  /// Input tensor shape expected by the model: [batch, height, width, channels].
  final List<int> inputShape = const [1, 32, 128, 1];

  /// Blank/CTC label index. Set this to match your labels file (usually the
  /// last index or a dedicated "_" entry).
  int blankIndex = 0;

  Future<bool> init({
    String modelPath = 'assets/models/ocr.tflite',
    String labelsPath = 'assets/models/labels.txt',
  }) async {
    try {
      final interpreter = await Interpreter.fromAsset(modelPath);
      _interpreter = interpreter;

      final labels = await rootBundle.loadString(labelsPath);
      _labels = labels
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      _initialized = true;
      return true;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  /// Recognize text lines in an image. Returns one string per detected line.
  ///
    /// Pre-processing converts to grayscale, resizes to [inputShape], and
    /// normalizes to the [-1, 1] range typical for quantized CRNN models.
    /// Post-processing runs greedy CTC decoding over the argmax sequence.
  Future<List<String>> recognize(File imageFile) async {
    if (!_initialized || _interpreter == null) return [];

    try {
      final bytes = imageFile.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return [];

      final input = _preprocess(decoded);
      final output = _interpreter!.run(input);

      // output shape: [batch, time, numClasses] typically
      final lines = _ctcGreedyDecode(output);
      return lines.where((l) => l.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Convert a [img.Image] to a tensor matching [inputShape] and the model's
  /// input dtype (float32 [-1,1] or quantized uint8/int8 [0,255]).
  dynamic _preprocess(img.Image image) {
    final h = inputShape[1];
    final w = inputShape[2];
    final c = inputShape[3];
    final total = inputShape.reduce((a, b) => a * b);

    final resized = img.copyResize(image, width: w, height: h);
    final gray = img.grayscale(resized);

    final inputTensor = _interpreter!.getInputTensor(0);
    final isQuantized = inputTensor.type == TensorType.uint8 ||
        inputTensor.type == TensorType.int8;

    if (isQuantized) {
      final buffer = Uint8List(total);
      int idx = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final v = gray.getPixel(x, y).r;
          buffer[idx++] = v;
          for (int ch = 1; ch < c; ch++) {
            buffer[idx++] = v;
          }
        }
      }
      return buffer;
    }

    final buffer = Float32List(total);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Normalize to [-1, 1].
        final v = (gray.getPixel(x, y).r / 127.5) - 1.0;
        buffer[idx++] = v;
        for (int ch = 1; ch < c; ch++) {
          buffer[idx++] = v;
        }
      }
    }
    return buffer;
  }

  /// Greedy CTC decode: argmax per timestep, collapse repeats, drop blank.
  ///
  /// [tflite_flutter] returns `dynamic`, so we read the output structure
  /// defensively. Match [inputShape] / output shape to your actual model.
  List<String> _ctcGreedyDecode(dynamic output) {
    List<dynamic> sequences;
    if (output is List) {
      sequences = output.cast<dynamic>();
    } else {
      // Single flat buffer (quantized output). Without the model's time x
      // numClasses shape we cannot reshape it here; return empty and let the
      // user wire outputShape to their model.
      return [];
    }

    final lines = <String>[];
    for (final sequence in sequences) {
      final timesteps = sequence as List<dynamic>;
      final chars = <String>[];
      int? previous;
      for (final timestep in timesteps) {
        final scores = timestep as List<dynamic>;
        int best = 0;
        num bestScore = scores[0] as num;
        for (int i = 1; i < scores.length; i++) {
          final s = scores[i] as num;
          if (s > bestScore) {
            bestScore = s;
            best = i;
          }
        }
        if (best != blankIndex && best != previous) {
          if (best < _labels.length) {
            chars.add(_labels[best]);
          } else {
            chars.add('?');
          }
        }
        previous = best;
      }
      final line = chars.join().trim();
      if (line.isNotEmpty) lines.add(line);
    }
    return lines;
  }

  /// Extract structured card fields from raw OCR text lines using heuristics.
  ///
    /// This is a review-first helper: it pre-fills fields, but the user must
    /// confirm/edit them before the card is marked reviewed.
  static Map<String, String> parseFields(List<String> lines) {
    final emailRegExp = RegExp(
      r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
      caseSensitive: false,
    );
    final phoneRegExp = RegExp(
      r'^[\+]?[(]?[0-9]{1,3}[)]?[-\s\.]?[(]?[0-9]{1,4}[)]?[-\s\.]?[0-9]{1,4}[-\s\.]?[0-9]{1,9}$',
    );
    final webRegExp = RegExp(
      r'(https?://|www\.)|(\.(com|org|net|co|io|biz|app)\b)',
      caseSensitive: false,
    );

    String? email;
    String? phone;
    String? website;
    final others = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (email == null && emailRegExp.hasMatch(trimmed)) {
        email = trimmed;
        continue;
      }
      if (phone == null && phoneRegExp.hasMatch(trimmed)) {
        phone = trimmed;
        continue;
      }
      if (website == null && webRegExp.hasMatch(trimmed)) {
        website = trimmed;
        continue;
      }
      others.add(trimmed);
    }

    // Heuristic field assignment for the remaining text lines.
    String? name;
    String? title;
    String? company;
    String? address;

    if (others.isNotEmpty) {
      name = others.first;
      if (others.length > 1) {
        // The line after the name is often the designation/title.
        title = others[1];
      }
      if (others.length > 2) {
        company = others.sublist(2).take(others.length - 2).join(' ');
      }
      // Any line containing digits/road-ish tokens is treated as address.
      final addrIdx = others.indexWhere((l) => RegExp(r'\d').hasMatch(l));
      if (addrIdx != -1) {
        address = others.sublist(addrIdx).join(', ');
      } else if (others.length > 3) {
        address = others.last;
      }
    }

    return {
      'name': name ?? '',
      'title': title ?? '',
      'company': company ?? '',
      'email': email ?? '',
      'phone': phone ?? '',
      'website': website ?? '',
      'address': address ?? '',
    };
  }
}
