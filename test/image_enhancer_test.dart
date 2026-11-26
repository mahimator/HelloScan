import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/services/image_enhancer.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ImageEnhancer', () {
    test('upscales small images and returns decodable output', () {
      final source = img.Image(width: 40, height: 30, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(120, 120, 120));
      final input = Uint8List.fromList(img.encodePng(source));

      final output = const ImageEnhancer().enhance(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      // 40px * maxUpscale(3) = 120px.
      expect(decoded!.width, 120);
    });

    test('leaves already-large images at their size', () {
      final source = img.Image(width: 2000, height: 1000, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(10, 10, 10));
      final input = Uint8List.fromList(img.encodePng(source));

      final output = const ImageEnhancer().enhance(input);
      final decoded = img.decodeImage(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 2000);
    });

    test('returns original bytes when input cannot be decoded', () {
      final input = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final output = const ImageEnhancer().enhance(input);
      expect(output, input);
    });
  });
}
