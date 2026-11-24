/// A single detected text line with its bounding box and confidence.
class OcrLine {
  OcrLine({
    required this.text,
    required this.confidence,
    required this.box,
  });

  final String text;
  /// Confidence score from the recognition model (0.0–1.0).
  final double confidence;
  /// Normalized bounding box [x1, y1, x2, y2] in 0..1 range.
  final List<double> box;

  /// Vertical center of the box, used to sort lines top-to-bottom.
  double get centerY => (box[1] + box[3]) / 2.0;

  /// Horizontal center of the box.
  double get centerX => (box[0] + box[2]) / 2.0;

  @override
  String toString() => 'OcrLine(text: $text, conf: ${confidence.toStringAsFixed(2)})';
}

/// Result of running OCR on a single card image (front or back).
class OcrImageResult {
  OcrImageResult({
    required this.lines,
    required this.processingTimeMs,
  });

  final List<OcrLine> lines;
  final int processingTimeMs;

  /// All recognized text joined by newlines, sorted top-to-bottom.
  String get allText => lines
      .where((l) => l.text.trim().isNotEmpty)
      .map((l) => l.text.trim())
      .join('\n');
}

/// Combined result for a business card that may have front and back images.
class OcrCardResult {
  OcrCardResult({
    required this.front,
    this.back,
    required this.mergedFields,
  });

  final OcrImageResult front;
  final OcrImageResult? back;
  /// Field map produced by merging front + back OCR lines (review-first).
  final Map<String, String> mergedFields;

  /// True if both sides are missing or empty.
  bool get isEmpty =>
      front.lines.isEmpty && (back?.lines.isEmpty ?? true);

  /// Total processing time across all images.
  int get totalProcessingTimeMs =>
      front.processingTimeMs + (back?.processingTimeMs ?? 0);
}
