import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parsed_card.dart';

/// OpenRouter-powered business card parser.
///
/// Sends raw OCR text to OpenRouter's chat completion API and expects a
/// structured JSON object back with name, designation, company, email, phone,
/// website, and address fields. This is a separate, optional parsing path from
/// the deterministic CardParser — useful when local regex heuristics aren't
/// accurate enough.
///
/// The API key is stored locally in SharedPreferences and never leaves the
/// device except for the API request itself.
class OpenRouterOcrService {
  OpenRouterOcrService._();
  static final OpenRouterOcrService instance = OpenRouterOcrService._();

  static const String _baseUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const String _model = 'qwen/qwen2.5-72b-instruct:free';

  static const String _prefsApiKeyKey = 'openrouter.api_key';
  static const String _prefsEnabledKey = 'openrouter.enabled';

  String? _apiKey;
  bool _enabled = false;

  /// Whether OpenRouter parsing is enabled.
  bool get isEnabled => _enabled;

  /// Whether an API key has been configured.
  bool get hasApiKey => _apiKey != null && _apiKey!.trim().isNotEmpty;

  Future<void> loadPrefs() async {
    // First check for a locally-baked API key in lib/secrets.dart (gitignored,
    // never committed to the repo).
    final localKey = await _loadLocalApiKey();
    if (localKey != null && localKey.trim().isNotEmpty) {
      _apiKey = localKey.trim();
    }

    final prefs = await SharedPreferences.getInstance();
    if (_apiKey == null) {
      _apiKey = prefs.getString(_prefsApiKeyKey);
    }
    _enabled = prefs.getBool(_prefsEnabledKey) ?? false;
  }

  /// Reads the OpenRouter API key from lib/secrets.dart at runtime.
  ///
  /// This file is gitignored and never committed. Create it by copying
  /// lib/secrets.dart.template and replacing the placeholder with your key.
  static Future<String?> _loadLocalApiKey() async {
    try {
      final file = File('lib/secrets.dart');
      if (await file.exists()) {
        final content = await file.readAsString();
        final match = RegExp(
          "openRouterApiKey\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']",
        ).firstMatch(content);
        return match?.group(1);
      }
    } catch (_) {
      // Best-effort only; if the file can't be read, we just have no key.
    }
    return null;
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsApiKeyKey, _apiKey!);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, value);
  }

  /// Parses raw OCR text using OpenRouter. Returns a [ParsedCard] with the
  /// extracted fields. On any failure (network, bad response, missing key)
  /// returns [ParsedCard.empty] so the caller can fall back to local parsing.
  Future<ParsedCard> parse(String rawText) async {
    if (!hasApiKey || !_enabled) return ParsedCard.empty;

    try {
      final prompt = '''
You are a business card OCR extraction engine. Your ONLY job is to extract contact fields from noisy OCR text.

OCR TEXT:
${rawText}

EXTRACTION RULES (read carefully):
1. person_name: The person's full name. Usually near the top. Do NOT include titles like "CEO", "Manager", "Dr.", "Mr." unless they are part of the printed name. If unsure, leave empty.
2. designation: Job title / role (e.g. "Water Solutions Engineer", "Founder & CEO", "Sales Manager"). Do NOT confuse this with company name.
3. company: Organization/business name. Can be without a legal suffix (e.g. "Samanga Utilities", "Acme"). Do NOT extract email domains as company names.
4. email: Email address(es). Extract every email found.
5. phone: Phone number(s). Extract every phone found, normalize digits (remove spaces, dashes, parentheses).
6. website: Website URL (e.g. www.samangasolutions.com). Distinct from email domain.
7. address: Full physical address. Combine all address lines (street, city, state, postal code, country) into one string separated by ", ".

CRITICAL:
- Return text EXACTLY as it appears in the OCR. Do NOT invent, correct, or complete words.
- A job title like "Water Solutions Engineer" is NOT a company name. The company might be "Water Solutions" or something else entirely.
- If a field cannot be identified with confidence, return null for that field.
- Return ONLY valid JSON. No markdown, no explanation, no extra text.

JSON FORMAT:
{"person_name": "...", "designation": "...", "company": "...", "email": "...", "phone": "...", "website": "...", "address": "..."}

Use null for any field you cannot identify.
''';

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://helloscan.app',
          'X-Title': 'HelloScan',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
          'max_tokens': 800,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return ParsedCard.empty;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>;
      if (choices.isEmpty) return ParsedCard.empty;

      final message = choices[0]['message'] as Map<String, dynamic>;
      final content = message['content'] as String?;

      if (content == null || content.trim().isEmpty) return ParsedCard.empty;

      // Extract JSON from the response (may be wrapped in markdown).
      final jsonText = _extractJson(content);
      final cardData = jsonDecode(jsonText) as Map<String, dynamic>;

      return ParsedCard(
        name: _asString(cardData['person_name']) ?? '',
        designation: _asString(cardData['designation']) ?? '',
        company: _asString(cardData['company']) ?? '',
        email: _asString(cardData['email']) ?? '',
        phone: _asString(cardData['phone']) ?? '',
        website: _asString(cardData['website']) ?? '',
        address: _asString(cardData['address']) ?? '',
        emails: _extractList(cardData['emails'] ?? cardData['email']),
        phones: _extractList(cardData['phones'] ?? cardData['phone']),
        rawText: rawText,
      );
    } catch (_) {
      return ParsedCard.empty;
    }
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  /// Extracts a list of strings from either a JSON array or a comma/semicolon-separated string.
  List<String> _extractList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.whereType<String>().map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    }
    final str = value.toString().trim();
    if (str.isEmpty) return const [];
    return str.split(RegExp(r'[,;]')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
  }

  /// Strips markdown code fences and extracts the JSON object from the text.
  String _extractJson(String text) {
    text = text.trim();

    // Remove markdown code fences.
    final fenceRegex = RegExp(
      r'```(?:json)?\s*\n?(.*?)\n?\s*```',
      dotAll: true,
    );
    final fenceMatch = fenceRegex.firstMatch(text);
    if (fenceMatch != null && fenceMatch.groupCount >= 1) {
      return fenceMatch.group(1)!.trim();
    }

    // Find the first { and last } to isolate the JSON object.
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }

    return text;
  }
}
