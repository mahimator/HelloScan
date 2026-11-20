# HelloScan

HelloScan is an Android-first Flutter app for capturing visiting cards into a temporary batch, reviewing contact details, and exporting CRM-ready JSON. It is **not** a permanent contacts database.

## Current milestone

- Capture a card's front with the phone camera
- Capture the back of the selected card
- Import multiple card images from gallery
- Create a blank card and edit fields manually
- Review cards and remove individual records
- Export the batch as structured JSON
- Clear the entire temporary batch when finished

Card records are staged in app memory only. There is no OCR yet, no permanent contacts store, and no database. The next milestone is OCR/model extraction with a review-first workflow.

## Stack

- Flutter / Dart
- `image_picker` for camera and gallery
- `file_picker` for JSON export
- JSON schema at `schemas/contact-batch-v1.schema.json`

## Local Android setup

Install Flutter and Android Studio/Android SDK, then run:

```bash
flutter create --platforms android .
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android scaffold is generated locally and by CI, keeping platform boilerplate out of the initial source commit.

## CI

GitHub Actions runs Flutter analysis, unit tests, and a debug APK build on pushes and pull requests. A successful build uploads an APK artifact from the workflow run.

## Export format

The batch export uses `helloscan.contact-batch.v1`. Contact fields are editable and remain nullable when unknown. Images are not embedded in the export.
