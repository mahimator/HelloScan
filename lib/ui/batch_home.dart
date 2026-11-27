import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ocr_document.dart';
import '../models/parsed_card.dart';
import '../models/scan_card.dart';
import '../services/batch_export.dart';
import '../services/card_parser.dart';
import '../services/semantic_card_refiner.dart';
import '../services/mlkit_ocr_service.dart';
import '../services/ocr_service.dart';

const _kPrimary = Color(0xFF1A73E8);
const _kPrimaryContainer = Color(0xFFE8F0FE);
const _kSurface = Color(0xFFFFFFFF);
const _kSurfaceVariant = Color(0xFFF1F3F4);
const _kBackground = Color(0xFFF8F9FA);
const _kOnSurface = Color(0xFF202124);
const _kOnSurfaceVariant = Color(0xFF5F6368);
const _kDivider = Color(0xFFE0E0E0);

enum _ScanMode { single, bulk }

class BatchHome extends StatefulWidget {
  const BatchHome({super.key, this.ocrService});

  final OcrService? ocrService;

  @override
  State<BatchHome> createState() => _BatchHomeState();
}

class _BatchHomeState extends State<BatchHome> {
  final ImagePicker _picker = ImagePicker();
  final List<ScanCard> _cards = <ScanCard>[];
  ScanCard? _selected;
  int _counter = 0;

  OcrService? _ocr;
  bool _ownsOcr = false;

  OcrService get _ocrService {
    if (_ocr == null) {
      _ocr = widget.ocrService ?? MlKitOcrService();
      _ownsOcr = widget.ocrService == null;
    }
    return _ocr!;
  }

  _ScanMode _mode = _ScanMode.single;

  /// When true, skips image enhancement for faster (lower-quality) OCR.
  bool _fastScan = false;

  /// Lock so only one OCR extraction runs at a time. Prevents the batch from
  /// being corrupted when the user taps capture back-to-back while a previous
  /// card is still being read.
  bool _isExtracting = false;

  /// Cards captured in bulk mode that are waiting to be processed.
  bool _bulkProcessing = false;
  int _bulkProcessed = 0;

  /// Whether the Neural Semantic Engine is enabled.
  /// Disabled by default — deterministic rule-based parser is the source of truth.
  bool _neuralEngineEnabled = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await SemanticCardRefiner.instance.loadPrefs();
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('helloscan.onboarded') ?? false;

    setState(() {
      _neuralEngineEnabled = SemanticCardRefiner.instance.isEnabled;
    });

    // Pre-warm the ML Kit model on startup so the first scan doesn't freeze
    // for ~30s while the recognition model downloads.
    _ocrService.prewarm().catchError((_) {});

    // Do not preload the native LLM beside ML Kit. It loads on demand after
    // OCR, or when the user explicitly taps Download in engine settings.
    // Show onboarding on first launch.
    if (!onboarded && mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _showOnboarding();
    }
  }

  @override
  void dispose() {
    if (_ownsOcr) _ocr?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Mode switching
  // ---------------------------------------------------------------------------

  void _setMode(_ScanMode mode) {
    setState(() {
      _mode = mode;
    });
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  Future<void> captureFront() async {
    // In single mode, don't allow a new capture while OCR is running.
    if (_mode == _ScanMode.single && _isExtracting) {
      _snack('Still reading the previous card. Please wait.');
      return;
    }

    // Ask whether this is a one-sided or two-sided card before capturing.
    final isTwoSided = await _showCardTypeDialog();
    if (!mounted) return;

    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (image == null || !mounted) return;

    final card = ScanCard(
      id: 'card-${++_counter}',
      front: image,
      isTwoSided: isTwoSided,
      fastScan: _fastScan,
    );
    setState(() {
      _cards.insert(0, card);
      _selected = card;
    });

    if (_mode == _ScanMode.bulk) {
      // Bulk mode: just queue the card, no OCR yet.
      _snack('Card queued. Tap "Process all" when ready.');
    } else if (isTwoSided) {
      // Two-sided: capture front only now, OCR both sides after back is scanned.
      _snack('Front captured. Now scan the back.');
    } else {
      // One-sided: OCR immediately.
      await _extract(card);
    }
  }

  Future<void> captureBack() async {
    if (_selected == null) {
      _snack('Select a card first, then scan its back.');
      return;
    }
    if (_isExtracting) {
      _snack('Still reading the previous card. Please wait.');
      return;
    }

    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (image == null || !mounted) return;

    setState(() => _selected!.back = image);

    if (_mode == _ScanMode.bulk) {
      _snack('Back scanned. Tap "Process all" when ready.');
    } else {
      await _extract(_selected!);
    }
  }

  /// Asks the user whether the card is one-sided or two-sided before capture.
  Future<bool> _showCardTypeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text('Card type'),
        content: const Text(
          'Is this card single-sided or double-sided?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('One-sided'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Two-sided'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _captureInto(ScanCard card, {required bool front}) async {
    if (_isExtracting) {
      _snack('Still reading the previous card. Please wait.');
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (image == null || !mounted) return;
    setState(() {
      if (front) {
        card.front = image;
      } else {
        card.back = image;
      }
    });
    if (_mode == _ScanMode.bulk) {
      _snack('Card updated. Tap "Process all" when ready.');
    } else {
      await _extract(card);
    }
  }

  Future<void> importGallery() async {
    if (_isExtracting && _mode == _ScanMode.single) {
      _snack('Still reading the previous card. Please wait.');
      return;
    }
    final images = await _picker.pickMultiImage(
      imageQuality: 90,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (images.isEmpty || !mounted) return;

    if (_mode == _ScanMode.bulk) {
      for (final image in images) {
        final card = ScanCard(
          id: 'card-${++_counter}',
          front: image,
          fastScan: _fastScan,
        );
        setState(() {
          _cards.insert(0, card);
          _selected = card;
        });
      }
      _snack('${images.length} cards queued.');
      return;
    }

    // Single mode: import each image as a card front, offer back-side import
    // for two-sided cards.
    for (final image in images) {
      if (!mounted) break;
      final card = ScanCard(
        id: 'card-${++_counter}',
        front: image,
        fastScan: _fastScan,
      );
      setState(() {
        _cards.insert(0, card);
        _selected = card;
      });

      final isTwoSided = await _showCardTypeDialog();
      if (!mounted) break;
      if (isTwoSided) {
        await _importBackInto(card);
      } else {
        await _extract(card);
      }
    }
  }

  /// Imports the back side of a card from the gallery.
  Future<void> _importBackInto(ScanCard card) async {
    if (_isExtracting) {
      _snack('Still reading the previous card. Please wait.');
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (image == null || !mounted) return;
    setState(() {
      card.back = image;
    });
    await _extract(card);
  }

  /// Imports the back side of the currently selected card from the gallery.
  Future<void> importSelectedBack() async {
    if (_selected == null) {
      _snack('Select a card first, then import its back.');
      return;
    }
    await _importBackInto(_selected!);
  }

  // ---------------------------------------------------------------------------
  // Neural Semantic Engine management
  // ---------------------------------------------------------------------------

  Future<void> _showNeuralEngineDialog() async {
    final refiner = SemanticCardRefiner.instance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('helloscan.onboarded', true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          title: const Text(
            'Neural Semantic Engine',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The Neural Semantic Engine disambiguates person names from '
                  'company names on noisy business cards. It runs entirely '
                  'on-device and never sends your card data anywhere.',
                  style: TextStyle(fontSize: 13, color: _kOnSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: refiner.isLoaded
                            ? const Color(0xFFE8F0FE)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: refiner.isLoaded
                              ? _kPrimary
                              : const Color(0xFFDADCE0),
                        ),
                      ),
                      child: Text(
                        refiner.isLoaded ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: refiner.isLoaded
                              ? _kPrimary
                              : _kOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: refiner.isLoaded
                            ? const Color(0xFFE8F0FE)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: refiner.isLoaded
                              ? _kPrimary
                              : const Color(0xFFDADCE0),
                        ),
                      ),
                      child: Text(
                        refiner.isLoaded ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: refiner.isLoaded
                              ? _kPrimary
                              : _kOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (refiner.isLoaded) ...[
                  Row(
                    children: [
                      const Text(
                        'Inferences: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${refiner.inferenceCount}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _kOnSurface,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Last result: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        refiner.lastInferenceResult.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: refiner.lastInferenceResult == 'ran'
                              ? Colors.green
                              : refiner.lastInferenceResult == 'low_confidence'
                                  ? Colors.orange
                                  : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Enable Neural Semantic Layer'),
                  subtitle: const Text(
                    'When on, ambiguous names/companies are resolved using '
                    'on-device AI. The model loads only when needed.',
                  ),
                  value: refiner.isEnabled,
                  onChanged: (value) async {
                    await refiner.setEnabled(value);
                    setDialogState(() {
                      _neuralEngineEnabled = value;
                    });
                    setState(() {});
                  },
                  activeThumbColor: _kPrimary,
                ),
                const SizedBox(height: 8),
                if (!refiner.isLoaded && refiner.isEnabled) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_download, size: 18),
                      label: const Text('Download Neural Engine'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _downloadNeuralEngine();
                      },
                    ),
                  ),
                ],
                if (refiner.isLoaded && refiner.isEnabled) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reinitialize Neural Engine'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await refiner.preloadModel().catchError((_) {});
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadNeuralEngine() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: Text('Downloading Neural Engine…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Fetching the on-device inference engine. This happens once.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5F6368)),
            ),
          ],
        ),
      ),
    );
    try {
      await SemanticCardRefiner.instance.preloadModel();
      if (mounted) {
        Navigator.pop(context);
        _snack('Neural Semantic Engine is now online.');
        setState(() {});
      }
    } catch (e) {
      debugPrint('HelloScan: Neural engine download failed: $e');
      if (mounted) {
        Navigator.pop(context);
        _snack(
          'Neural Engine download failed: $e. Card parsing still works.',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // First-run onboarding
  // ---------------------------------------------------------------------------

  Future<void> _showOnboarding() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: const Text(
          'Welcome to HelloScan',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Turn visiting cards into CRM-ready contacts in three steps:',
                style: TextStyle(fontSize: 14, color: Color(0xFF5F6368)),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Text('1', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A73E8))),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scan or import card fronts (and backs for two-sided cards).',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Text('2', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A73E8))),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Review each card — the Neural Semantic Engine helps separate names from companies.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Text('3', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A73E8))),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Export the batch as CRM-ready JSON.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Text(
                'Tap the Neural Semantic Engine icon in the top bar to download '
                'and manage the on-device AI layer.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF5F6368),
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('helloscan.onboarded', true);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Get started'),
            ),
          ),
        ],
      ),
    );
  }

  void addEmpty() {
    final card = ScanCard(id: 'card-${++_counter}', fastScan: _fastScan);
    setState(() {
      _cards.insert(0, card);
      _selected = card;
    });
  }

  // ---------------------------------------------------------------------------
  // Bulk processing
  // ---------------------------------------------------------------------------

  Future<void> processBulk() async {
    final pending = _cards.where((c) => c.front != null || c.back != null).toList();
    if (pending.isEmpty) {
      _snack('No cards to process.');
      return;
    }

    // Only process cards that haven't been OCR'd yet.
    final unprocessed = pending.where((c) => c.detectedFields == 0).toList();
    if (unprocessed.isEmpty) {
      _snack('All cards already processed.');
      return;
    }

    setState(() {
      _bulkProcessing = true;
      _bulkProcessed = 0;
    });

    var success = 0;
    var failed = 0;

    for (final card in unprocessed) {
      if (!mounted) break;
      try {
        final documents = <OcrDocument>[];
        if (card.front != null) {
          documents.add(await _ocrService.recognizeDocument(
            File(card.front!.path),
            fast: card.fastScan,
          ));
        }
        if (card.back != null) {
          documents.add(await _ocrService.recognizeDocument(
            File(card.back!.path),
            fast: card.fastScan,
          ));
        }

        final parsed = await SemanticCardRefiner.instance.refine(
          const CardParser().parseManyDocuments(documents),
        );
        if (!mounted) break;

        setState(() {
          _applyParsed(card, parsed);
          card.extracting = false;
          card.detectedFields = parsed.detectedCount;
          card.ocrFailed = parsed.isEmpty;
          _bulkProcessed++;
        });

        if (parsed.isEmpty) failed++;
        if (!parsed.isEmpty) success++;
      } catch (_) {
        if (!mounted) break;
        setState(() {
          card.extracting = false;
          card.ocrFailed = true;
          _bulkProcessed++;
          failed++;
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _bulkProcessing = false;
    });
    _snack('Processed: $success succeeded, $failed failed.');
  }

  // ---------------------------------------------------------------------------
  // Extraction (single mode)
  // ---------------------------------------------------------------------------

  Future<void> _extract(ScanCard card) async {
    if (card.front == null && card.back == null) return;
    if (_isExtracting) return; // guard against double entry

    setState(() {
      _isExtracting = true;
      card.extracting = true;
      card.ocrFailed = null;
    });

    try {
      final documents = <OcrDocument>[];
      if (card.front != null) {
        documents.add(await _ocrService.recognizeDocument(
          File(card.front!.path),
          fast: card.fastScan,
        ));
      }
      if (card.back != null) {
        documents.add(await _ocrService.recognizeDocument(
          File(card.back!.path),
          fast: card.fastScan,
        ));
      }

      final parsed = await SemanticCardRefiner.instance.refine(
        const CardParser().parseManyDocuments(documents),
      );
      if (!mounted) return;

      setState(() {
        _applyParsed(card, parsed);
        card.extracting = false;
        card.detectedFields = parsed.detectedCount;
        card.ocrFailed = parsed.isEmpty;
        _isExtracting = false;
      });

      if (parsed.isEmpty) {
        _snack(
          'No text detected. Try better lighting or enter details manually.',
        );
      }
    } catch (e, stack) {
      debugPrint('HelloScan extraction error: $e\n$stack');
      if (!mounted) return;
      setState(() {
        card.extracting = false;
        card.ocrFailed = true;
        _isExtracting = false;
      });
      _snack('Could not read this card. You can enter details manually.');
    }
  }

  void _applyParsed(ScanCard card, ParsedCard parsed) {
    var changed = false;

    void apply(String field, String value, void Function(String) assign) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (card.editedFields.contains(field)) return;
      assign(trimmed);
      changed = true;
    }

    apply('name', parsed.name, (value) => card.name = value);
    apply('title', parsed.designation, (value) => card.title = value);
    apply('company', parsed.company, (value) => card.company = value);
    apply('email', parsed.email, (value) => card.email = value);
    apply('phone', parsed.phone, (value) => card.phone = value);
    if (!card.editedFields.contains('email') && parsed.emails.isNotEmpty) {
      card.emails = List<String>.from(parsed.emails);
    }
    if (!card.editedFields.contains('phone') && parsed.phones.isNotEmpty) {
      card.phones = List<String>.from(parsed.phones);
    }
    apply('website', parsed.website, (value) => card.website = value);
    apply('address', parsed.address, (value) => card.address = value);

    if (changed) card.revision++;
  }

  // ---------------------------------------------------------------------------
  // Paste-text fallback
  // ---------------------------------------------------------------------------

  Future<void> pasteText() async {
    if (_isExtracting) {
      _snack('Still reading the previous card. Please wait.');
      return;
    }
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text('Paste card text'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const Key('paste-text-input'),
            controller: controller,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Paste raw text read from a visiting card...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('paste-extract-button'),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Extract'),
          ),
        ],
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;

    final parsed = await SemanticCardRefiner.instance.refine(
      const CardParser().parse(text),
    );
    final card = ScanCard(
      id: 'card-${++_counter}',
      fastScan: _fastScan,
    );
    _applyParsed(card, parsed);
    card.detectedFields = parsed.detectedCount;
    card.ocrFailed = parsed.isEmpty;

    setState(() {
      _cards.insert(0, card);
      _selected = card;
    });

    if (parsed.isEmpty) {
      _snack('No contact details detected. You can edit the fields manually.');
    }
  }

  // ---------------------------------------------------------------------------
  // Export / clear
  // ---------------------------------------------------------------------------

  Future<void> exportBatch() async {
    if (_cards.isEmpty) return;
    try {
      final json = const BatchExport().encode(_cards);
      final uri = await FilePicker.saveFile(
        fileName: 'helloscan-batch.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      if (uri != null && mounted) _snack('JSON exported successfully');
    } catch (_) {
      if (mounted) _snack('Could not export the batch.');
    }
  }

  Future<void> clearBatch() async {
    if (_cards.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text('Clear entire batch?'),
        content: const Text(
          'This will remove all staged cards. Images are not embedded in '
          'exports and cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _cards.clear();
        _selected = null;
      });
      _snack('Batch cleared');
    }
  }

  void _removeCard(ScanCard card) {
    setState(() {
      _cards.remove(card);
      if (_selected == card) {
        _selected = _cards.isEmpty ? null : _cards.first;
      }
    });
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pendingCount = _cards.where(
      (c) => (c.front != null || c.back != null) && c.detectedFields == 0,
    ).length;

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text(
          'HelloScan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          // Mode toggle: Single / Bulk
          PopupMenuButton<_ScanMode>(
            initialValue: _mode,
            icon: const Icon(Icons.view_list_rounded),
            tooltip: 'Scan mode',
            onSelected: _setMode,
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: _ScanMode.single,
                child: Text('Single scan (review each card)'),
              ),
              const PopupMenuItem(
                value: _ScanMode.bulk,
                child: Text('Bulk scan (capture all, then process)'),
              ),
            ],
          ),
          // Fast scan toggle: skips image enhancement for speed.
          Switch(
            value: _fastScan,
            onChanged: (value) => setState(() => _fastScan = value),
            activeThumbColor: _kPrimary,
            activeTrackColor: _kPrimaryContainer,
          ),
          const SizedBox(width: 8),
          // Neural Semantic Engine status + management.
          Tooltip(
            message: 'Neural Semantic Engine — manage AI disambiguation layer',
            child: IconButton(
              icon: Icon(
                _neuralEngineEnabled
                    ? (SemanticCardRefiner.instance.isLoaded
                        ? Icons.auto_awesome
                        : Icons.auto_awesome_outlined)
                    : Icons.auto_awesome_outlined,
                color: SemanticCardRefiner.instance.isLoaded
                    ? _kPrimary
                    : _kOnSurfaceVariant,
              ),
              onPressed: _showNeuralEngineDialog,
              tooltip: 'Neural Semantic Engine',
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _cards.isEmpty ? null : exportBatch,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export JSON',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header strip — full width
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: _kPrimary,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CARD CAPTURE WORKSPACE',
                            style: TextStyle(
                              color: _kPrimary,
                              letterSpacing: 1.1,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'From card to CRM-ready data.',
                            style: TextStyle(
                              color: _kOnSurface,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${_cards.length} cards in this batch',
                      style: const TextStyle(
                        color: _kOnSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kPrimaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$pendingCount pending',
                          style: const TextStyle(
                            color: _kPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kDivider),

          // Action row — full width tile strip
          Expanded(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: _kSurface,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _actionTile(
                        icon: Icons.camera_alt_outlined,
                        label: 'Scan card',
                        color: _kPrimary,
                        onPressed: _isExtracting ? null : captureFront,
                      ),
                      _actionTile(
                        icon: Icons.flip_outlined,
                        label: 'Scan back',
                        color: _kOnSurfaceVariant,
                        onPressed:
                            _selected == null || _isExtracting ? null : captureBack,
                      ),
                      _actionTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Import back',
                        color: _kOnSurfaceVariant,
                        onPressed:
                            _selected == null || _isExtracting ? null : importSelectedBack,
                      ),
                      _actionTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        color: _kOnSurfaceVariant,
                        onPressed: _isExtracting ? null : importGallery,
                      ),
                      _actionTile(
                        icon: Icons.add_outlined,
                        label: 'Manual',
                        color: _kOnSurfaceVariant,
                        onPressed: _isExtracting ? null : addEmpty,
                      ),
                      _actionTile(
                        icon: Icons.content_paste_go_outlined,
                        label: 'Paste text',
                        color: _kOnSurfaceVariant,
                        onPressed: _isExtracting ? null : pasteText,
                      ),
                    ],
                  ),
                ),

                // Bulk-mode only: Process all button
                if (_mode == _ScanMode.bulk && _cards.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: _kSurfaceVariant,
                    child: _bulkProcessing
                        ? _bulkProgressBar()
                        : SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isExtracting ? null : processBulk,
                              child: const Text(
                                'Process all queued cards',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                  ),
                const Divider(height: 1, color: _kDivider),

                // Card list + editor — full width split
                Expanded(
                  child: _cards.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.contact_page_outlined,
                                size: 48,
                                color: Color(0xFFBDC3C7),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Your batch is empty',
                                style: TextStyle(
                                  color: _kOnSurface,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Scan or import visiting cards to start.',
                                style: TextStyle(
                                  color: _kOnSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            // Left rail: card list
                            SizedBox(
                              width: 170,
                              child: ListView.builder(
                                itemCount: _cards.length,
                                itemBuilder: (_, index) {
                                  final card = _cards[index];
                                  return _cardListTile(card);
                                },
                              ),
                            ),
                            Container(width: 1, color: _kDivider),
                            // Right panel: editor
                            Expanded(
                              child: _selected == null
                                  ? const Center(
                                      child: Text(
                                        'Select a card to review',
                                        style: TextStyle(
                                          color: _kOnSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  : _editor(_selected!),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (_cards.isNotEmpty)
            Container(
              width: double.infinity,
              color: _kSurface,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text(
                    '${_cards.length} staged',
                    style: const TextStyle(
                      color: _kOnSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: clearBatch,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'Clear batch',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: exportBatch,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export batch JSON'),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isExtracting ? null : captureFront,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  Widget _bulkProgressBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(minHeight: 4),
        const SizedBox(height: 6),
        Text(
          'Processing $_bulkProcessed card${_bulkProcessed == 1 ? '' : 's'}…',
          style: const TextStyle(
            color: _kOnSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: onPressed == null
            ? const Color(0xFFE0E0E0)
            : color,
        foregroundColor: onPressed == null
            ? const Color(0xFF9AA0A6)
            : Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(110, 48),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _cardListTile(ScanCard card) {
    final isSelected = card == _selected;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: _kPrimaryContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: isSelected ? _kPrimary : const Color(0xFFDADCE0),
        child: Text(
          (card.name.isEmpty ? '?' : card.name[0]).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        card.name.isEmpty ? 'Untitled' : card.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _kOnSurface,
        ),
      ),
      subtitle: Text(
        card.company.isEmpty ? 'No company' : card.company,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          color: _kOnSurfaceVariant,
        ),
      ),
      onTap: _isExtracting ? null : () => setState(() => _selected = card),
      trailing: card.ocrFailed == true
          ? const Icon(Icons.error_outline, size: 18, color: Colors.red)
          : card.extracting || _bulkProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
    );
  }

  Widget _editor(ScanCard card) {
    Widget imageTile(XFile? image, String side, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: _isExtracting ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 120,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _kSurfaceVariant,
              border: Border.all(color: _kDivider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: image == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Color(0xFF9AA0A6),
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          side,
                          style: const TextStyle(
                            color: Color(0xFF9AA0A6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.file(File(image.path), fit: BoxFit.cover),
                  ),
          ),
        ),
      );
    }

    Widget field(
      String keyName,
      String label,
      String value,
      void Function(String) onChanged,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _kOnSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('${card.id}-${card.revision}-$keyName'),
              initialValue: value,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            imageTile(card.front, 'Front', () => _captureInto(card, front: true)),
            imageTile(card.back, 'Back', () => _captureInto(card, front: false)),
          ],
        ),
        const SizedBox(height: 12),
        _extractionBanner(card),
        if (card.extracting || _bulkProcessing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        const SizedBox(height: 4),
        field('name', 'Full name', card.name, (value) {
          card.name = value;
          card.editedFields.add('name');
        }),
        field('title', 'Designation', card.title, (value) {
          card.title = value;
          card.editedFields.add('title');
        }),
        field('company', 'Company', card.company, (value) {
          card.company = value;
          card.editedFields.add('company');
        }),
        field('email', 'Emails (comma separated)', card.emails.isEmpty ? card.email : card.emails.join(', '), (value) {
          final values = value.split(RegExp(r'[,;]')).map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
          card.emails = values;
          card.email = values.isEmpty ? '' : values.first;
          card.editedFields.add('email');
        }),
        field('phone', 'Phone numbers (comma separated)', card.phones.isEmpty ? card.phone : card.phones.join(', '), (value) {
          final values = value.split(RegExp(r'[,;]')).map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
          card.phones = values;
          card.phone = values.isEmpty ? '' : values.first;
          card.editedFields.add('phone');
        }),
        field('website', 'Website', card.website, (value) {
          card.website = value;
          card.editedFields.add('website');
        }),
        field('address', 'Address', card.address, (value) {
          card.address = value;
          card.editedFields.add('address');
        }),
        field('notes', 'Notes', card.notes, (value) {
          card.notes = value;
          card.editedFields.add('notes');
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => setState(() => card.reviewed = true),
                style: FilledButton.styleFrom(
                  backgroundColor: card.reviewed
                      ? Colors.green
                      : _kSurfaceVariant,
                  foregroundColor: card.reviewed
                      ? Colors.white
                      : _kOnSurfaceVariant,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(card.reviewed ? 'Reviewed ✓' : 'Mark reviewed'),
              ),
            ),
            if ((card.front != null || card.back != null) && !_isExtracting)
              ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _extract(card),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Re-read'),
                ),
              ],
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _isExtracting ? null : () => _removeCard(card),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text(
            'Remove card',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _extractionBanner(ScanCard card) {
    if (_bulkProcessing) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Processing batch…',
              style: TextStyle(color: _kOnSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (card.extracting) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Reading card…',
              style: TextStyle(color: _kOnSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (card.ocrFailed == true) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'No text detected. Improve lighting or enter details manually.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (card.detectedFields > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 16,
              color: _kPrimary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Auto-filled ${card.detectedFields} '
                'field${card.detectedFields == 1 ? '' : 's'}. '
                'Review before export.',
                style: const TextStyle(
                  color: _kOnSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
