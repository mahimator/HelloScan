import 'package:flutter_test/flutter_test.dart';
import 'package:helloscan/main.dart';

void main() {
  group('ScanCard JSON mapping', () {
    test('empty card exports null scalar fields and empty arrays', () {
      final card = ScanCard(id: 'card-1');
      final json = card.toJson();

      expect(json['person']['name'], isNull);
      expect(json['organization']['website'], isNull);
      expect(json['contact']['emails'], isEmpty);
      expect(json['contact']['phones'], isEmpty);
      expect(json['location']['full_address'], isNull);
      expect(json['source']['sides'], isEmpty);
      expect(json['source']['review_status'], 'pending');
    });

    test('trims values and reflects review status', () {
      final card = ScanCard(
        id: 'card-2',
        name: '  Ada Lovelace  ',
        title: '  Analyst ',
        company: '  Analytical Engines ',
        email: ' ada@example.com ',
        phone: ' +44 1234 ',
        website: ' https://example.com ',
        address: ' London ',
        notes: ' First note ',
      )..reviewed = true;
      final json = card.toJson();

      expect(json['person']['name'], 'Ada Lovelace');
      expect(json['person']['designation'], 'Analyst');
      expect(json['organization']['name'], 'Analytical Engines');
      expect(json['contact']['emails'], ['ada@example.com']);
      expect(json['contact']['phones'], ['+44 1234']);
      expect(json['location']['full_address'], 'London');
      expect(json['notes'], 'First note');
      expect(json['source']['review_status'], 'reviewed');
    });
  });
}
