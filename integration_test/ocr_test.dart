import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/services/card_parser.dart';
import 'package:helloscan/services/mlkit_ocr_service.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ML Kit reads a degraded card and the parser structures it', (
    tester,
  ) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/helloscan_ocr_probe.jpg');
    await file.writeAsBytes(_buildDegradedCard(), flush: true);

    final ocr = MlKitOcrService();
    try {
      final text = await ocr.recognize(file);
      final parsed = const CardParser().parse(text);

      // The raw recognizer should recover the name even from the degraded
      // image that has been shrunk, blurred and washed out.
      expect(text.toLowerCase(), contains('ravi'));

      expect(parsed.name.toLowerCase(), contains('ravi'));
      expect(parsed.email, isNotEmpty, reason: 'Raw OCR text:\n$text');
      expect(
        parsed.email.toLowerCase(),
        contains('acrne'),
        reason: 'Raw OCR text:\n$text',
      );
      expect(parsed.phone.replaceAll(RegExp(r'[^0-9]'), ''), contains('98123'));
      expect(parsed.company.toLowerCase(), contains('acrne'));
      expect(parsed.address.toLowerCase(), contains('bengaluru'));
    } finally {
      await ocr.dispose();
      if (await file.exists()) await file.delete();
    }
  });
}

List<int> _buildDegradedCard() {
  var card = img.Image(width: 1200, height: 800, numChannels: 3);
  img.fill(card, color: img.ColorRgb8(252, 252, 250));
  final ink = img.ColorRgb8(20, 20, 20);

  img.drawString(
    card,
    'RAVI KUMAR',
    font: img.arial48,
    x: 70,
    y: 60,
    color: ink,
  );
  img.drawString(
    card,
    'Sr. Manager',
    font: img.arial24,
    x: 70,
    y: 150,
    color: ink,
  );
  img.drawString(
    card,
    'Acrne Technologies Pvt. Ltd',
    font: img.arial24,
    x: 70,
    y: 205,
    color: ink,
  );
  img.drawString(
    card,
    'ravi.kumar@acrne-tech.com',
    font: img.arial24,
    x: 70,
    y: 290,
    color: ink,
  );
  img.drawString(
    card,
    '+91 98123 45678',
    font: img.arial24,
    x: 70,
    y: 345,
    color: ink,
  );
  img.drawString(
    card,
    'www.acrne-tech.com',
    font: img.arial24,
    x: 70,
    y: 400,
    color: ink,
  );
  img.drawString(
    card,
    'Plot 12, Sector 5, HSR Layout',
    font: img.arial24,
    x: 70,
    y: 490,
    color: ink,
  );
  img.drawString(
    card,
    'Bengaluru 560102',
    font: img.arial24,
    x: 70,
    y: 545,
    color: ink,
  );

  // Simulate a weak capture: shrink, blur and wash out contrast. The enhancer
  // should upscale and re-stretch this before ML Kit sees it.
  var weak = img.copyResize(
    card,
    width: 720,
    height: 480,
    interpolation: img.Interpolation.average,
  );
  weak = img.gaussianBlur(weak, radius: 1);
  weak = img.adjustColor(weak, contrast: 0.9, brightness: 0.97);

  return img.encodeJpg(weak, quality: 82);
}
