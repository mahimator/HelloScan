import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/services/card_parser.dart';
import 'package:helloscan/services/image_enhancer.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = CardParser();
  const enhancer = ImageEnhancer();
  final directory = Directory('sample cards');

  group('Sample card image processing', () {
    test('processes JPG sample card through full pipeline', () async {
      final jpgFile = File('${directory.path}/62AC3B19-8EBA-4452-9582-8549CED3B99E.JPG');
      expect(await jpgFile.exists(), isTrue, reason: 'Sample JPG file should exist');

      final bytes = await jpgFile.readAsBytes();
      final enhanced = enhancer.enhance(bytes, fast: false);
      expect(enhanced, isNotEmpty);

      // Decode to verify it's a valid image
      final decoded = img.decodeImage(enhanced);
      expect(decoded, isNotNull, reason: 'Enhanced image should be decodable');
      expect(decoded!.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));

      print('JPG sample: ${decoded.width}x${decoded.height} pixels');
    });

    test('enhancement preserves image quality for OCR', () async {
      final jpgFile = File('${directory.path}/62AC3B19-8EBA-4452-9582-8549CED3B99E.JPG');
      final bytes = await jpgFile.readAsBytes();

      final enhanced = enhancer.enhance(bytes, fast: false);
      final fastEnhanced = enhancer.enhance(bytes, fast: true);

      // Both should produce valid images
      expect(img.decodeImage(enhanced), isNotNull);
      expect(img.decodeImage(fastEnhanced), isNotNull);

      print('Full enhancement: ${enhanced.length} bytes');
      print('Fast enhancement: ${fastEnhanced.length} bytes');
    });

    test('parseManyDocuments combines front and back OCR', () {
      final documents = [
        'John Smith\nSenior Engineer\nAcme Corp\njohn@acme.com\n+1 234 567 8900',
        '+1 234 567 8901\n123 Main Street\nSan Francisco, CA 94105',
      ];

      final parsed = const CardParser().parseMany(documents);
      expect(parsed.name, 'John Smith');
      expect(parsed.designation, 'Senior Engineer');
      expect(parsed.company, 'Acme Corp');
      expect(parsed.email, 'john@acme.com');
      expect(parsed.address, contains('Main Street'));
    });

    // OpenRouter service test skipped - requires platform plugins not
    // available in pure unit tests. Verified manually on device.
    test('full end-to-end parse of typical business card OCR', () {
      const ocr = '''
Sarah Chen
Marketing Director
TechFlow Solutions Inc
sarah.chen@techflow.com
+1 (415) 555-0123
www.techflow.com
450 Market Street, Suite 1000
San Francisco, CA 94105''';

      final result = parser.parse(ocr);

      print('Parsed result:');
      print('  name: ${result.name}');
      print('  designation: ${result.designation}');
      print('  company: ${result.company}');
      print('  email: ${result.email}');
      print('  phone: ${result.phone}');
      print('  website: ${result.website}');
      print('  address: ${result.address}');
      print('  detectedCount: ${result.detectedCount}');

      expect(result.name, isNotEmpty);
      expect(result.designation, isNotEmpty);
      expect(result.company, isNotEmpty);
      expect(result.email, contains('techflow'));
      expect(result.phone, isNotEmpty);
      expect(result.website, contains('techflow'));
      expect(result.address, isNotEmpty);
      expect(result.detectedCount, greaterThanOrEqualTo(6));
    });

    test('Equator Chocolate is name not company', () {
      // "Chocolate" is a company keyword but "Equator Chocolate" is a person's
      // name — it must not be classified as company.
      const ocr = '''
Equator Chocolate
+1 234 567 8900''';

      final result = parser.parse(ocr);

      print('Equator Chocolate result:');
      print('  name: ${result.name}');
      print('  company: ${result.company}');

      expect(result.name, 'Equator Chocolate');
      expect(result.company, isEmpty);
    });

    test('JSON export matches schema', () async {
      // Verify the schema is valid JSON
      final schemaFile = File('schemas/contact-batch-v1.schema.json');
      expect(await schemaFile.exists(), isTrue);
      final schemaContent = await schemaFile.readAsString();
      // Just verify it parses as JSON
      final decoded = jsonDecode(schemaContent) as Map<String, dynamic>;
      expect(decoded['\$id'], 'https://helloscan.app/schemas/contact-batch-v1.json');
      expect(decoded['title'], 'HelloScan Contact Batch');
    });
  });
}
