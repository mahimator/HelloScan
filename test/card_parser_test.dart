import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/services/card_parser.dart';

void main() {
  const parser = CardParser();

  group('CardParser accuracy', () {
    test('recovers every field from a noisy, low-quality card', () {
      const messy = '''
  RAVI  KUMAR
 Sr.  Manager
Acrne Technologies Pvt.Ltd
 ravi.kumar @ acrne-tech.con
M: +91 98l23 45678
www.acrne-tech.com
Plot 12, Sector 5 , HSR Layout
Bengaluru - 560102''';

      final result = parser.parse(messy);

      expect(result.name, 'Ravi Kumar');
      expect(result.designation.toLowerCase(), contains('manager'));
      expect(result.company.toLowerCase(), contains('acrne technologies'));
      expect(result.email, 'ravi.kumar@acrne-tech.com');
      expect(result.phone, '+919812345678');
      expect(result.website.toLowerCase(), contains('acrne-tech.com'));
      expect(result.address.toLowerCase(), contains('bengaluru'));
      expect(result.address, contains('560102'));
      expect(result.detectedCount, 7);
    });

    test('handles OCR letter/digit confusions in phone numbers', () {
      const messy = '''
AMIT  SHAH
MaNaGer - Sales
ZenTech  S0lutions  Pvt  Ltd
amit.shah@zentech.co.in
Mobile : 98O12 34S67
C-14, 2nd Floor, MG Road
Pune 411001''';

      final result = parser.parse(messy);

      expect(result.name, 'Amit Shah');
      expect(result.designation.toLowerCase(), contains('manager'));
      expect(result.company.toLowerCase(), contains('zentech'));
      expect(result.email, 'amit.shah@zentech.co.in');
      expect(result.phone, '9801234567');
      expect(result.address.toLowerCase(), contains('mg road'));
      expect(result.address, contains('411001'));
    });

    test('separates email domains from website fields', () {
      const card = '''
Priya Nair
Brightlabs Technologies
priya@brightlabs.in
www.brightlabs.in
+91 98765 43210''';

      final result = parser.parse(card);

      expect(result.name, 'Priya Nair');
      expect(result.email, 'priya@brightlabs.in');
      expect(result.website, 'www.brightlabs.in');
      expect(result.phone, '+919876543210');
      expect(result.company.toLowerCase(), contains('brightlabs'));
    });

    test('repairs spaced and obfuscated email addresses', () {
      final result = parser.parse('''
John Doe
john . doe @ example . com''');

      expect(result.email, 'john.doe@example.com');
    });

    test('recognizes initials and surname-first name formats', () {
      final examples = <String, String>{
        'Madhav Prashant Trivedi': 'Madhav Prashant Trivedi',
        'Madhav Trivedi': 'Madhav Trivedi',
        'Trivedi Madhav': 'Trivedi Madhav',
        'Trivedi Madhav Prashant': 'Trivedi Madhav Prashant',
        'M.P. Trivedi': 'M.P. Trivedi',
        'M P Trivedi': 'M P Trivedi',
        'MADHAV P TRIVEDI': 'Madhav P Trivedi',
      };

      for (final entry in examples.entries) {
        final parsed = parser.parse('${entry.key}\nFounder & Managing Director\nTrivedi Industries\n+256 700 123456');
        expect(parsed.name, entry.value, reason: 'Input: ${entry.key}');
      }
    });

    test('recognizes designation words alongside company vocabulary', () {
      final result = parser.parse('''
Madhav Trivedi
Water Solutions Engineer
Samanga Utilities
madhav@samangasolutions.com
+256 700 123456''');

      expect(result.name, 'Madhav Trivedi');
      expect(result.designation, 'Water Solutions Engineer');
      expect(result.company, 'Samanga Utilities');
    });

    test('retains every email and phone candidate', () {
      final result = parser.parse('''
Madhav Trivedi
madhav@example.com
m.trivedi@company.org
+256 700 123456
+256 772 654321
Company Solutions''');

      expect(result.emails, <String>['madhav@example.com', 'm.trivedi@company.org']);
      expect(result.phones, <String>['+256700123456', '+256772654321']);
      expect(result.email, result.emails.first);
      expect(result.phone, result.phones.first);
    });

    test('does not extract email domain as company when no company line exists', () {
      final result = parser.parse('''
Asha Rao
asha@nimbusworks.io
+1 202 555 0114''');

      // Company must come from an explicit company line on the card, never
      // synthesized from an email domain.
      expect(result.company, isEmpty);
      expect(result.name, 'Asha Rao');
      expect(result.email, 'asha@nimbusworks.io');
    });

    test('merges front and back scans', () {
      final front = parser.parse('''
John Smith
Acme LLC
john@acme.io''');
      final back = parser.parse('''
+1 415 555 0132
500 Market Street
San Francisco, CA 94105''');

      final merged = front.merge(back);

      expect(merged.name, 'John Smith');
      expect(merged.company, 'Acme LLC');
      expect(merged.email, 'john@acme.io');
      expect(merged.phone, '+14155550132');
      expect(merged.address, contains('Market Street'));
      expect(merged.address, contains('94105'));
    });

    test('parseMany merges multiple sides', () {
      final merged = parser.parseMany(<String>[
        'Sara Lee\nDesign Lead\nbeacon.studio',
        'sara@beacon.studio\n+44 20 7946 0018',
      ]);

      expect(merged.name, 'Sara Lee');
      expect(merged.designation.toLowerCase(), contains('lead'));
      expect(merged.email, 'sara@beacon.studio');
      expect(merged.phone, '+442079460018');
    });

    test('repairs a misread email domain using the website', () {
      const ocr = '''
RAVI KUMAR
Sr. Manager
Acrne Technologies Pt. Ltd
ravi. kumar@acrme-tech.com
+91 98123 45678
www.acrne-tech.com
Plat 12, Sector 5, HSR Layout
Bengaluru 560102''';

      final result = parser.parse(ocr);

      expect(result.name, 'Ravi Kumar');
      expect(result.email, 'ravi.kumar@acrne-tech.com');
      expect(result.phone, '+919812345678');
      expect(result.company.toLowerCase(), contains('acrne'));
      expect(result.address.toLowerCase(), contains('bengaluru'));
    });

    test('never throws on empty or garbage input', () {
      expect(parser.parse('').isEmpty, isTrue);
      expect(parser.parse('   \n\n  ').isEmpty, isTrue);
      expect(parser.parse('!!! *** ???').isEmpty, isTrue);
      expect(parser.parse('12345678901234567890').name, isEmpty);
    });

    test('does not mistake phone numbers or dates for addresses', () {
      final result = parser.parse('''
Neha Gupta
+91 90000 12345
2024-05-01''');

      expect(result.phone, contains('9000012345'));
      expect(result.address, isEmpty);
    });
  });
}
