/// Structured contact details extracted from raw OCR text.
///
/// All scalar fields use empty strings instead of null so they can be merged
/// and mapped onto a [ScanCard] without null checks. [emails] and [phones]
/// preserve every candidate that was found.
class ParsedCard {
  const ParsedCard({
    this.name = '',
    this.designation = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.address = '',
    this.emails = const <String>[],
    this.phones = const <String>[],
    this.rawText = '',
  });

  final String name;
  final String designation;
  final String company;
  final String email;
  final String phone;
  final String website;
  final String address;
  final List<String> emails;
  final List<String> phones;
  final String rawText;

  static const ParsedCard empty = ParsedCard();

  bool get isEmpty => detectedCount == 0;

  /// Number of primary contact fields that were successfully extracted.
  int get detectedCount {
    var count = 0;
    for (final value in <String>[
      name,
      designation,
      company,
      email,
      phone,
      website,
      address,
    ]) {
      if (value.trim().isNotEmpty) count++;
    }
    return count;
  }

  /// Merge two parses (for example the front and back of a card).
  ///
  /// Scalar fields prefer the first non-empty value; lists are unioned.
  ParsedCard merge(ParsedCard other) {
    final mergedEmails = _unionEmails(emails, other.emails);
    final mergedPhones = _unionPhones(phones, other.phones);
    return ParsedCard(
      name: _prefer(name, other.name),
      designation: _prefer(designation, other.designation),
      company: _prefer(company, other.company),
      email: _prefer(
        _prefer(email, other.email),
        mergedEmails.isNotEmpty ? mergedEmails.first : '',
      ),
      phone: _prefer(
        _prefer(phone, other.phone),
        mergedPhones.isNotEmpty ? mergedPhones.first : '',
      ),
      website: _prefer(website, other.website),
      address: _preferLonger(address, other.address),
      emails: mergedEmails,
      phones: mergedPhones,
      rawText: [
        rawText,
        other.rawText,
      ].where((value) => value.trim().isNotEmpty).join('\n'),
    );
  }

  static String _prefer(String value, String fallback) =>
      value.trim().isNotEmpty ? value : fallback;

  static String _preferLonger(String a, String b) {
    if (a.trim().isEmpty) return b;
    if (b.trim().isEmpty) return a;
    return b.trim().length > a.trim().length ? b : a;
  }

  static List<String> _unionEmails(List<String> a, List<String> b) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in <String>[...a, ...b]) {
      final trimmed = value.trim();
      final key = trimmed.toLowerCase();
      if (trimmed.isNotEmpty && seen.add(key)) result.add(trimmed);
    }
    return result;
  }

  static List<String> _unionPhones(List<String> a, List<String> b) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in <String>[...a, ...b]) {
      final trimmed = value.trim();
      final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      final key = digits.isEmpty ? trimmed : digits;
      if (trimmed.isNotEmpty && seen.add(key)) result.add(trimmed);
    }
    return result;
  }
}
