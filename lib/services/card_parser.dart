import '../models/parsed_card.dart';
import '../models/ocr_document.dart';

/// Turns noisy OCR text from a visiting card into structured contact fields.
///
/// Real-world cards (and real-world OCR) are messy: bad spacing, `O`/`0` and
/// `l`/`1` confusions, lowercase-generated capitals, missing punctuation and
/// text that runs across columns. The parser combines normalization, pattern
/// matching and layout heuristics to recover as much as possible, and never
/// throws on garbage input.
class CardParser {
  const CardParser();

  // ---------------------------------------------------------------------------
  // Patterns and vocabularies
  // ---------------------------------------------------------------------------

  static final RegExp _emailPattern = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _urlPattern = RegExp(
    r'(?:https?://)?(?:www\.)?(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}(?:/[^\s,;]*)?',
    caseSensitive: false,
  );

  static final RegExp _phoneCandidate = RegExp(r'\+?\d[\d\s().\-]{5,}\d');

  static const Set<String> _knownTlds = <String>{
    'com',
    'net',
    'org',
    'io',
    'co',
    'ai',
    'dev',
    'app',
    'tech',
    'info',
    'biz',
    'us',
    'uk',
    'ug',
    'ke',
    'tz',
    'rw',
    'za',
    'nl',
    'in',
    'ca',
    'de',
    'fr',
    'au',
    'sg',
    'jp',
    'cn',
    'xyz',
    'me',
    'site',
    'online',
    'store',
    'club',
    'pro',
    'live',
    'cloud',
    'agency',
    'studio',
    'design',
    'group',
    'world',
    'global',
    'email',
    'mail',
    'edu',
    'gov',
    'mil',
    'tv',
    'cc',
    'ly',
    'to',
    'gg',
    'link',
  };

  static const Set<String> _publicEmailDomains = <String>{
    'gmail',
    'googlemail',
    'yahoo',
    'hotmail',
    'outlook',
    'live',
    'msn',
    'icloud',
    'me',
    'protonmail',
    'proton',
    'aol',
    'rediffmail',
    'zoho',
    'yandex',
    'mail',
  };

  static const List<String> _designationKeywords = <String>[
    'ceo',
    'cto',
    'cfo',
    'coo',
    'cmo',
    'vp',
    'svp',
    'evp',
    'vice president',
    'president',
    'founder',
    'co-founder',
    'cofounder',
    'director',
    'manager',
    'head',
    'lead',
    'engineer',
    'developer',
    'designer',
    'analyst',
    'consultant',
    'architect',
    'specialist',
    'officer',
    'executive',
    'partner',
    'owner',
    'proprietor',
    'advocate',
    'attorney',
    'doctor',
    'professor',
    'scientist',
    'accountant',
    'recruiter',
    'sales',
    'marketing',
    'operations',
    'supervisor',
    'coordinator',
    'associate',
    'assistant',
    'intern',
    'advisor',
    'strategist',
    'editor',
    'writer',
    'photographer',
    'teacher',
    'principal',
    'dean',
    'chairman',
    'chairperson',
    'secretary',
    'treasurer',
    'general manager',
    'senior manager',
    'project manager',
    'product manager',
    'team lead',
    'tech lead',
    'managing director',
    'managing partner',
    'sr. manager',

    // Trades / skilled professions
    'mechanic',
    'electrician',
    'plumber',
    'carpenter',
    'welder',
    'mason',
    'painter',
    'technician',
    'hvac',
    'locksmith',
    'landscaper',
    'gardener',
    'janitor',
    'cleaner',
    'driver',
    'chauffeur',
    'pilot',
    'captain',
    'operator',
    'machinist',
    'fabricator',
    'fitter',
    'inspector',
    'surveyor',
    'draftsman',
    'delineator',
    'estimator',
    'foreman',
    'superintendent',
    'contractor',
    'subcontractor',
    'builder',
    'developer',
    'real estate agent',
    'realtor',
    'broker',
    'appraiser',

    // Medical / healthcare
    'physician',
    'surgeon',
    'dentist',
    'orthodontist',
    'veterinarian',
    'vet',
    'nurse',
    'midwife',
    'paramedic',
    'therapist',
    'psychologist',
    'psychiatrist',
    'counselor',
    'social worker',
    'pharmacist',
    'optometrist',
    'chiropractor',
    'nutritionist',
    'dietitian',
    'hygienist',
    'technologist',
    'sonographer',
    'radiologist',
    'anesthesiologist',
    'pediatrician',
    'dermatologist',
    'cardiologist',
    'oncologist',
    'neurologist',
    'orthopedist',
    'gynecologist',
    'urologist',
    'podiatrist',
    'audiologist',
    'speech therapist',
    'occupational therapist',
    'physical therapist',
    'massage therapist',
    'acupuncturist',
    'homeopath',
    'naturopath',

    // Legal
    'lawyer',
    'barrister',
    'solicitor',
    'counsel',
    'notary',
    'paralegal',
    'judge',
    'magistrate',
    'advocate',

    // Education
    'lecturer',
    'instructor',
    'trainer',
    'tutor',
    'coach',
    'librarian',
    'registrar',
    'administrator',

    // Creative / media
    'artist',
    'illustrator',
    'animator',
    'videographer',
    'filmmaker',
    'director',
    'producer',
    'editor',
    'journalist',
    'reporter',
    'anchor',
    'presenter',
    'actor',
    'musician',
    'singer',
    'composer',
    'dancer',
    'choreographer',
    'makeup artist',
    'stylist',
    'barber',
    'hairdresser',
    'cosmetologist',
    'esthetician',
    'manicurist',
    'interior designer',
    'fashion designer',
    'graphic designer',
    'web designer',
    'ux designer',
    'ui designer',

    // Technical / IT
    'programmer',
    'coder',
    'sysadmin',
    'administrator',
    'network engineer',
    'systems engineer',
    'software engineer',
    'hardware engineer',
    'qa engineer',
    'tester',
    'analyst',
    'scrum master',
    'product owner',
    'data scientist',
    'data analyst',
    'devops',
    'security analyst',
    'penetration tester',
    'architect',

    // Service / hospitality / retail
    'waiter',
    'waitress',
    'server',
    'bartender',
    'barista',
    'chef',
    'cook',
    'host',
    'hostess',
    'cashier',
    'sales associate',
    'salesperson',
    'retail associate',
    'stylist',
    'receptionist',
    'concierge',
    'bellhop',
    'housekeeper',
    'valet',
    'doorman',
    'security guard',
    'guard',
    'patrol officer',
    'detective',
    'investigator',
    'agent',
    'broker',

    // Misc / service
    'clergy',
    'pastor',
    'priest',
    'minister',
    'rabbi',
    'imam',
    'monk',
    'nun',
    'officiant',
    'celebrant',
  ];

  static const List<String> _companyKeywords = <String>[
    'inc',
    'llc',
    'ltd',
    'limited',
    'pvt',
    'private',
    'corp',
    'corporation',
    'company',
    'co',
    'llp',
    'gmbh',
    'plc',
    'solutions',
    'technologies',
    'technology',
    'systems',
    'services',
    'labs',
    'group',
    'enterprises',
    'industries',
    'ventures',
    'consulting',
    'studio',
    'agency',
    'associates',
    'holdings',
    'partners',
    'international',
    'global',
    'traders',
    'exports',
    'imports',
    'enterprise',
    // Common industry descriptors: many real companies omit legal suffixes.
    'utilities',
    'utility',
    'minerals',
    'mineral',
    'mining',
    'chocolate',
    'foods',
    'food',
    'beverages',
    'beverage',
    'manufacturing',
    'logistics',
    'foundation',
    'institute',
    'university',
    'hospital',
    'clinic',
    'hotel',
    'construction',
    'engineering',
    'energy',
    'agriculture',
  ];

  static const List<String> _addressKeywords = <String>[
    'street',
    'road',
    'avenue',
    'boulevard',
    'lane',
    'drive',
    'suite',
    'floor',
    'block',
    'sector',
    'plot',
    'nagar',
    'colony',
    'district',
    'state',
    'pin',
    'zip',
    'po box',
    'apartment',
    'building',
    'tower',
    'park',
    'estate',
    'phase',
    'unit',
    'near',
    'opposite',
    'opp',
    'cross',
    'main',
    'layout',
  ];

  /// Common words that are never a person's name — hard exclusion layer.
  static const Set<String> _nonNameKeywords = <String>{
    'hello', 'hi', 'hey', 'welcome', 'contact', 'card', 'business', 'visit',
    'phone', 'mobile', 'tel', 'telephone', 'call', 'cell', 'fax', 'email',
    'mail', 'e-mail', 'website', 'web', 'url', 'www', 'address', 'addr',
    'designation', 'title', 'company', 'organization', 'organisation',
    'office', 'direct', 'location', 'notes', 'name', 'full', 'first', 'last',
    'surname', 'given', 'middle', 'initial', 'mr', 'mrs', 'ms', 'miss', 'dr',
    'prof', 'sir', 'madam', 'the', 'and', 'or', 'of', 'at', 'to', 'for',
    'with', 'in', 'on', 'by', 'from', 'as', 'is', 'it', 'this', 'that',
    'pvt', 'ltd', 'inc', 'llc', 'corp', 'limited', 'private', 'corporation',
    'technologies', 'solutions', 'systems', 'services', 'group',
  };

  static const List<String> _labelStrips = <String>[
    'name',
    'full name',
    'contact',
    'email',
    'e-mail',
    'mail',
    'phone',
    'mobile',
    'mob',
    'tel',
    'telephone',
    'ph',
    'fax',
    'website',
    'web',
    'url',
    'www',
    'address',
    'addr',
    'designation',
    'title',
    'company',
    'organization',
    'organisation',
    'office',
    'cell',
    'direct',
    'call',
  ];

  /// Single-letter labels such as "M:" / "T:" that appear on compact cards.
  static const String _singleLetterLabels = 'mtopfd';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Parses a single block of OCR text.
  ParsedCard parse(String rawText) {
    final text = _normalizeText(rawText);
    if (text.trim().isEmpty) return ParsedCard.empty;

    final lines = text
        .split('\n')
        .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) return ParsedCard.empty;

    var emails = _extractEmails(text);
    final websites = _extractWebsites(text, emails);
    // OCR often misreads a single character in the email domain (n vs m,
    // rn vs m). When a website is present it is usually cleaner, so use it
    // to repair near-miss email domains.
    final canonicalHost = _canonicalHost(websites, emails);
    emails = _reconcileEmails(emails, canonicalHost);
    final phones = _extractPhones(lines, emails, websites);
    final address = _extractAddress(lines, phones);
    final designation = _extractDesignation(lines);
    var company = _extractCompany(lines, emails, websites, designation.text);
    company = _reconcileCompany(company, canonicalHost);
    final name = _extractName(
      lines,
      emails,
      websites,
      phones,
      address,
      designation,
      company,
    );

    return ParsedCard(
      name: name,
      designation: designation.text,
      company: company,
      email: emails.isNotEmpty ? emails.first : '',
      phone: phones.isNotEmpty ? phones.first : '',
      website: websites.isNotEmpty ? websites.first : '',
      address: address,
      emails: emails,
      phones: phones,
      rawText: text,
    );
  }

  /// Parses structured OCR documents while preserving ML Kit's block and
  /// line grouping. This prevents consumers from flattening all recognized
  /// words into a single unstructured token stream before classification.
  ParsedCard parseManyDocuments(Iterable<OcrDocument> documents) {
    final texts = documents.map((document) {
      final blockText = document.blocks
          .map((block) => block.lines
              .map((line) => line.text.trim())
              .where((line) => line.isNotEmpty)
              .join('\n'))
          .where((block) => block.isNotEmpty)
          .join('\n');
      return blockText.isNotEmpty ? blockText : document.text;
    });
    return parseMany(texts);
  }

  /// Parses and merges multiple sides of the same card (front and back).
  ParsedCard parseMany(Iterable<String> texts) {
    var result = ParsedCard.empty;
    for (final text in texts) {
      result = result.merge(parse(text));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Normalization
  // ---------------------------------------------------------------------------

  String _normalizeText(String input) {
    var text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    const replacements = <String, String>{
      '\u00a0': ' ',
      '\u2007': ' ',
      '\u202f': ' ',
      '\t': ' ',
      '\u2010': '-',
      '\u2011': '-',
      '\u2012': '-',
      '\u2013': '-',
      '\u2014': '-',
      '\u2015': '-',
      '\uff20': '@',
      '\uff0e': '.',
      '\uff0d': '-',
      '\uff0b': '+',
      '\uff1a': ':',
    };
    replacements.forEach((from, to) => text = text.replaceAll(from, to));

    // Bracket-style obfuscation: "name [at] domain [dot] com".
    text = text.replaceAll(
      RegExp(r'\[\s*at\s*\]|\(\s*at\s*\)', caseSensitive: false),
      '@',
    );
    text = text.replaceAll(
      RegExp(r'\[\s*dot\s*\]|\(\s*dot\s*\)', caseSensitive: false),
      '.',
    );

    return text;
  }

  // ---------------------------------------------------------------------------
  // Email
  // ---------------------------------------------------------------------------

  List<String> _extractEmails(String text) {
    // Collapse spaces that OCR often leaves around "@" and "." so that
    // "john @ acme . com" still becomes a candidate.
    final compact = text
        .replaceAll(RegExp(r'\s*@\s*'), '@')
        .replaceAll(RegExp(r'\s*\.\s*'), '.');

    final found = <String>[];
    for (final match in _emailPattern.allMatches(compact)) {
      final email = _fixEmail(match.group(0)!);
      if (email.isNotEmpty && !found.contains(email)) found.add(email);
    }
    return found;
  }

  String _fixEmail(String input) {
    var email = input.trim();
    email = email.replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '');
    email = email.replaceAll(RegExp(r'[.,;:]+$'), '');

    final at = email.indexOf('@');
    if (at <= 0) return '';

    var local = email.substring(0, at);
    var domain = email.substring(at + 1).toLowerCase();

    domain = domain
        .replaceAll(RegExp(r'\.con$'), '.com')
        .replaceAll(RegExp(r'\.corn$'), '.com')
        .replaceAll(RegExp(r'\.c0rn$'), '.com')
        .replaceAll(RegExp(r'\.c0m$'), '.com')
        .replaceAll(RegExp(r'\.ocm$'), '.com')
        .replaceAll(RegExp(r'\.cm$'), '.com')
        .replaceAll(RegExp(r'^gmai1\.'), 'gmail.')
        .replaceAll(RegExp(r'^gma1l\.'), 'gmail.')
        .replaceAll(RegExp(r'^gmail\.c0m$'), 'gmail.com')
        .replaceAll(RegExp(r'^hotmai1\.'), 'hotmail.')
        .replaceAll(RegExp(r'^outl00k\.'), 'outlook.')
        .replaceAll(RegExp(r'^yah00\.'), 'yahoo.')
        .replaceAll(RegExp(r'^yaho0\.'), 'yahoo.');

    local = local.replaceAll(RegExp(r'[^A-Za-z0-9._%+\-]'), '');

    if (local.isEmpty || !domain.contains('.')) return '';
    final candidate = '$local@$domain';
    return RegExp(
          r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
        ).hasMatch(candidate)
        ? candidate
        : '';
  }

  // ---------------------------------------------------------------------------
  // Websites
  // ---------------------------------------------------------------------------

  List<String> _extractWebsites(String text, List<String> emails) {
    // Normalize spacing the same way as email extraction so an email's own
    // domain is not mistaken for the company website.
    var cleaned = text
        .replaceAll(RegExp(r'\s*@\s*'), '@')
        .replaceAll(RegExp(r'\s*\.\s*'), '.');
    for (final email in emails) {
      cleaned = cleaned.replaceAll(email, ' ');
    }

    final results = <String>[];
    for (final match in _urlPattern.allMatches(cleaned)) {
      final trimmed = match.group(0)!.replaceAll(RegExp(r'[.,;:)\]}]+$'), '');
      if (trimmed.isEmpty) continue;

      final lower = trimmed.toLowerCase();
      if (_looksLikeFile(lower)) continue;

      final hasScheme =
          lower.startsWith('http://') || lower.startsWith('https://');
      final hasWww = lower.startsWith('www.');
      final host = _hostOf(lower);
      if (host.isEmpty || !host.contains('.')) continue;

      final tld = host.split('.').last;
      if (!hasScheme && !hasWww && !_knownTlds.contains(tld)) continue;

      if (!results.contains(trimmed)) results.add(trimmed);
    }
    return results;
  }

  bool _looksLikeFile(String value) {
    return RegExp(
      r'\.(jpg|jpeg|png|gif|bmp|webp|pdf|doc|docx|xls|xlsx|ppt|pptx|zip)$',
    ).hasMatch(value);
  }

  String _hostOf(String value) {
    var host = value.trim().toLowerCase();
    host = host.replaceFirst(RegExp(r'^[a-z]+://'), '');
    host = host.split('/').first;
    host = host.split('?').first;
    host = host.split('#').first;
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  String _rootLabel(String host) {
    final parts = host.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    // For "mail.acme.com" prefer "acme" over "mail".
    if (parts.length > 2 &&
        _publicEmailDomains.contains(parts.first.toLowerCase()) &&
        parts.length >= 3) {
      return parts[parts.length - 2];
    }
    return parts.first;
  }

  // ---------------------------------------------------------------------------
  // Phone
  // ---------------------------------------------------------------------------

  List<String> _extractPhones(
    List<String> lines,
    List<String> emails,
    List<String> websites,
  ) {
    final phones = <String>[];

    for (final original in lines) {
      if (emails.any((email) => original.contains(email))) continue;
      if (websites.any((site) => original.contains(site))) continue;

      final lower = original.toLowerCase();
      final labeled =
          RegExp(
            r'\b(tel|phone|mobile|mob|cell|call|ph|fax|contact)\b',
          ).hasMatch(lower) ||
          RegExp(r'(^|\s)[mtfph]\s*[:\-]').hasMatch(lower);
      final digits = original.replaceAll(RegExp(r'[^0-9]'), '').length;
      final letters = original.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
      final numericish = digits >= 6 && digits >= letters;

      if (!labeled && !numericish) continue;

      final line = _fixNumericConfusions(original);
      for (final match in _phoneCandidate.allMatches(line)) {
        final normalized = _normalizePhone(match.group(0)!);
        if (normalized.isEmpty) continue;
        final digitsOnly = normalized.replaceAll(RegExp(r'[^0-9]'), '');
        final duplicate = phones.any(
          (phone) => phone.replaceAll(RegExp(r'[^0-9]'), '') == digitsOnly,
        );
        if (!duplicate) phones.add(normalized);
      }
    }

    return phones;
  }

  /// Repairs common OCR confusions inside digit-heavy tokens only, so words
  /// such as "Mobile" or "Solutions" are never corrupted.
  String _fixNumericConfusions(String line) {
    final tokens = line.split(' ');
    final out = <String>[];

    for (final token in tokens) {
      final digits = token.replaceAll(RegExp(r'[^0-9]'), '').length;
      final alphanumeric = token.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length;
      final confusable = token
          .replaceAll(RegExp(r'[^0-9OoIlSsBb|]'), '')
          .length;

      final shouldFix =
          digits >= 2 &&
          confusable >= 4 &&
          alphanumeric > 0 &&
          confusable >= alphanumeric * 0.6;

      if (!shouldFix) {
        out.add(token);
        continue;
      }

      out.add(
        token
            .replaceAll('O', '0')
            .replaceAll('o', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1')
            .replaceAll('|', '1')
            .replaceAll('S', '5')
            .replaceAll('s', '5')
            .replaceAll('B', '8')
            .replaceAll('b', '6'),
      );
    }

    return out.join(' ');
  }

  String _normalizePhone(String raw) {
    var value = raw.trim();

    // Strip extension indicators ("ext 123", "x123", "extension 123") so the
    // extension digits are not appended to the main number.
    value = value.replaceAll(
      RegExp(r'\s*(ext|extension|x)\s*\d+', caseSensitive: false),
      '',
    );

    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    // "00" international prefix is commonly written instead of "+".
    if (digits.startsWith('00') && digits.length > 10) {
      digits = digits.substring(2);
      value = '+$digits';
      return value;
    }

    final hadPlus = value.startsWith('+');
    if (digits.length < 7 || digits.length > 15) return '';
    return hadPlus ? '+$digits' : digits;
  }

  // ---------------------------------------------------------------------------
  // Address
  // ---------------------------------------------------------------------------

  String _extractAddress(List<String> lines, List<String> phones) {
    final addressLines = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_looksLikePhoneLine(line, phones)) continue;
      if (line.contains('@')) continue;
      if (_urlPattern.hasMatch(line)) continue;

      final lower = line.toLowerCase();
      final hasKeyword = _addressKeywords.any(
        (keyword) => _hasKeyword(lower, keyword),
      );
      final startsWithNumber =
          RegExp(r'^\s*\d{1,6}[\s,/\-]').hasMatch(line) &&
          RegExp(r'[A-Za-z]{3,}').hasMatch(line);
      final pinLike =
          RegExp(r'\b\d{5,6}\b').hasMatch(line) &&
          RegExp(r'[A-Za-z]').hasMatch(line);
      final cityStateLike =
          RegExp(r'\b[A-Za-z]{3,}\b').hasMatch(line) &&
          (RegExp(r'\b\d{5,6}\b').hasMatch(line) ||
              _addressKeywords.any((kw) => _hasKeyword(lower, kw)));

      if (hasKeyword || startsWithNumber || pinLike || cityStateLike) {
        addressLines.add(line.trim());
        // OCR often splits an address across two lines (street / city-pin).
        // Grab the next line if it looks like a continuation and hasn't been
        // claimed as a phone, email or website.
        if (i + 1 < lines.length) {
          final next = lines[i + 1];
          if (!_looksLikePhoneLine(next, phones) &&
              !next.contains('@') &&
              !_urlPattern.hasMatch(next) &&
              !_designationKeywords.any((kw) =>
                  _hasKeyword(next.toLowerCase(), kw)) &&
              RegExp(r'[A-Za-z]').hasMatch(next)) {
            addressLines.add(next.trim());
          }
        }
      }
    }

    final unique = <String>[];
    for (final entry in addressLines) {
      if (!unique.any((value) => value.toLowerCase() == entry.toLowerCase())) {
        unique.add(entry);
      }
    }
    return unique.join(', ');
  }

  bool _looksLikePhoneLine(String line, List<String> phones) {
    final lineDigits = line.replaceAll(RegExp(r'[^0-9]'), '');
    if (lineDigits.length < 7) return false;
    for (final phone in phones) {
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 7 && lineDigits.contains(digits)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Designation
  // ---------------------------------------------------------------------------

  ({String text, int index}) _extractDesignation(List<String> lines) {
    var best = '';
    var bestIndex = -1;
    var bestScore = 0;

    for (var i = 0; i < lines.length; i++) {
      final candidate = _stripLabel(lines[i]);
      if (candidate.isEmpty || candidate.length > 60) continue;
      if (_emailPattern.hasMatch(candidate) ||
          _urlPattern.hasMatch(candidate)) {
        continue;
      }
      if (RegExp(r'\d{3,}').hasMatch(candidate)) continue;

      final lower = candidate.toLowerCase();
      var score = 0;
      for (final keyword in _designationKeywords) {
        if (_hasKeyword(lower, keyword)) {
          score += keyword.contains(' ') || keyword.contains('.') ? 3 : 2;
        }
      }
      // Do not penalize a designation because it contains a descriptor
      // that can also occur in an organization name (e.g. "Water Solutions
      // Engineer"). A strong role keyword should remain decisive.

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
        bestIndex = i;
      }
    }

    if (bestScore < 2) return (text: '', index: -1);
    return (text: _cleanEntity(best), index: bestIndex);
  }

  // ---------------------------------------------------------------------------
  // Company
  // ---------------------------------------------------------------------------

  String _extractCompany(
    List<String> lines,
    List<String> emails,
    List<String> websites,
    String designation,
  ) {
    // A domain can corroborate a printed company name, but must never be
    // converted into a company name by itself.
    final rootLabels = <String>{};
    for (final website in websites) {
      final label = _rootLabel(_hostOf(website));
      if (label.isNotEmpty &&
          !_publicEmailDomains.contains(label.toLowerCase())) {
        rootLabels.add(label);
      }
    }
    for (final email in emails) {
      final at = email.indexOf('@');
      if (at < 0) continue;
      final label = _rootLabel(email.substring(at + 1));
      if (label.isNotEmpty &&
          !_publicEmailDomains.contains(label.toLowerCase())) {
        rootLabels.add(label);
      }
    }

    var best = '';
    var bestScore = -1000;
    final candidates = <({String text, int index})>[];

    for (var i = 0; i < lines.length; i++) {
      candidates.add((text: lines[i], index: i));

      // Logos are frequently split across two OCR lines:
      // "HEIFER" / "INTERNATIONAL", "SAMANGA" / "UTILITIES".
      if (i + 1 >= lines.length) continue;
      final first = lines[i].trim();
      final second = lines[i + 1].trim();
      if (first.isEmpty || second.isEmpty ||
          first.length > 35 || second.length > 35) {
        continue;
      }
      if (_emailPattern.hasMatch(first) || _emailPattern.hasMatch(second) ||
          _urlPattern.hasMatch(first) || _urlPattern.hasMatch(second)) {
        continue;
      }
      if (_designationKeywords.any((kw) => _hasKeyword(first.toLowerCase(), kw)) ||
          _designationKeywords.any((kw) => _hasKeyword(second.toLowerCase(), kw))) {
        continue;
      }
      if (_isLikelyName(first) || _isLikelyName(second)) continue;

      final combined = '$first $second';
      final hasMarker = _hasCompanySuffix(combined) ||
          _hasIndustryCompanyEnding(combined);
      final hasDomainMatch = rootLabels.any((root) => _domainMatches(combined, root));
      if (hasMarker || hasDomainMatch) {
        candidates.add((text: combined, index: i));
      }
    }

    for (final item in candidates) {
      final candidate = _cleanEntity(_stripLabel(item.text));
      if (candidate.isEmpty || candidate.length > 80) continue;
      if (_emailPattern.hasMatch(candidate)) continue;
      if (_urlPattern.hasMatch(candidate) && !candidate.contains(' ')) continue;

      final lower = candidate.toLowerCase();

      // Never classify job titles, people, addresses or promotional copy as
      // an organization. Slogan filtering is deliberately conservative.
      if (_designationKeywords.any((kw) => _hasKeyword(lower, kw))) continue;
      if (_looksLikeCompanySlogan(lower)) continue;
      if (_addressKeywords.any((kw) => _hasKeyword(lower, kw)) &&
          RegExp(r'\d').hasMatch(candidate)) {
        continue;
      }

      final legalSuffix = _hasCompanySuffix(candidate);
      final industryEnding = _hasIndustryCompanyEnding(candidate);
      final domainMatch = rootLabels.any((root) => _domainMatches(candidate, root));

      var score = 0;
      if (legalSuffix) score += 14;
      if (industryEnding) score += 9;
      if (domainMatch) score += 25;

      // An unmarked multiword brand is accepted only when corroborated by
      // the website/email domain. A single-word brand without a suffix is
      // intentionally left for manual correction.
      if (!legalSuffix && !industryEnding && !domainMatch) continue;

      // Prefer concise, brand-like lines over long promotional phrases.
      final count = wordsCount(candidate);
      if (count >= 2 && count <= 5) score += 2;
      if (count > 6) score -= 5;
      if (item.index <= 3) score += 2;
      if (candidate == candidate.toUpperCase() &&
          RegExp(r'[A-Z]{2,}').hasMatch(candidate)) {
        score += 1;
      }

      // A confirmed domain match outranks suffix-only candidates.
      if (domainMatch) score += 10;

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best.isEmpty ? '' : _cleanEntity(best);
  }

  bool _hasCompanySuffix(String value) {
    // Legal forms, including common OCR punctuation/spacing variants.
    // The suffix must occur at the END of the candidate.
    return RegExp(
      r'(?:^|[\s,])(?:'
      r'pvt\.?\s*(?:ltd\.?|limited)|private\s+limited|'
      r'public\s+limited|'
      r'ltd\.?|limited|'
      r'llc|l\.l\.c\.|'
      r'inc\.?|incorporated|'
      r'corp\.?|corporation|'
      r'company|co\.|'
      r'llp|plc|'
      r'gmbh|ag|'
      r'pty\s*ltd\.?|'
      r'pte\.?\s*ltd\.?|'
      r'sdn\.?\s*bhd\.?|'
      r'bv|nv|'
      r's\.a\.?|s\.r\.l\.?|srl|s\.p\.a\.?|'
      r'sas|s\.a\.s\.?|sro|oy|ab|'
      r'fz-llc|fze|fzco'
      r')\s*\.?$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  bool _hasIndustryCompanyEnding(String value) {
    // Industry/organization descriptors commonly used as the final word(s)
    // of a trading name. This is intentionally an ending-only test.
    return RegExp(
      r'\b(?:'
      r'solutions?|technolog(?:y|ies)|systems?|services?|'
      r'labs?|laboratories|groups?|enterprises?|industries?|'
      r'ventures?|consulting|studios?|agenc(?:y|ies)|'
      r'associates?|holdings?|partners?|international|global|'
      r'traders?|exports?|imports?|utilities|utility|'
      r'minerals?|mining|chocolate|foods?|beverages?|'
      r'manufacturing|logistics|foundations?|institutes?|'
      r'universit(?:y|ies)|hospitals?|clinics?|hotels?|'
      r'construction|engineering|energy|agriculture'
      r')$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  bool _looksLikeCompanySlogan(String lower) {
    return RegExp(
      r'\b(?:'
      r'unlocking|building|delivering|empowering|transforming|'
      r'creating|connecting|inspiring|shaping|driving|'
      r'your\s+trusted|your\s+partner|we\s+(?:are|make|build|deliver)|'
      r'scan\s+to|scan\s+me|visit\s+us|follow\s+us|'
      r'lasting\s+value|potential|excellence|quality\s+first'
      r')\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  int wordsCount(String value) {
    return value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  bool _domainMatches(String candidate, String rootLabel) {
    final normalCandidate = candidate.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final normalRoot = rootLabel.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalRoot.length < 3 || normalCandidate.isEmpty) return false;
    if (normalCandidate.contains(normalRoot) ||
        normalRoot.contains(normalCandidate)) {
      return true;
    }

    // Business names and domains often share only the brand token:
    // "Samanga Utilities" / "samangasolutions.com". Treat a meaningful
    // token overlap as corroboration without synthesizing a company from
    // the domain itself.
    final tokens = candidate
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 4);
    return tokens.any((token) => normalRoot.contains(token));
  }

  // ---------------------------------------------------------------------------
  // Name
  // ---------------------------------------------------------------------------

  /// Hard semantic layer: returns false if [candidate] can never be a
  /// person's name, regardless of score.
  bool _isLikelyName(String candidate) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || trimmed.length > 50) return false;

    // Must contain at least one letter.
    if (!RegExp(r'[A-Za-z]').hasMatch(trimmed)) return false;

    // No digits allowed in a name.
    if (RegExp(r'\d').hasMatch(trimmed)) return false;

    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || words.length > 4) return false;

    // A person's name should have at least 2 words (single words are rarely
    // full names on business cards).
    if (words.length < 2) return false;

    final lower = trimmed.toLowerCase();

    // Explicit non-name keywords are never a name.
    if (_nonNameKeywords.contains(lower)) return false;

    // Designation words are never a name.
    if (_designationKeywords.any((kw) => _hasKeyword(lower, kw))) {
      return false;
    }

    // Company keywords are never a name.
    if (_companyKeywords.any((kw) => _hasKeyword(lower, kw))) {
      return false;
    }

    // Email or URL is never a name.
    if (_emailPattern.hasMatch(trimmed) || _urlPattern.hasMatch(trimmed)) {
      return false;
    }

    return true;
  }

  String _extractName(
    List<String> lines,
    List<String> emails,
    List<String> websites,
    List<String> phones,
    String address,
    ({String text, int index}) designation,
    String company,
  ) {
    var bestIndex = -1;
    var bestScore = -100;

    for (var i = 0; i < lines.length; i++) {
      final candidate = _stripLabel(lines[i]);
      if (!_isLikelyName(candidate)) continue;
      if (candidate == designation.text || candidate == company) continue;
      if (address.isNotEmpty && address.contains(candidate)) continue;
      if (_looksLikePhoneLine(candidate, phones)) continue;

      var score = 0;
      final words = candidate
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      if (words.length >= 2 && words.length <= 4) score += 3;
      if (candidate == candidate.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(candidate)) {
        score += 1;
      }

      final titleCase = words.where((word) => _isCapitalized(word)).length;
      if (titleCase >= (words.length / 2).ceil()) score += 2;
      if (i <= 2) score += 2;

      if (designation.index >= 0 &&
          (i == designation.index - 1 || i == designation.index + 1)) {
        score += 3;
      }

      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    if (bestIndex < 0 || bestScore < 2) return '';
    return _normalizeName(_stripLabel(lines[bestIndex]));
  }

  bool _isCapitalized(String word) {
    if (word.isEmpty) return false;
    final first = word[0];
    return first == first.toUpperCase() && first != first.toLowerCase();
  }

  String _normalizeName(String name) {
    var value = _cleanEntity(name);

    // Strip courtesy titles that OCR may have glued onto the name.
    value = value.replaceFirst(
      RegExp(r'^(Mr|Mrs|Ms|Miss|Dr|Prof|Sir|Madam)\s+', caseSensitive: false),
      '',
    );

    if (value.toUpperCase() == value && RegExp(r'[A-Z]').hasMatch(value)) {
      value = value
          .split(' ')
          .map(
            (word) => word
                .split('-')
                .map((part) {
                  if (part.isEmpty) return part;
                  return part[0].toUpperCase() +
                      part.substring(1).toLowerCase();
                })
                .join('-'),
          )
          .join(' ');
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  /// Picks the most reliable host for the card, preferring an explicit website.
  String _canonicalHost(List<String> websites, List<String> emails) {
    final ordered = <String>[...websites]
      ..sort((a, b) => _websiteRank(a).compareTo(_websiteRank(b)));
    for (final site in ordered) {
      final host = _hostOf(site);
      if (host.contains('.') && !_looksLikeFile(host)) return host;
    }
    for (final email in emails) {
      final at = email.indexOf('@');
      if (at < 0) continue;
      final host = email.substring(at + 1).toLowerCase();
      if (!host.contains('.')) continue;
      final root = _rootLabel(host).toLowerCase();
      if (!_publicEmailDomains.contains(root)) return host;
    }
    return '';
  }

  int _websiteRank(String site) {
    final lower = site.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return 0;
    if (lower.startsWith('www.')) return 1;
    return 2;
  }

  List<String> _reconcileEmails(List<String> emails, String canonicalHost) {
    if (canonicalHost.isEmpty) return emails;
    final canonical = canonicalHost.toLowerCase();
    return emails.map((email) {
      final at = email.indexOf('@');
      if (at <= 0) return email;
      final domain = email.substring(at + 1).toLowerCase();
      if (domain == canonical) return email;
      if (!_isNearMissDomain(domain, canonical)) return email;
      return '${email.substring(0, at)}@$canonical';
    }).toList();
  }

  /// True when two domains differ only by a likely OCR substitution in the
  /// registrable name (e.g. `acrme-tech.com` vs `acrne-tech.com`).
  bool _isNearMissDomain(String a, String b) {
    final rootA = _rootLabel(a).toLowerCase();
    final rootB = _rootLabel(b).toLowerCase();
    if (rootA == rootB) return false;
    if (rootA.length < 4 || rootB.length < 4) return false;
    return _editDistance(rootA, rootB) <= 1;
  }

  /// Repairs company names that were OCR'd one character away from the domain.
  String _reconcileCompany(String company, String canonicalHost) {
    if (company.isEmpty || canonicalHost.isEmpty) return company;
    final root = _rootLabel(canonicalHost).toLowerCase();
    final candidates = <String>{
      root,
      ...root.split(RegExp(r'[-_]')),
    }.where((value) => value.length >= 4).toList();
    if (candidates.isEmpty) return company;

    var changed = false;
    final repaired = company
        .split(' ')
        .map((word) {
          final cleaned = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
          if (cleaned.length < 4) return word;
          final lower = cleaned.toLowerCase();
          for (final candidate in candidates) {
            if (lower == candidate) return word;
            if (_editDistance(lower, candidate) <= 1) {
              changed = true;
              return word.replaceFirst(
                RegExp(RegExp.escape(cleaned)),
                _titleCaseWords(candidate),
              );
            }
          }
          return word;
        })
        .join(' ');

    return changed ? repaired : company;
  }

  int _editDistance(String a, String b) {
    final row = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      var diagonal = row[0];
      row[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final above = row[j];
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final insertion = row[j] + 1;
        final deletion = row[j - 1] + 1;
        final substitution = diagonal + cost;
        row[j] = _min3(insertion, deletion, substitution);
        diagonal = above;
      }
    }
    return row[b.length];
  }

  int _min3(int a, int b, int c) {
    final min = a < b ? a : b;
    return min < c ? min : c;
  }

  bool _hasKeyword(String haystack, String keyword) {
    final escaped = RegExp.escape(keyword);
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(haystack);
  }

  String _stripLabel(String line) {
    var value = line.trim();
    final match = RegExp(
      r'^([A-Za-z][A-Za-z .\-]{0,15})\s*[:\-]\s*',
    ).firstMatch(value);
    if (match != null) {
      final label = match.group(1)!.trim().toLowerCase();
      final isKnownLabel = label.length == 1
          ? _singleLetterLabels.contains(label)
          : _labelStrips.contains(label) ||
                _labelStrips.any(
                  (known) => known.length > 1 && label.startsWith(known),
                );
      if (isKnownLabel) value = value.substring(match.end);
    }
    return value.trim();
  }

  String _cleanEntity(String value) {
    var cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'^[.,;:\-]+|[.,;:\-]+$'), '');
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([A-Za-z])\.([A-Z][a-z])'),
      (match) => '${match[1]}. ${match[2]}',
    );
    return cleaned.trim();
  }

  String _titleCaseWords(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}
