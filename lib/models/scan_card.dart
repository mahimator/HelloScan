import 'package:image_picker/image_picker.dart';

/// A single staged visiting card. Image files remain local and are not exported.
class ScanCard {
  ScanCard({
    required this.id,
    this.front,
    this.back,
    this.name = '',
    this.title = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.address = '',
    this.notes = '',
    List<String>? emails,
    List<String>? phones,
    this.isTwoSided = false,
    this.fastScan = false,
  }) : emails = emails ?? <String>[],
       phones = phones ?? <String>[];

  final String id;
  XFile? front;
  XFile? back;

  bool isTwoSided;
  bool fastScan;
  String name;
  String title;
  String company;
  String email;
  String phone;
  String website;
  String address;
  String notes;

  /// All recognised contact points, not just the primary editable value.
  /// The scalar [email] and [phone] remain for compatibility with the editor.
  final List<String> emails;
  final List<String> phones;

  bool reviewed = false;
  bool extracting = false;
  bool? ocrFailed;
  int detectedFields = 0;
  int revision = 0;
  final Set<String> editedFields = <String>{};

  String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _values(List<String> values, String primary) {
    final result = <String>[];
    for (final value in <String>[primary, ...values]) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !result.contains(trimmed)) result.add(trimmed);
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'person': {'name': _nonEmpty(name), 'designation': _nonEmpty(title)},
    'organization': {'name': _nonEmpty(company), 'website': _nonEmpty(website)},
    'contact': {
      'emails': _values(emails, email),
      'phones': _values(phones, phone),
    },
    'location': {'full_address': _nonEmpty(address)},
    'notes': _nonEmpty(notes),
    'source': {
      'sides': [if (front != null) 'front', if (back != null) 'back'],
      'review_status': reviewed ? 'reviewed' : 'pending',
    },
  };
}
