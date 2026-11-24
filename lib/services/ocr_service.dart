import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'ocr_config.dart';
import '../models/ocr_result.dart';

/// On-device OCR pipeline for business cards.
///
/// Two-stage: [detect] finds text regions, [recognize] reads each region.
/// Optimized for low-to-mid range Android phones:
///   * INT8 quantized TFLite models
///   * NNAPI delegate (NPU/DSP) with CPU fallback
///   * Bounded detection count to cap RAM usage
///
/// The service is defensive: if no model is bundled, [recognizeCard] returns
/// empty results and the app falls back to manual entry.
class OcrService {
  static final OcrService instance = OcrService._();
  OcrService._();

  OcrConfig? _config;
  Interpreter? _detInterpreter;
  Interpreter? _recInterpreter;
  List<String> _labels = [];
  bool _initialized = false;

  /// Initialize the detection and recognition interpreters.
  ///
  /// [detModelPath] and [recModelPath] are file system paths to the downloaded
  /// INT8 TFLite models (typically in the app documents directory).
  /// [labelsPath] is a file system path to the labels text file.
  Future<bool> init({
    required String detModelPath,
    required String recModelPath,
    required String labelsPath,
    OcrConfig? config,
  }) async {
    _config = config ?? const OcrConfig();

    try {
      // Detection interpreter
      final detOpts = InterpreterOptions();
      if (_config!.useNnapi) {
        detOpts.addDelegate(NnapiDelegate());
      }
      _detInterpreter = await Interpreter.fromFile(
        File(detModelPath),
        options: detOpts,
      );

      // Recognition interpreter
      final recOpts = InterpreterOptions();
      if (_config!.useNnapi) {
        recOpts.addDelegate(NnapiDelegate());
      }
      _recInterpreter = await Interpreter.fromFile(
        File(recModelPath),
        options: recOpts,
      );

      final labels = await File(labelsPath).readAsString();
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

  /// Run the full OCR pipeline on a card's front (and optional back).
  ///
  /// Returns recognized lines plus a merged field map pre-filled for review.
  /// The caller should display the fields and let the user edit before
  /// marking the card reviewed.
  Future<OcrCardResult> recognizeCard({
    required File front,
    File? back,
  }) async {
    if (!_initialized) {
      return OcrCardResult(
        front: OcrImageResult(lines: [], processingTimeMs: 0),
        mergedFields: {},
      );
    }

    final stopwatch = math.Stopwatch()..start();

    final frontResult = await _recognizeImage(front);
    OcrImageResult? backResult;
    if (back != null) {
      backResult = await _recognizeImage(back);
    }

    stopwatch.stop();

    final merged = _mergeFields(frontResult.lines, backResult?.lines ?? []);

    return OcrCardResult(
      front: frontResult,
      back: backResult,
      mergedFields: merged,
    );
  }

  /// Detect text boxes on an image, then recognize each box.
  Future<OcrImageResult> _recognizeImage(File imageFile) async {
    final stopwatch = math.Stopwatch()..start();

    try {
      final bytes = imageFile.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return OcrImageResult(lines: [], processingTimeMs: 0);
      }

      final detInput = _preprocessDet(decoded);
      final detOutput = _detInterpreter!.run(detInput);

      final boxes = _parseDetectionBoxes(detOutput, decoded.width, decoded.height);
      final filtered = _filterAndNms(boxes);

      final lines = <OcrLine>[];
      for (final box in filtered.take(_config!.maxDetections)) {
        final crop = _cropCardRegion(decoded, box);
        if (crop == null) continue;

        final recInput = _preprocessRec(crop);
        final recOutput = _recInterpreter!.run(recInput);

        final text = _ctcDecode(recOutput);
        if (text.trim().isEmpty) continue;

        final confidence = _estimateConfidence(recOutput);
        lines.add(OcrLine(
          text: text,
          confidence: confidence,
          box: [box.x1, box.y1, box.x2, box.y2],
        ));
      }

      // Sort top-to-bottom, then left-to-right.
      lines.sort((a, b) {
        final dy = (a.centerY - b.centerY).abs();
        if (dy > 0.02) return a.centerY.compareTo(b.centerY);
        return a.centerX.compareTo(b.centerX);
      });

      return OcrImageResult(
        lines: lines,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      return OcrImageResult(lines: [], processingTimeMs: stopwatch.elapsedMilliseconds);
    }
  }

  // -------------------------------------------------------------------------
  // Detection preprocessing
  // -------------------------------------------------------------------------

  /// Resize + normalize image for the detection model (uint8 [0,255]).
  Uint8List _preprocessDet(img.Image image) {
    final w = _config!.detInputWidth;
    final h = _config!.detInputHeight;
    final resized = img.copyResize(image, width: w, height: h);
    final buffer = Uint8List(w * h * 3);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = resized.getPixel(x, y);
        buffer[idx++] = p.r;
        buffer[idx++] = p.g;
        buffer[idx++] = p.b;
      }
    }
    return buffer;
  }

  // -------------------------------------------------------------------------
  // Detection output parsing
  // -------------------------------------------------------------------------

  /// Parse detection model output into bounding boxes.
  ///
  /// PP-OCR detection models output geometry maps; the exact shape depends on
  /// whether the model is DB, EAST, etc. This implementation handles the most
  /// common flat-box output. If your model outputs probability/geometry maps,
  /// replace [_parseDetectionOutputMaps] with contour-based polygon extraction.
  List<_DetBox> _parseDetectionBoxes(dynamic output, int origW, int origH) {
    final boxes = <_DetBox>[];

    try {
      // Try to read as nested list: [[x1, y1, x2, y2, score], ...]
      if (output is List) {
        for (final row in output) {
          if (row is List && row.length >= 5) {
            final x1 = (row[0] as num).toDouble();
            final y1 = (row[1] as num).toDouble();
            final x2 = (row[2] as num).toDouble();
            final y2 = (row[3] as num).toDouble();
            final score = (row[4] as num).toDouble();
            boxes.add(_DetBox(
              x1: _clamp(x1 / _config!.detInputWidth, 0, 1) * origW,
              y1: _clamp(y1 / _config!.detInputHeight, 0, 1) * origH,
              x2: _clamp(x2 / _config!.detInputWidth, 0, 1) * origW,
              y2: _clamp(y2 / _config!.detInputHeight, 0, 1) * origH,
              score: score,
            ));
          }
        }
      }

      // If no boxes parsed, try flat buffer (detection maps).
      if (boxes.isEmpty && output is Float32List || output is List) {
        boxes.addAll(_parseDetectionOutputMaps(output, origW, origH));
      }
    } catch (_) {
      // Ignore parse errors; fall back to empty.
    }

    return boxes;
  }

  /// Fallback: split the image into horizontal bands and treat each as a
  /// potential text line when the detection model output can't be parsed.
  List<_DetBox> _parseDetectionOutputMaps(dynamic output, int origW, int origH) {
    // Without the exact model output schema we cannot reliably extract boxes.
    // Return a single full-image box so the recognizer still gets a chance.
    return [
      _DetBox(
        x1: 0,
        y1: 0,
        x2: origW.toDouble(),
        y2: origH.toDouble(),
        score: 0.5,
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Filtering + NMS
  // -------------------------------------------------------------------------

  List<_DetBox> _filterAndNms(List<_DetBox> boxes) {
    boxes.removeWhere((b) => b.score < _config!.detScoreThreshold);
    boxes.sort((a, b) => b.score.compareTo(a.score));

    final kept = <_DetBox>[];
    for (final box in boxes) {
      bool overlaps = false;
      for (final keptBox in kept) {
        if (_iou(box, keptBox) > _config!.detNmsThreshold) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) kept.add(box);
    }
    return kept;
  }

  double _iou(_DetBox a, _DetBox b) {
    final interX1 = math.max(a.x1, b.x1);
    final interY1 = math.max(a.y1, b.y1);
    final interX2 = math.min(a.x2, b.x2);
    final interY2 = math.min(a.y2, b.y2);

    if (interX2 <= interX1 || interY2 <= interY1) return 0.0;

    final interArea = (interX2 - interX1) * (interY2 - interY1);
    final aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
    final bArea = (b.x2 - b.x1) * (b.y2 - b.y1);
    final union = aArea + bArea - interArea;
    if (union <= 0) return 0.0;
    return interArea / union;
  }

  // -------------------------------------------------------------------------
  // Recognition preprocessing
  // -------------------------------------------------------------------------

  /// Crop a card region from the image using a detection box.
  img.Image? _cropCardRegion(img.Image image, _DetBox box) {
    final x1 = box.x1.round().clamp(0, image.width - 1);
    final y1 = box.y1.round().clamp(0, image.height - 1);
    final x2 = box.x2.round().clamp(x1 + 1, image.width);
    final y2 = box.y2.round().clamp(y1 + 1, image.height);

    try {
      return img.copyCrop(image, x: x1, y: y1, width: x2 - x1, height: y2 - y1);
    } catch (_) {
      return null;
    }
  }

  /// Resize + grayscale + normalize for the recognition model.
  ///
  /// Quantized rec models expect uint8 [0,255]; float models expect [-1,1].
  /// We auto-detect via the input tensor type.
  dynamic _preprocessRec(img.Image image) {
    final w = _config!.recInputWidth;
    final h = _config!.recInputHeight;
    final resized = img.copyResize(image, width: w, height: h);
    final gray = img.grayscale(resized);

    final inputTensor = _recInterpreter!.getInputTensor(0);
    final isQuantized =
        inputTensor.type == TensorType.uint8 || inputTensor.type == TensorType.int8;

    final total = w * h;
    if (isQuantized) {
      final buffer = Uint8List(total);
      int idx = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          buffer[idx++] = gray.getPixel(x, y).r;
        }
      }
      return buffer;
    }

    final buffer = Float32List(total);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        buffer[idx++] = (gray.getPixel(x, y).r / 127.5) - 1.0;
      }
    }
    return buffer;
  }

  // -------------------------------------------------------------------------
  // CTC decoding
  // -------------------------------------------------------------------------

  /// Greedy CTC decode: argmax per timestep, collapse repeats, drop blank.
  String _ctcDecode(dynamic output) {
    List<List<dynamic>> sequences;
    if (output is List) {
      sequences = output.cast<List<dynamic>>();
    } else {
      return '';
    }

    final chars = <String>[];
    int? previous;
    for (final timestep in sequences) {
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
      if (best != _config!.blankIndex && best != previous) {
        if (best < _labels.length) {
          chars.add(_labels[best]);
        } else {
          chars.add('?');
        }
      }
      previous = best;
    }
    return chars.join();
  }

  /// Rough confidence estimate: mean of per-step max softmax probabilities.
  double _estimateConfidence(dynamic output) {
    if (output is! List) return 0.0;
    double sum = 0;
    int count = 0;
    for (final timestep in output) {
      final scores = timestep as List<dynamic>;
      num max = scores[0] as num;
      for (int i = 1; i < scores.length; i++) {
        final s = scores[i] as num;
        if (s > max) max = s;
      }
      sum += max.toDouble();
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
  }

  // -------------------------------------------------------------------------
  // Field parsing + merging (review-first)
  // -------------------------------------------------------------------------

  /// Parse OCR lines into card fields using regex heuristics.
  ///
  /// Returns a map with keys: name, title, company, email, phone, website,
  /// address, notes. Empty strings mean "not found".
  static Map<String, String> parseFields(List<OcrLine> lines) {
    final textLines = lines
        .where((l) => l.text.trim().isNotEmpty)
        .map((l) => l.text.trim())
        .toList();

    return _parseTextLines(textLines);
  }

  static Map<String, String> _parseTextLines(List<String> lines) {
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
      if (line.isEmpty) continue;
      if (email == null && emailRegExp.hasMatch(line)) {
        email = line;
        continue;
      }
      if (phone == null && phoneRegExp.hasMatch(line)) {
        phone = line;
        continue;
      }
      if (website == null && webRegExp.hasMatch(line)) {
        website = line;
        continue;
      }
      others.add(line);
    }

    String? name;
    String? title;
    String? company;
    String? address;

    if (others.isNotEmpty) {
      name = others.first;
      if (others.length > 1) title = others[1];
      if (others.length > 2) {
        company = others.sublist(2).join(' ');
      }
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
      'notes': '',
    };
  }

  /// Merge fields from front and back OCR results.
  ///
  /// Strategy:
  ///   * Start with front fields (usually cleaner/more complete).
  ///   * Fill missing fields from back.
  ///   * Deduplicate emails/phones.
  ///   * Prefer back address if front address is missing.
  static Map<String, String> mergeFields(
    Map<String, String> front,
    Map<String, String> back,
  ) {
    final result = Map<String, String>.from(front);

    // Fill missing scalars from back.
    for (final key in ['name', 'title', 'company', 'email', 'phone', 'website', 'address', 'notes']) {
      if ((result[key] ?? '').isEmpty && (back[key] ?? '').isNotEmpty) {
        result[key] = back[key]!;
      }
    }

    // Deduplicate / combine emails and phones if both sides have them.
    final frontEmail = front['email'] ?? '';
    final backEmail = back['email'] ?? '';
    if (frontEmail.isNotEmpty && backEmail.isNotEmpty && frontEmail != backEmail) {
      result['email'] = '$frontEmail, $backEmail';
    }

    final frontPhone = front['phone'] ?? '';
    final backPhone = back['phone'] ?? '';
    if (frontPhone.isNotEmpty && backPhone.isNotEmpty && frontPhone != backPhone) {
      result['phone'] = '$frontPhone, $backPhone';
    }

    return result;
  }

  /// Internal merge for OcrCardResult: parse both sides, then merge.
  Map<String, String> _mergeFields(List<OcrLine> frontLines, List<OcrLine> backLines) {
    final front = parseFields(frontLines);
    final back = parseFields(backLines);
    return mergeFields(front, back);
  }

  double _clamp(double v, double min, double max) =>
      math.min(math.max(v, min), max);
}

/// Internal detection box representation.
class _DetBox {
  _DetBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
  });
  final double x1, y1, x2, y2, score;
}
