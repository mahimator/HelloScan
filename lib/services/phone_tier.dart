/// Phone performance tier configuration.
///
/// Used to pick the right OCR model resolution and detection budget for the
/// device class. Tiers are chosen by the user during onboarding with reference
/// specs shown for each.
enum PhoneTier { low, mid, high }

class PhoneTierConfig {
  const PhoneTierConfig({
    required this.tier,
    required this.label,
    required this.referenceSpecs,
    required this.detInputWidth,
    required this.detInputHeight,
    required this.recInputWidth,
    required this.recInputHeight,
    required this.maxDetections,
    required this.detModelUrl,
    required this.recModelUrl,
  });

  final PhoneTier tier;
  /// Human-readable name shown in the onboarding UI.
  final String label;
  /// Reference phone specs to help the user pick the right tier.
  final String referenceSpecs;
  final int detInputWidth;
  final int detInputHeight;
  final int recInputWidth;
  final int recInputHeight;
  /// Max text-line detections per image (caps RAM usage).
  final int maxDetections;
  /// Hugging Face download URL for the detection model (INT8 TFLite).
  final String detModelUrl;
  /// Hugging Face download URL for the recognition model (INT8 TFLite).
  final String recModelUrl;

  /// Returns the [OcrConfig] matching this tier.
  OcrConfig toOcrConfig() {
    return OcrConfig(
      detInputWidth: detInputWidth,
      detInputHeight: detInputHeight,
      recInputWidth: recInputWidth,
      recInputHeight: recInputHeight,
      maxDetections: maxDetections,
      useNnapi: true,
      blankIndex: 0,
    );
  }
}

/// Reference configs for each tier. Replace the Hugging Face URLs below with
/// the actual TFLite model file URLs you find on Hugging Face.
class PhoneTierConfigs {
  static const List<PhoneTierConfig> all = [
    PhoneTierConfig(
      tier: PhoneTier.low,
      label: 'Low-end',
      referenceSpecs:
          '2–3 GB RAM • entry-level CPU\n'
          'Example: Samsung Galaxy A04, A13, M13, M14',
      detInputWidth: 256,
      detInputHeight: 256,
      recInputWidth: 96,
      recInputHeight: 32,
      maxDetections: 20,
      detModelUrl:
          'https://huggingface.co/your-org/helloscan-models/resolve/main/det_low.tflite',
      recModelUrl:
          'https://huggingface.co/your-org/helloscan-models/resolve/main/rec_low.tflite',
    ),
    PhoneTierConfig(
      tier: PhoneTier.mid,
      label: 'Mid-range',
      referenceSpecs:
          '4–6 GB RAM • mid-tier CPU\n'
          'Example: Samsung Galaxy A34, A53, A54, M34, M54',
      detInputWidth: 320,
      detInputHeight: 320,
      recInputWidth: 128,
      recInputHeight: 32,
      maxDetections: 40,
      detModelUrl:
          'https://huggingface.co/your-org/helloscan-models/resolve/main/det_mid.tflite',
      recModelUrl:
          'https://huggingface.co/your-org/helloscan-models/resolve/main/rec_mid.tflite',
    ),
    PhoneTierConfig(
      tier: PhoneTier.high,
      label: 'High-end',
      referenceSpecs:
          '8 GB+ RAM • flagship CPU\n'
          'Example: Samsung Galaxy S23, S24, A73, A74',
      detInputWidth: 640,
      detInputHeight: 640,
      recInputWidth: 128,
      recInputHeight: 32,
      maxDetections: 80,
      detModelUrl:
          'https://huggingface.co/your-org/helloscan-models/resolve/main/det_high.tflite',
      recModelUrl:
          'https://huggingface.co/your-org/helloscan-models/resolve/main/rec_high.tflite',
    ),
  ];

  static PhoneTierConfig forTier(PhoneTier tier) =>
      all.firstWhere((c) => c.tier == tier);
}
