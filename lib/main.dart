import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/ocr_result.dart';
import 'screens/tier_selection.dart';
import 'services/ocr_config.dart';
import 'services/ocr_service.dart';
import 'services/phone_tier.dart';

void main() => runApp(const HelloScanApp());

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
  });
  final String id;
  XFile? front;
  XFile? back;
  String name, title, company, email, phone, website, address, notes;
  bool reviewed = false;
  bool ocrPending = true; // true until the user has reviewed OCR pre-fill

  static String? _opt(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  Map<String, dynamic> toJson() => {
    'person': {'name': _opt(name), 'designation': _opt(title)},
    'organization': {'name': _opt(company), 'website': _opt(website)},
    'contact': {
      'emails': email.isEmpty ? [] : [email.trim()],
      'phones': phone.isEmpty ? [] : [phone.trim()],
    },
    'location': {'full_address': _opt(address)},
    'notes': _opt(notes),
    'source': {
      'sides': [if (front != null) 'front', if (back != null) 'back'],
      'review_status': reviewed ? 'reviewed' : 'pending',
    },
  };

  /// Apply OCR-extracted fields to this card (review-first: user still edits).
  void applyOcr(Map<String, String> fields) {
    name = fields['name'] ?? name;
    title = fields['title'] ?? title;
    company = fields['company'] ?? company;
    email = fields['email'] ?? email;
    phone = fields['phone'] ?? phone;
    website = fields['website'] ?? website;
    address = fields['address'] ?? address;
    notes = fields['notes'] ?? notes;
    ocrPending = false;
  }
}

class HelloScanApp extends StatefulWidget {
  const HelloScanApp({super.key});

  @override
  State<HelloScanApp> createState() => _HelloScanAppState();
}

class _HelloScanAppState extends State<HelloScanApp> {
  bool _initialized = false;
  bool _ocrReady = false;
  Widget _home = const TierSelectionScreen();

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('helloscan.onboarded') ?? false;
    final tierName = prefs.getString('helloscan.selected_tier');

    if (onboarded && tierName != null) {
      // Models already downloaded; initialize OCR from stored files.
      await _initOcrFromStorage(tierName);
    }

    if (!mounted) return;
    setState(() {
      _initialized = true;
      _home = onboarded ? const BatchHome() : const TierSelectionScreen();
    });
  }

  Future<void> _initOcrFromStorage(String tierName) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final detPath = p.join(docs.path, 'helloscan', 'models', 'det_$tierName.tflite');
      final recPath = p.join(docs.path, 'helloscan', 'models', 'rec_$tierName.tflite');
      final labelsPath = p.join(docs.path, 'helloscan', 'models', 'labels.txt');

      if (await File(detPath).exists() &&
          await File(recPath).exists() &&
          await File(labelsPath).exists()) {
        // Map tier name back to input size config.
        final config = PhoneTierConfigs.all.firstWhere(
          (c) => c.tier.name == tierName,
          orElse: () => PhoneTierConfigs.all[1], // default to mid
        );

        final ok = await OcrService.instance.init(
          detModelPath: detPath,
          recModelPath: recPath,
          labelsPath: labelsPath,
          config: config.toOcrConfig(),
        );
        if (mounted) setState(() => _ocrReady = ok);
      }
    } catch (_) {
      // OCR will fall back to manual entry.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'HelloScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff111216),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xffa4f16b),
          secondary: Color(0xffa4f16b),
          surface: Color(0xff191a1e),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xff111216), elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff1c1d20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xff303137)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xff303137)),
          ),
        ),
      ),
      home: _home,
    );
  }
}

class BatchHome extends StatefulWidget {
  const BatchHome({super.key});
  @override
  State<BatchHome> createState() => _BatchHomeState();
}

class _BatchHomeState extends State<BatchHome> {
  final picker = ImagePicker();
  final cards = <ScanCard>[];
  ScanCard? selected;
  int counter = 0;
  final ocr = OcrService.instance;
  bool ocrReady = false;
  bool ocrRunning = false;

  @override
  void initState() {
    super.initState();
    // OCR is already initialized by HelloScanApp on returning users.
    _ocrReady = true;
  }

  Future<void> captureFront() async {
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (image == null) return;
    final card = ScanCard(id: 'card-${++counter}', front: image);
    setState(() {
      cards.insert(0, card);
      selected = card;
    });
    _runOcrPipeline(card, image.path);
  }

  Future<void> captureBack() async {
    if (selected == null) {
      _snack('Select a card first, then capture its back.');
      return;
    }
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (image != null) {
      setState(() => selected!.back = XFile(image.path));
      _runOcrPipeline(selected!, image.path, backPath: image.path);
    }
  }

  Future<void> importGallery() async {
    final images = await picker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return;
    final newCards = <ScanCard>[];
    setState(() {
      for (final image in images) {
        final card = ScanCard(id: 'card-${++counter}', front: XFile(image.path));
        cards.insert(0, card);
        newCards.add(card);
      }
      selected = cards.first;
    });
    for (final card in newCards) {
      if (card.front != null) _runOcrPipeline(card, card.front!.path);
    }
    if (mounted) _snack('Imported ${newCards.length} card(s) — review OCR pre-fill.');
  }

  void addEmpty() {
    final card = ScanCard(id: 'card-${++counter}');
    setState(() {
      cards.insert(0, card);
      selected = card;
    });
  }

  /// Run detection + recognition pipeline on a card image.
  ///
  /// If [backPath] is provided, both sides are processed and fields merged.
  /// Pre-fills only empty fields so manual edits are never clobbered.
  Future<void> _runOcrPipeline(
    ScanCard card,
    String frontPath, {
    String? backPath,
  }) async {
    if (!ocrReady) {
      if (mounted) _snack('OCR model not loaded yet — edit fields manually.');
      return;
    }

    setState(() => ocrRunning = true);

    try {
      final result = await ocr.recognizeCard(
        front: File(frontPath),
        back: backPath != null ? File(backPath) : null,
      );

      if (!mounted) return;

      // Only auto-fill if the card still has empty fields.
      if (card.name.isEmpty &&
          card.title.isEmpty &&
          card.company.isEmpty &&
          card.email.isEmpty &&
          card.phone.isEmpty &&
          card.website.isEmpty &&
          card.address.isEmpty) {
        card.applyOcr(result.mergedFields);
      }

      setState(() => ocrRunning = false);

      if (result.isEmpty) {
        _snack('OCR found no text — edit fields manually.');
      } else {
        final sides = result.back == null ? 'front' : 'front + back';
        _snack(
          'OCR complete ($sides, ${result.totalProcessingTimeMs}ms) — review fields, then mark reviewed.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => ocrRunning = false);
        _snack('OCR failed — edit fields manually.');
      }
    }
  }

  Future<void> exportBatch() async {
    final payload = {
      'schema': 'helloscan.contact-batch.v1',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'total': cards.length,
      'contacts': cards.map((c) => c.toJson()).toList(),
    };
    final file = await FilePicker.platform.saveFile(
      fileName: 'helloscan-batch.json',
      bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file != null) _snack('JSON exported successfully');
  }

  Future<void> clearBatch() async {
    if (cards.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear entire batch?'),
        content: const Text(
          'This removes all staged cards and cannot be undone. '
          'Images are not exported unless you save the JSON first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        cards.clear();
        selected = null;
      });
      _snack('Batch cleared');
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Manually trigger OCR on the selected card (front + back if both scanned).
  Future<void> _ocrSelected() async {
    if (selected == null || selected!.front == null) return;

    setState(() => ocrRunning = true);
    try {
      final result = await ocr.recognizeCard(
        front: File(selected!.front!.path),
        back: selected!.back != null ? File(selected!.back!.path) : null,
      );
      if (!mounted) return;
      setState(() => ocrRunning = false);
      setState(() => selected!.applyOcr(result.mergedFields));
      _snack('OCR pre-fill applied — review the fields.');
    } catch (_) {
      if (mounted) {
        setState(() => ocrRunning = false);
        _snack('OCR failed — edit fields manually.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HelloScan', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (ocrReady)
            IconButton(
              onPressed: (cards.isEmpty || ocrRunning) ? null : _ocrSelected,
              icon: const Icon(Icons.text_fields_outlined),
              tooltip: 'Auto-fill selected card from OCR',
            ),
          IconButton(
            onPressed: cards.isEmpty ? null : exportBatch,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export JSON',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CARD CAPTURE WORKSPACE',
                          style: TextStyle(
                            color: Color(0xffa4f16b),
                            letterSpacing: 1.3,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('From card to CRM-ready data.',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text('${cards.length} cards in this batch',
                            style: const TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: ocrRunning ? null : captureFront,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan card'),
                  ),
                  OutlinedButton.icon(
                    onPressed: ocrRunning ? null : captureBack,
                    icon: const Icon(Icons.flip_outlined),
                    label: const Text('Scan back'),
                  ),
                  OutlinedButton.icon(
                    onPressed: ocrRunning ? null : importGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                  OutlinedButton.icon(
                    onPressed: addEmpty,
                    icon: const Icon(Icons.add),
                    label: const Text('Manual'),
                  ),
                ],
              ),
            ),
            if (ocrRunning)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Running OCR...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: cards.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.contact_page_outlined,
                              size: 44, color: Colors.white30),
                          const SizedBox(height: 12),
                          const Text('Your batch is empty', style: TextStyle(fontSize: 17)),
                          const SizedBox(height: 5),
                          const Text('Scan or import visiting cards to start.',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: ListView.builder(
                            itemCount: cards.length,
                            itemBuilder: (_, i) {
                              final card = cards[i];
                              return ListTile(
                                dense: true,
                                selected: card == selected,
                                selectedTileColor: const Color(0xff27292d),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xff303137),
                                  child: Text(
                                    (card.name.isEmpty ? '?' : card.name[0]).toUpperCase(),
                                  ),
                                ),
                                title: Text(
                                  card.name.isEmpty ? 'Untitled' : card.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  card.company.isEmpty ? 'No company' : card.company,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                onTap: () => setState(() => selected = card),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: selected == null ? const SizedBox.shrink() : _editor(selected!),
                        ),
                      ],
                    ),
            ),
            if (cards.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Text('${cards.length} staged',
                        style: const TextStyle(color: Colors.white54)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: exportBatch,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Export batch JSON'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: clearBatch,
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                      label: const Text('Clear batch',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _editor(ScanCard card) {
    Widget field(String label, String value, ValueChanged<String> onChanged,
        {String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            initialValue: value,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
            ),
            onChanged: onChanged,
          ),
        );
    Widget imageTile(XFile? image, String side, VoidCallback onTap) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 110,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: image == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: Colors.white38),
                          Text(side, style: const TextStyle(color: Colors.white38, fontSize: 11)),
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

    final ocrHint = card.ocrPending ? 'OCR pre-fill • review me' : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            imageTile(card.front, 'Front', () async {
              final x = await picker.pickImage(source: ImageSource.camera);
              if (x != null) {
                setState(() => card.front = x);
                _runOcrPipeline(card, x.path,
                    backPath: card.back?.path);
              }
            }),
            imageTile(card.back, 'Back', () async {
              final x = await picker.pickImage(source: ImageSource.camera);
              if (x != null) {
                setState(() => card.back = x);
                _runOcrPipeline(card, card.front?.path ?? '', backPath: x.path);
              }
            }),
          ],
        ),
        const SizedBox(height: 14),
        field('Full name', card.name, (v) => setState(() => card.name = v),
            hint: ocrHint),
        field('Designation', card.title, (v) => setState(() => card.title = v),
            hint: ocrHint),
        field('Company', card.company, (v) => setState(() => card.company = v),
            hint: ocrHint),
        field('Email', card.email, (v) => setState(() => card.email = v),
            hint: ocrHint),
        field('Phone', card.phone, (v) => setState(() => card.phone = v),
            hint: ocrHint),
        field('Website', card.website, (v) => setState(() => card.website = v),
            hint: ocrHint),
        field('Address', card.address, (v) => setState(() => card.address = v),
            hint: ocrHint),
        field('Notes', card.notes, (v) => setState(() => card.notes = v),
            hint: ocrHint),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => setState(() => card.reviewed = true),
                child: Text(card.reviewed ? 'Reviewed ✓' : 'Mark reviewed'),
              ),
            ),
            const SizedBox(width: 8),
            if (card.ocrPending && card.front != null)
              OutlinedButton.icon(
                onPressed: ocrRunning ? null : () => _ocrSelected(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Re-OCR', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() {
            cards.remove(card);
            selected = cards.isEmpty ? null : cards.first;
          }),
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          label: const Text('Remove card', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }
}
