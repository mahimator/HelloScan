import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parsed_card.dart';

/// Optional semantic correction for ambiguous person/company OCR candidates.
///
/// The deterministic parser remains the source of truth for contact data.
/// This layer may only select text that already exists in the OCR transcript —
/// it never invents, completes, or corrects words. A failure to download,
/// load, or run the engine returns [parsed] unchanged, so OCR is never blocked.
class SemanticCardRefiner {
  SemanticCardRefiner._();

  static final SemanticCardRefiner instance = SemanticCardRefiner._();

  /// SmolLM2-135M-Instruct Q4_K_M from Hugging Face. Small enough to run
  /// on-device on entry-level phones, large enough to disambiguate names
  /// from companies.
  static const String modelUri =
      'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
      'SmolLM2-135M-Instruct-Q4_K_M.gguf';

  static const String _prefsEnabledKey = 'semantic_refiner.enabled';
  static const String _prefsModelLoadedKey = 'semantic_refiner.model_loaded';

  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;
  Future<void> _inferenceQueue = Future<void>.value();
  bool _enabled = true;
  bool _modelLoaded = false;

  /// Whether the neural semantic layer is enabled for OCR disambiguation.
  bool get isEnabled => _enabled;

  /// Whether the underlying engine is loaded and ready.
  bool get isLoaded => _engine != null;

  /// Human-friendly corporate status for the neural layer.
  String get statusLabel {
    if (!_enabled) return 'Neural Semantic Engine: Standby';
    if (_engine != null) return 'Neural Semantic Engine: Online';
    if (_loading != null) return 'Neural Semantic Engine: Initializing…';
    return _modelLoaded ? 'Neural Semantic Engine: Cached' : 'Neural Semantic Engine: Offline';
  }

  /// Color-ish status string for UI chips.
  String get statusChip {
    if (!_enabled) return 'standby';
    if (_engine != null) return 'online';
    return 'offline';
  }

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsEnabledKey) ?? true;
    _modelLoaded = prefs.getBool(_prefsModelLoadedKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, value);
  }

  Future<LlamaEngine> _getEngine() {
    if (_engine != null) return Future.value(_engine!);
    return _loading ??= _loadEngine();
  }

  Future<LlamaEngine> _loadEngine() async {
    try {
      print('HelloScan: Neural engine loading model from Hugging Face…');
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.parse(modelUri)),
        // Keep native memory use predictable on entry-level Android devices.
        // The task is short text classification, so a 1K context is sufficient.
        params: const ModelParams(
          contextSize: 1024,
          batchSize: 128,
          microBatchSize: 128,
          maxParallelSequences: 1,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          gpuLayers: 0,
        ),
      );
      _engine = engine;
      _loading = null;
      _modelLoaded = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsModelLoadedKey, true);
      print('HelloScan: Neural engine model loaded successfully');
      return engine;
    } catch (e) {
      _loading = null;
      print('HelloScan: Neural engine load failed: $e');
      rethrow;
    }
  }

  /// Explicitly download and initialize the neural engine. Safe to call
  /// multiple times; subsequent calls are no-ops once loaded.
  Future<void> preloadModel() async {
    if (_engine != null) return;
    await _getEngine();
  }

  /// Refines only the name/company pair. All other parsed fields are retained.
  /// Skips inference entirely when disabled or when the rule-based parser
  /// already has a clear, corroborated company and plausible person name.
  Future<T> _serializeInference<T>(Future<T> Function() operation) async {
    final previous = _inferenceQueue;
    final release = Completer<void>();
    _inferenceQueue = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<ParsedCard> refine(ParsedCard parsed) {
    // llama.cpp owns native state. Never issue overlapping generations against
    // the same engine, even if paste, single scan, and batch paths overlap.
    return _serializeInference(() => _refineSerial(parsed));
  }

  Future<ParsedCard> _refineSerial(ParsedCard parsed) async {
    if (!_enabled) return parsed;

    final raw = parsed.rawText.trim();
    if (raw.isEmpty) return parsed;

    final needsReview = parsed.company.isEmpty ||
        parsed.company.trim().split(RegExp(r'\s+')).length == 1 ||
        parsed.name.isEmpty ||
        _looksLikeSloganOrInstruction(parsed.name) ||
        _looksLikeSloganOrInstruction(parsed.company);
    if (!needsReview) return parsed;

    try {
      print('HelloScan: Neural engine starting inference…');
      final engine = await _getEngine();
      print('HelloScan: Neural engine loaded, running inference…');
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

      print('HelloScan: Neural engine inference complete');
      final result = _decode(output);
      if (result == null || result.confidence < 0.55) {
        print('HelloScan: Neural engine returned low confidence or null');
        return parsed;
      }

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
    } catch (e) {
      // Engine failures must never block OCR.
      print('HelloScan: Neural engine inference failed: $e');
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
    // Permit the engine to join adjacent logo lines, but never accept text
    // that cannot be reconstructed from two neighboring OCR lines.
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
