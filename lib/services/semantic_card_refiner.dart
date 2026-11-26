import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import '../models/parsed_card.dart';

/// Optional semantic correction for ambiguous person/company OCR candidates.
///
/// The deterministic parser remains the source of truth for contact data.
/// This model may only select text that already exists in the OCR transcript —
/// it never invents, completes, or corrects words. A failure to download,
/// load, or run the model returns [parsed] unchanged, so OCR is never blocked.
class SemanticCardRefiner {
  SemanticCardRefiner._();

  static final SemanticCardRefiner instance = SemanticCardRefiner._();

  /// SmolLM2-135M-Instruct Q4_K_M from Hugging Face. Small enough to run
  /// on-device on entry-level phones, large enough to disambiguate names
  /// from companies.
  static const String modelUri =
      'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
      'SmolLM2-135M-Instruct-Q4_K_M.gguf';

  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;

  bool get isLoaded => _engine != null;

  Future<LlamaEngine> _getEngine() {
    if (_engine != null) return Future.value(_engine!);
    return _loading ??= _loadEngine();
  }

  Future<LlamaEngine> _loadEngine() async {
    try {
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.parse(modelUri)),
      );
      _engine = engine;
      return engine;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  /// Refines only the name/company pair. All other parsed fields are retained.
  /// Skips inference entirely when the rule-based parser already has a clear,
  /// corroborated company and plausible person name.
  Future<ParsedCard> refine(ParsedCard parsed) async {
    final raw = parsed.rawText.trim();
    if (raw.isEmpty) return parsed;

    final needsReview = parsed.company.isEmpty ||
        parsed.company.trim().split(RegExp(r'\s+')).length == 1 ||
        parsed.name.isEmpty ||
        _looksLikeSloganOrInstruction(parsed.name) ||
        _looksLikeSloganOrInstruction(parsed.company);
    if (!needsReview) return parsed;

    try {
      final engine = await _getEngine();
      final lines = raw
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(35)
          .toList();

      final prompt = '''
You classify OCR text from a business card. Do not invent, complete, or correct words.
Select the person's full name and the organization/company name only when the exact
text appears in the OCR lines. A slogan, instruction, job title, address, website,
email, or QR prompt is not a person's name or company. A brand can be a company
without a legal suffix. If uncertain, return null for that field.

Return ONLY one JSON object, for example:
{"person_name":"Jane Doe","company":"Acme Foods","confidence":0.9}
Use JSON null when a field cannot be identified.

OCR lines:
${jsonEncode(lines)}
''';

      final output = await engine.create(
        [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: prompt,
          ),
        ],
        params: const GenerationParams(
          maxTokens: 100,
          topP: 0.8,
        ),
      ).text();

      final result = _decode(output);
      if (result == null || result.confidence < 0.55) return parsed;

      final refinedName = _verifiedSelection(result.personName, lines);
      final refinedCompany = _verifiedSelection(result.company, lines);

      return ParsedCard(
        name: refinedName ?? parsed.name,
        designation: parsed.designation,
        company: refinedCompany ?? parsed.company,
        email: parsed.email,
        phone: parsed.phone,
        website: parsed.website,
        address: parsed.address,
        emails: parsed.emails,
        phones: parsed.phones,
        rawText: parsed.rawText,
      );
    } catch (_) {
      // Model download, runtime, and generation failures must never block OCR.
      return parsed;
    }
  }

  _SemanticResult? _decode(String output) {
    final start = output.indexOf('{');
    final end = output.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(output.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;
      final confidence = decoded['confidence'];
      return _SemanticResult(
        personName: decoded['person_name'] is String
            ? decoded['person_name'] as String
            : null,
        company: decoded['company'] is String
            ? decoded['company'] as String
            : null,
        confidence: confidence is num ? confidence.toDouble() : 0,
      );
    } catch (_) {
      return null;
    }
  }

  String? _verifiedSelection(String? selected, List<String> lines) {
    final value = selected?.trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      return null;
    }
    final normalized = _normalize(value);
    if (normalized.isEmpty) return null;
    for (final line in lines) {
      if (_normalize(line) == normalized) return value;
    }
    // Permit a model to join adjacent logo lines, but never accept text that
    // cannot be reconstructed from two neighboring OCR lines.
    for (var i = 0; i + 1 < lines.length; i++) {
      if (_normalize('${lines[i]} ${lines[i + 1]}') == normalized) {
        return value;
      }
    }
    return null;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  bool _looksLikeSloganOrInstruction(String value) {
    return RegExp(
      r'\b(scan|visit|follow|unlocking|building|delivering|'
      r'potential|lasting|value|welcome|contact|call|email)\b',
      caseSensitive: false,
    ).hasMatch(value);
  }
}

class _SemanticResult {
  const _SemanticResult({
    required this.personName,
    required this.company,
    required this.confidence,
  });

  final String? personName;
  final String? company;
  final double confidence;
}
