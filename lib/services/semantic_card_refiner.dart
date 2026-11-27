import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parsed_card.dart';

/// Optional semantic correction for ambiguous person/company OCR candidates.
///
/// The deterministic parser remains the source of truth for contact data.
/// This layer may only select text that already exists in the OCR transcript —
/// it never invents, completes, or corrects words. A failure to load or run
/// the engine returns [parsed] unchanged, so OCR is never blocked.
///
/// The GGUF model is bundled with the app as a Flutter asset and copied to the
/// app's documents directory on first launch, so debug installs do not
/// re-download ~100 MB from Hugging Face every time.
class SemanticCardRefiner {
  SemanticCardRefiner._();

  static final SemanticCardRefiner instance = SemanticCardRefiner._();

  /// Hugging Face fallback URI (used only if the bundled asset is missing).
  static const String modelUri =
      'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
      'SmolLM2-135M-Instruct-Q4_K_M.gguf';

  static const String _assetModelPath =
      'assets/models/SmolLM2-135M-Instruct-Q4_K_M.gguf';
  static const String _fileName =
      'SmolLM2-135M-Instruct-Q4_K_M.gguf';

  static const String _prefsEnabledKey = 'semantic_refiner.enabled';
  static const String _prefsModelLoadedKey = 'semantic_refiner.model_loaded';
  static const String _prefsInferenceCountKey =
      'semantic_refiner.inference_count';
  static const String _prefsLastInferenceKey =
      'semantic_refiner.last_inference_result';

  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;
  Future<void> _inferenceQueue = Future<void>.value();
  bool _enabled = true;
  bool _modelLoaded = false;
  int _inferenceCount = 0;
  String _lastInferenceResult = 'not_run';

  /// Whether the neural semantic layer is enabled for OCR disambiguation.
  bool get isEnabled => _enabled;

  /// Whether the underlying engine is loaded and ready.
  bool get isLoaded => _engine != null;

  /// Total number of successful inference calls made.
  int get inferenceCount => _inferenceCount;

  /// Result of the last inference: 'ran', 'low_confidence', 'failed', or
  /// 'not_run'.
  String get lastInferenceResult => _lastInferenceResult;

  /// Human-friendly corporate status for the neural layer.
  String get statusLabel {
    if (!_enabled) return 'Neural Semantic Engine: Standby';
    if (_engine != null) {
      if (_inferenceCount > 0) {
        return 'Neural Semantic Engine: Online ($_inferenceCount inference${_inferenceCount == 1 ? '' : 's'})';
      }
      return 'Neural Semantic Engine: Online';
    }
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
    _enabled = prefs.getBool(_prefsEnabledKey) ?? false;
    _modelLoaded = prefs.getBool(_prefsModelLoadedKey) ?? false;
    _inferenceCount = prefs.getInt(_prefsInferenceCountKey) ?? 0;
    _lastInferenceResult = prefs.getString(_prefsLastInferenceKey) ?? 'not_run';
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, value);
  }

  /// Returns the local model path, copying from Flutter assets to the app's
  /// documents directory on first launch. Returns null if the asset cannot be
  /// resolved.
  Future<String?> _localModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final local = File('${dir.path}/$_fileName');
    if (await local.exists()) return local.path;

    try {
      final data = await rootBundle.load(_assetModelPath);
      await local.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return local.path;
    } catch (_) {
      return null;
    }
  }

  Future<LlamaEngine> _getEngine() {
    if (_engine != null) return Future.value(_engine!);
    return _loading ??= _loadEngine();
  }

  Future<LlamaEngine> _loadEngine() async {
    try {
      final localPath = await _localModelPath();
      if (localPath != null) {
        print('HelloScan: Loading bundled Neural Engine model from $localPath');
        final engine = await LlamaEngine.load(
          LlamaModel(ModelSource.path(localPath)),
        );
        _engine = engine;
        _loading = null;
        _modelLoaded = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefsModelLoadedKey, true);
        print('HelloScan: Neural Engine model loaded successfully (bundled)');
        return engine;
      }

      // Fallback: download from Hugging Face.
      print('HelloScan: Bundled model missing; downloading from Hugging Face…');
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
      print('HelloScan: Neural Engine model loaded successfully (downloaded)');
      return engine;
    } catch (e) {
      _loading = null;
      print('HelloScan: Neural Engine load failed: $e');
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
      print('HelloScan: Neural Engine starting inference…');
      final engine = await _getEngine();
      print('HelloScan: Neural Engine loaded, running inference…');
      final lines = raw
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(35)
          .toList();

      final prompt = '''
You classify OCR text from a business card. Return ONLY one JSON object.

Rules:
- Select the person's full name and the organization/company name ONLY when exact text appears in the OCR lines below.
- A slogan, instruction, job title, address, website, email, or QR prompt is NOT a person's name or company.
- A brand can be a company without a legal suffix (e.g. "Samanga Utilities" is a valid company).
- If a field cannot be identified, return null for that field.
- confidence: how sure you are (0.0 to 1.0). Be generous — if the text clearly appears in the OCR lines, give 0.8+.

Return format: {"person_name":"Jane Doe","company":"Acme Foods","confidence":0.9}
Use null for fields you cannot identify.

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

      print('HelloScan: Neural Engine inference complete');
      final result = _decode(output);
      if (result == null || result.confidence < 0.35) {
        print('HelloScan: Neural Engine returned low confidence or null');
        _lastInferenceResult = 'low_confidence';
        _inferenceCount++;
        await _persistStats();
        return parsed;
      }

      final refinedName = _verifiedSelection(result.personName, lines);
      final refinedCompany = _verifiedSelection(result.company, lines);

      _lastInferenceResult = 'ran';
      _inferenceCount++;
      await _persistStats();

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
      print('HelloScan: Neural Engine inference failed: $e');
      _lastInferenceResult = 'failed';
      _inferenceCount++;
      await _persistStats();
      // Engine failures must never block OCR.
      return parsed;
    }
  }

  Future<void> _persistStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsInferenceCountKey, _inferenceCount);
    await prefs.setString(_prefsLastInferenceKey, _lastInferenceResult);
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
