import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/main.dart';
import 'package:helloscan/services/batch_export.dart';

void main() {
  group('BatchExport', () {
    test('builds a schema-compliant payload', () {
      final card = ScanCard(
        id: 'card-1',
        name: ' Ada ',
        company: ' Engines ',
        email: 'ada@example.com',
      );

      final payload = const BatchExport().buildPayload(<ScanCard>[
        card,
      ], exportedAt: DateTime.utc(2026, 1, 2, 3, 4, 5));

      expect(payload['schema'], 'helloscan.contact-batch.v1');
      expect(payload['exported_at'], '2026-01-02T03:04:05.000Z');
      expect(payload['total'], 1);

      final contacts = payload['contacts'] as List<dynamic>;
      expect(contacts, hasLength(1));
      final contact = contacts.single as Map<String, dynamic>;
      expect(contact['person']['name'], 'Ada');
      expect(contact['organization']['name'], 'Engines');
      expect(contact['contact']['emails'], <String>['ada@example.com']);
      expect(contact['source']['review_status'], 'pending');
    });

    test('exports every detected email and phone', () {
      final card = ScanCard(
        id: 'card-multi',
        email: 'first@example.com',
        phone: '+256700000001',
        emails: ['first@example.com', 'second@example.com'],
        phones: ['+256700000001', '+256700000002'],
      );

      final payload = const BatchExport().buildPayload([card]);
      final contact = (payload['contacts'] as List).single as Map;
      final details = contact['contact'] as Map;

      expect(details['emails'], ['first@example.com', 'second@example.com']);
      expect(details['phones'], ['+256700000001', '+256700000002']);
    });

    test('encodes pretty, valid JSON', () {
      final json = const BatchExport().encode(
        <ScanCard>[],
        exportedAt: DateTime.utc(2026, 1, 1),
      );

      expect(json, contains('"schema"'));
      expect(json, contains('"helloscan.contact-batch.v1"'));
      expect(json, contains('"total": 0'));
    });
  });
}
