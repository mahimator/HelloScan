/// Geometry-aware OCR output. Coordinates are in the processed image's
/// pixel coordinate space. Kept separate from parser output so callers can
/// audit exactly which text ML Kit saw and where it appeared.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get centerX => (left + right) ~/ 2;
  int get centerY => (top + bottom) ~/ 2;
}

class OcrBlock {
  const OcrBlock({required this.text, required this.lines});

  final String text;
  final List<OcrLine> lines;
}

class OcrDocument {
  const OcrDocument({
    required this.text,
    this.blocks = const <OcrBlock>[],
  });

  final String text;
  final List<OcrBlock> blocks;

  List<OcrLine> get lines =>
      blocks.expand((block) => block.lines).toList(growable: false);
}
