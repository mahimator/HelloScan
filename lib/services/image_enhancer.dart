import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Bounded, device-friendly image preparation for business-card OCR.
///
/// Processing cost is bounded by [maxDimension], so a 12MP camera image does
/// not create an equally large collection of temporary pixel buffers.
/// Expensive decoding and enhancement is invoked through [enhanceInIsolate].
class ImageEnhancer {
  const ImageEnhancer({
    this.maxDimension = 2200,
    this.targetWidth = 1600,
    this.maxUpscale = 3.0,
  });

  /// Maximum long edge sent to ML Kit. Keeps memory use predictable.
  final int maxDimension;
  final int targetWidth;
  final double maxUpscale;

  Uint8List enhance(Uint8List input, {bool fast = false}) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    // Respect EXIF rotation before deciding which dimension is the long edge.
    var image = img.bakeOrientation(decoded);
    final longest = math.max(image.width, image.height);

    // Always downscale oversized camera images before creating more buffers.
    // This is the most important guard for low-memory Android devices.
    if (longest > maxDimension) {
      final scale = maxDimension / longest;
      image = img.copyResize(
        image,
        width: math.max(1, (image.width * scale).round()).toInt(),
        height: math.max(1, (image.height * scale).round()).toInt(),
        interpolation: img.Interpolation.linear,
      );
    } else if (!fast && image.width < targetWidth) {
      // Only upscale genuinely small images, and never beyond the memory cap.
      final requested = math.min(targetWidth / image.width, maxUpscale);
      final capScale = maxDimension / math.max(image.width, image.height);
      final scale = math.min(requested, capScale);
      if (scale > 1.05) {
        image = img.copyResize(
          image,
          width: math.max(1, (image.width * scale).round()).toInt(),
          height: math.max(1, (image.height * scale).round()).toInt(),
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // Grayscale is deliberately retained as the low-cost baseline. Do not
    // apply aggressive thresholding: cards with white-on-dark print can suffer.
    image = img.grayscale(image);
    if (!fast) {
      image = img.adjustColor(image, contrast: 1.18, brightness: 1.02);
    }

    return img.encodeJpg(image, quality: fast ? 84 : 90);
  }
}

/// Runs CPU-heavy image decoding/resizing away from Flutter's UI isolate.
Uint8List enhanceInIsolate(List<Object> payload) {
  final input = payload[0] as Uint8List;
  final fast = payload[1] as bool;
  return const ImageEnhancer().enhance(input, fast: fast);
}
