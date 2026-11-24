/// Configuration for the on-device OCR pipeline.
///
/// Optimized for low-to-mid range Android phones (Samsung A/M series).
/// All models should be INT8 quantized and small enough to keep the APK
/// under ~10 MB for the ML assets.
class OcrConfig {
  const OcrConfig({
    this.detModelPath = 'assets/models/det.tflite',
    this.recModelPath = 'assets/models/rec.tflite',
    this.labelsPath = 'assets/models/labels.txt',

    /// Detection input size. 320x320 is a good trade-off for A/M series phones.
    /// Larger = more accurate but slower and more RAM.
    this.detInputWidth = 320,
    this.detInputHeight = 320,

    /// Recognition input size. PP-OCR rec models typically use 32x128 (HxW).
    this.recInputWidth = 128,
    this.recInputHeight = 32,

    /// Minimum confidence for a detection box to be kept.
    this.detScoreThreshold = 0.30,

    /// IoU threshold for non-maximum suppression on detection boxes.
    this.detNmsThreshold = 0.30,

    /// Maximum number of text lines to recognize per image.
    /// Keeps RAM usage bounded on low-end devices.
    this.maxDetections = 40,

    /// Use NNAPI delegate (NPU/DSP) when available, fallback to CPU.
    this.useNnapi = true,

    /// Index of the CTC blank label in the recognition labels file.
    this.blankIndex = 0,
  });

  final String detModelPath;
  final String recModelPath;
  final String? labelsPath;
  final int detInputWidth;
  final int detInputHeight;
  final int recInputWidth;
  final int recInputHeight;
  final double detScoreThreshold;
  final double detNmsThreshold;
  final int maxDetections;
  final bool useNnapi;
  final int blankIndex;
}
