import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pre-processes card photos before OCR.
///
/// Low-end photos of visiting cards are often small, low-contrast, slightly
/// blurry, or shot under uneven lighting. Upscaling small images, removing
/// color noise, stretching contrast and (optionally) binarizing gives the
/// recognizer a better chance on poor-quality cards while remaining cheap
/// enough to run on-device.
///
/// Enhancement is CPU-intensive and runs on the Dart main isolate. Use
/// [enhanceInIsolate] to offload it to a background isolate and prevent
/// "app not responding" (ANR) on large camera images.
class ImageEnhancer {
  const ImageEnhancer({
    this.targetWidth = 1600,
    this.maxUpscale = 3.0,
  });

  /// Preferred width in pixels. Smaller images are scaled up toward this.
  final int targetWidth;

  /// Never scale up by more than this factor (avoids turning mush into noise).
  final double maxUpscale;

  /// Returns enhanced image bytes. Falls back to [input] if it cannot be
  /// decoded, so a bad image never crashes the scan flow.
  ///
  /// When [fast] is true, skips upscaling and contrast stretching so the
  /// image is returned as-is (grayscale only). Use this for quick scans on
  /// low-end devices where the full enhancement pipeline feels sluggish.
  Uint8List enhance(Uint8List input, {bool fast = false}) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    // Apply EXIF orientation so sideways phone photos are upright before OCR.
    var image = img.bakeOrientation(decoded);

    if (!fast) {
      // Upscale small images toward [targetWidth], capped by [maxUpscale].
      if (image.width < targetWidth && image.width > 0) {
        final scale = math.min(targetWidth / image.width, maxUpscale);
        if (scale > 1.0) {
          final width = (image.width * scale).round();
          final height = (image.height * scale).round();
          image = img.copyResize(
            image,
            width: width,
            height: height,
            interpolation: img.Interpolation.cubic,
          );
        }
      }
    }

    // Grayscale removes colored backgrounds and lighting casts (cheap, always on).
    image = img.grayscale(image);

    if (!fast) {
      // Stretch contrast and lift shadows so faint print becomes readable.
      image = img.adjustColor(image, contrast: 1.3, brightness: 1.05);
    }

    return img.encodeJpg(image, quality: 92);
  }
}

/// Runs [ImageEnhancer.enhance] on a background isolate so CPU-intensive
/// image processing never blocks the UI thread and cause an ANR.
///
/// [payload] must be a `List<Object>` with two elements: [Uint8List] input
/// bytes at index 0 and a [bool] fast flag at index 1.
Uint8List enhanceInIsolate(List<Object> payload) {
  final input = payload[0] as Uint8List;
  final fast = payload[1] as bool;
  return const ImageEnhancer().enhance(input, fast: fast);
}
