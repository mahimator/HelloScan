# HelloScan

HelloScan is an Android-first Flutter app for capturing visiting cards into a temporary batch, reviewing contact details, and exporting CRM-ready JSON. It is **not** a permanent contacts database.

## What it does

- Capture a card's front with the phone camera and its back when needed.
- Import multiple card images from the gallery.
- Read cards **on-device** with Google ML Kit — images never leave the phone.
- Improve weak captures before OCR:
  - apply EXIF orientation so sideways photos are upright
  - convert to grayscale
  - stretch contrast and lift shadows
  - upscale low-resolution photos (with a conservative cap for entry-level devices)
  - cap oversized camera/gallery images before OCR to limit peak memory use
- Extract structured fields from noisy OCR text:
  - name, designation, company, email, phone, website and address
  - repair `O`/`0`, `l`/`1` and `S`/`5` confusions inside phone numbers
  - repair spaced emails (`john . doe @ acme . com`)
  - repair near-miss email domains using the card's website (`acrme-tech.com` → `acrne-tech.com`)
  - merge front/back scans and de-duplicate emails and phones
  - use explicit company text and domain correspondence as supporting evidence without inventing a company name
- Review-first editing: OCR fills fields, but never overwrites a field you have typed into.
- Paste raw text as a fallback for unreadable photos or external OCR.
- Export the batch as `helloscan.contact-batch.v1` JSON and clear it with confirmation.

Cards live in memory only. Images are used for OCR and are **not** embedded in exports. Nothing is uploaded.

## Accuracy notes

OCR quality depends on the capture. HelloScan mitigates common problems (low resolution, low contrast, rotation, OCR letter/digit confusions, domain misreads), and the review step is deliberately mandatory. Embossed, handwritten or extremely faint cards may still need manual edits or the **Paste text** fallback.

The recognizer currently uses ML Kit's Latin script. Other scripts can be enabled by swapping `TextRecognitionScript` in `MlKitOcrService`.

## Architecture

| Path | Responsibility |
| --- | --- |
| `lib/models/scan_card.dart` | Staged card + JSON mapping |
| `lib/models/parsed_card.dart` | Extraction result and merge logic |
| `lib/services/card_parser.dart` | Pure-Dart OCR text → fields parser |
| `lib/services/image_enhancer.dart` | Pre-OCR image enhancement |
| `lib/services/ocr_service.dart` | OCR abstraction (injectable for tests) |
| `lib/services/mlkit_ocr_service.dart` | On-device ML Kit implementation |
| `lib/services/batch_export.dart` | Schema payload builder |
| `lib/ui/batch_home.dart` | Capture, review, export UI |

## Stack

- Flutter / Dart
- `image_picker` for camera and gallery
- `google_mlkit_text_recognition` for on-device OCR
- `image` for preprocessing
- `path_provider` for temporary OCR files
- `file_picker` for JSON export
- JSON schema at `schemas/contact-batch-v1.schema.json`

## Android setup

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android project is checked in under `android/` and builds with:

- Gradle 9.6.0
- Android Gradle Plugin 9.1.1
- `compileSdk` from the Flutter toolchain (36)
- `minSdk` 21

Build a debug APK with:

```bash
flutter build apk --debug --target-platform android-arm64
```

The on-device OCR test needs a device or emulator with Google Play services. ML Kit's text model is downloaded on first use and then runs offline.

## Tests

Fast host suite (no device needed):

```bash
flutter test
```

Covers the parser (clean, noisy and degraded card text), image enhancement, JSON export, the widget shell and the full paste → extract → review → clear flow.

Integration tests on a connected Android device:

```bash
# App flow: paste a messy card, verify extracted fields, review, clear
flutter test integration_test/app_test.dart -d <device-id>

# Real ML Kit OCR against a deliberately degraded synthetic card
flutter test integration_test/ocr_test.dart -d <device-id>
```

## Export format

The batch export uses `helloscan.contact-batch.v1`. Contact fields are editable and remain nullable when unknown. Images are not embedded in the export.

## CI

GitHub Actions runs Flutter analysis, unit/widget tests and a debug APK build on pushes and pull requests. A successful build uploads an APK artifact. Integration tests require a physical device or emulator with Google Play services and run locally/nightly.

## Release / Play Store readiness

### Application ID
The app currently uses the placeholder `com.example.helloscan`. Before publishing, set a real, owned application ID in `android/app/build.gradle.kts` (`applicationId`) — Play Console does not accept `com.example.*`.

### Signing
`android/app/build.gradle.kts` signs the `release` build type with the debug signing config so `flutter build apk --release` works out of the box. For production, add your own `signingConfig` (keystore via `android/key.properties`, which is gitignored) and never commit the keystore.

### Permissions
- `CAMERA` — card capture
- `READ_MEDIA_IMAGES` — gallery import
- `INTERNET` — ML Kit downloads its on-device recognition model once (then runs fully offline)

All card images stay in memory on the device and are never embedded in exports or uploaded.

### Data safety (Google Play)
HelloScan is an ephemeral staging tool, not a permanent contacts store:
- No personal data is collected, shared, or transmitted off-device.
- ML Kit OCR runs on-device; card images never leave the phone.
- Exports are JSON written to a location you choose via the system file picker.

### Build
Debug APK:
```bash
flutter build apk --debug --target-platform android-arm64
```
Release APK:
```bash
flutter build apk --release --target-platform android-arm64
```

### Integration tests
Run on the physical device (integration tests are not run on an emulator per project policy):
```bash
flutter test integration_test/app_test.dart -d R8YL40VQXXT
flutter test integration_test/ocr_test.dart -d R8YL40VQXXT
```
The device must have Google Play services for ML Kit's model download.
