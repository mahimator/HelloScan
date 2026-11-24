import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads OCR models from Hugging Face and stores them in the app's
/// documents directory. Shows progress via [onProgress].
class ModelDownloader {
  ModelDownloader._();
  static final ModelDownloader instance = ModelDownloader._();

  /// Directory where downloaded models are stored.
  Future<Directory> get _appDocsDir async => getApplicationDocumentsDirectory();

  /// Returns the directory `app_documents/helloscan/models/`.
  Future<Directory> get _modelsDir async {
    final dir = Directory(p.join((await _appDocsDir).path, 'helloscan', 'models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Path to a downloaded model file by name.
  Future<String> modelPath(String modelName) async {
    final dir = await _modelsDir;
    return p.join(dir.path, modelName);
  }

  /// Checks whether a model file already exists locally.
  Future<bool> modelExists(String modelName) async {
    final path = await modelPath(modelName);
    return File(path).existsSync();
  }

  /// Download a file from [url] to [destination] with progress callbacks.
  ///
  /// [onProgress] receives (bytesDownloaded, totalBytes).
  Future<void> download({
    required String url,
    required String destination,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await http.Client().send(request);

    final response = streamedResponse;
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download $url: HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final contentLength = response.contentLength ?? -1;
    final file = File(destination);
    final sink = file.openWrite();

    int downloaded = 0;
    await for (final bytes in response.stream) {
      downloaded += bytes.length;
      sink.add(bytes);
      onProgress(downloaded, contentLength);
    }

    await sink.flush();
    await sink.close();
  }

  /// Downloads both detection and recognition models for a [PhoneTierConfig].
  ///
  /// Skips any model that already exists locally. Calls [onProgress] with a
  /// message string and a 0.0–1.0 progress fraction.
  Future<void> downloadTierModels({
    required PhoneTierConfig config,
    required void Function(String message, double progress) onProgress,
  }) async {
    final detPath = await modelPath('det_${config.tier.name}.tflite');
    final recPath = await modelPath('rec_${config.tier.name}.tflite');

    final detExists = await modelExists('det_${config.tier.name}.tflite');
    final recExists = await modelExists('rec_${config.tier.name}.tflite');

    if (detExists && recExists) {
      onProgress('Models already downloaded', 1.0);
      return;
    }

    int completed = 0;
    final totalSteps = (detExists ? 0 : 1) + (recExists ? 0 : 1);

    if (!detExists) {
      onProgress('Downloading detection model…', 0.0);
      await download(
        url: config.detModelUrl,
        destination: detPath,
        onProgress: (downloaded, total) {
          final stepProgress = total > 0 ? downloaded / total : 0.0;
          final overall = (completed + stepProgress) / totalSteps;
          onProgress('Downloading detection model…', overall.clamp(0.0, 1.0));
        },
      );
      completed++;
    }

    if (!recExists) {
      onProgress('Downloading recognition model…', 0.0);
      await download(
        url: config.recModelUrl,
        destination: recPath,
        onProgress: (downloaded, total) {
          final stepProgress = total > 0 ? downloaded / total : 0.0;
          final overall = (completed + stepProgress) / totalSteps;
          onProgress('Downloading recognition model…', overall.clamp(0.0, 1.0));
        },
      );
      completed++;
    }

    onProgress('Download complete', 1.0);
  }

  /// Clears all downloaded models (useful for testing or tier change).
  Future<void> clearModels() async {
    final dir = await _modelsDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }
}
