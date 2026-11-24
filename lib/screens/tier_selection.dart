import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/phone_tier.dart';
import '../services/model_downloader.dart';
import '../services/ocr_config.dart';
import '../services/ocr_service.dart';

/// Copies the bundled labels.txt into the app documents directory so OCR can
/// read it from storage (not assets).
Future<String> _ensureLabelsFile() async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'helloscan', 'models'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final labelsPath = p.join(dir.path, 'labels.txt');
  final file = File(labelsPath);
  if (!await file.exists()) {
    final byteData = await rootBundle.load('assets/models/labels.txt');
    await file.writeAsBytes(byteData.buffer.asUint8List());
  }
  return labelsPath;
}

/// Onboarding screen: user picks their phone tier, models download from
/// Hugging Face, then OCR is initialized and the main app opens.
class TierSelectionScreen extends StatefulWidget {
  const TierSelectionScreen({super.key});

  @override
  State<TierSelectionScreen> createState() => _TierSelectionScreenState();
}

class _TierSelectionScreenState extends State<TierSelectionScreen> {
  PhoneTierConfig? _selected;
  bool _downloading = false;
  double _progress = 0.0;
  String _status = '';
  String? _error;

  Future<void> _selectAndDownload(PhoneTierConfig config) async {
    setState(() {
      _selected = config;
      _downloading = true;
      _progress = 0.0;
      _status = 'Preparing download…';
      _error = null;
    });

    try {
      // Copy labels.txt from assets to app storage.
      setState(() => _status = 'Preparing labels…');
      final labelsPath = await _ensureLabelsFile();

      // Download detection + recognition models from Hugging Face.
      await ModelDownloader.instance.downloadTierModels(
        config: config,
        onProgress: (message, progress) {
          if (!mounted) return;
          setState(() {
            _status = message;
            _progress = progress;
          });
        },
      );

      // Initialize OCR with the downloaded models.
      final detPath = await ModelDownloader.instance
          .modelPath('det_${config.tier.name}.tflite');
      final recPath = await ModelDownloader.instance
          .modelPath('rec_${config.tier.name}.tflite');
      final labelsPath = await ModelDownloader.instance
          .modelPath('labels.txt');

      final ok = await OcrService.instance.init(
        detModelPath: detPath,
        recModelPath: recPath,
        labelsPath: labelsPath,
        config: config.toOcrConfig(),
      );

      if (!mounted) return;
      if (!ok) {
        setState(() {
          _downloading = false;
          _error = 'Failed to initialize OCR models.';
        });
        return;
      }

      // Mark onboarding complete and navigate to main app.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('helloscan.onboarded', true);
      await prefs.setString('helloscan.selected_tier', config.tier.name);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString();
      });
    }
  }
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff111216),
      body: SafeArea(
        child: _downloading ? _buildDownloadingUI() : _buildTierList(),
      ),
    );
  }

  Widget _buildTierList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Choose your phone tier',
            style: TextStyle(
              color: Color(0xffa4f16b),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'This selects the OCR model size for your device. '
            'Models are downloaded from Hugging Face on first launch.',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.builder(
            itemCount: PhoneTierConfigs.all.length,
            itemBuilder: (_, i) {
              final config = PhoneTierConfigs.all[i];
              return Card(
                color: const Color(0xff191a1e),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        _selected == config
                            ? const Color(0xffa4f16b)
                            : const Color(0xff303137),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color:
                            _selected == config
                                ? const Color(0xff111216)
                                : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    config.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    config.referenceSpecs,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: Radio<PhoneTierConfig>(
                    value: config,
                    groupValue: _selected,
                    activeColor: const Color(0xffa4f16b),
                    onChanged: (c) => setState(() => _selected = c),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _selected == null ? null : () => _selectAndDownload(_selected!),
            child: const Text('Continue & Download Models'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_download, size: 64, color: Color(0xffa4f16b)),
        const SizedBox(height: 20),
        Text(
          _selected?.label ?? 'Downloading models…',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _status,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: const Color(0xff303137),
              valueColor: const AlwaysStoppedAnimation(Color(0xffa4f16b)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${(_progress * 100).toInt()}%',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
