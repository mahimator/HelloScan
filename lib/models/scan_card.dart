import 'package:image_picker/image_picker.dart';

/// A single staged visiting card in the temporary batch.
///
/// Cards are intentionally ephemeral: they live only in memory until the batch
/// is reviewed and exported as CRM-ready JSON.
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
    this.isTwoSided = false,
    this.fastScan = false,
  });

  final String id;
  XFile? front;
  XFile? back;

  /// True when the card has a back side to scan. Set from the one/two-sided
  /// prompt so the UI knows to offer "Scan back" after the front.
  bool isTwoSided;

  /// When true, skips image enhancement for faster (lower-quality) OCR.
  bool fastScan;
  String name;
  String title;
  String company;
  String email;
  String phone;
  String website;
  String address;
  String notes;

  /// User has explicitly confirmed the card contents.
  bool reviewed = false;

  /// True while OCR is running for this card.
  bool extracting = false;

  /// Null when not attempted, true when OCR produced nothing usable.
  bool? ocrFailed;

  /// Number of contact fields that were auto-filled from the last OCR pass.
  int detectedFields = 0;

  /// Bumped whenever OCR rewrites fields so the editor can rebuild from the
  /// model. Typing does not bump this, so the cursor stays put while editing.
  int revision = 0;

  /// Field names the user typed into; OCR must never overwrite these.
  final Set<String> editedFields = <String>{};

  String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _nonEmptyList(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? <String>[] : <String>[trimmed];
  }

  Map<String, dynamic> toJson() => {
    'person': {'name': _nonEmpty(name), 'designation': _nonEmpty(title)},
    'organization': {'name': _nonEmpty(company), 'website': _nonEmpty(website)},
    'contact': {'emails': _nonEmptyList(email), 'phones': _nonEmptyList(phone)},
    'location': {'full_address': _nonEmpty(address)},
    'notes': _nonEmpty(notes),
    'source': {
      'sides': [if (front != null) 'front', if (back != null) 'back'],
      'review_status': reviewed ? 'reviewed' : 'pending',
    },
  };
}
