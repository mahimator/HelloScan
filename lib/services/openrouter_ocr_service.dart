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
  static const String _model = 'meta-llama/llama-3.1-8b-instruct:free';

  static const String _prefsApiKeyKey = 'openrouter.api_key';
  static const String _prefsEnabledKey = 'openrouter.enabled';

  String? _apiKey;
  bool _enabled = false;

  /// Whether OpenRouter parsing is enabled.
  bool get isEnabled => _enabled;

  /// Whether an API key has been configured.
  bool get hasApiKey => _apiKey != null && _apiKey!.trim().isNotEmpty;

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_prefsApiKeyKey);
    _enabled = prefs.getBool(_prefsEnabledKey) ?? false;
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
You extract contact details from business card OCR text. Return ONLY a JSON object.

Extract these fields from the OCR text:
- person_name: the person's full name
- designation: job title
- company: organization name
- email: email address
- phone: phone number
- website: website URL
- address: full physical address

Rules:
- Use exact text from the OCR lines. Do not invent, complete, or correct words.
- If a field cannot be identified, use null.
- Return ONLY valid JSON, no markdown, no explanation.

OCR text:
${rawText}

Response format:
{"person_name":"...","designation":"...","company":"...","email":"...","phone":"...","website":"...","address":"..."}
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
          'max_tokens': 500,
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
        emails: _asString(cardData['email']) != null
            ? [_asString(cardData['email'])!]
            : const [],
        phones: _asString(cardData['phone']) != null
            ? [_asString(cardData['phone'])!]
            : const [],
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
