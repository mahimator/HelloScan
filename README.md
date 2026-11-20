# HelloScan

HelloScan is an Android-first Flutter app for capturing visiting cards into a temporary batch, reviewing extracted contact details, and exporting CRM-ready JSON. It is **not** a permanent contacts database.

## Stack
- Flutter / Dart
- Android camera capture via `image_picker`
- Multi-image gallery import
- Manual review/editing
- JSON batch export
- OCR/model inference planned behind a replaceable interface

## Current status
Mobile-first scaffold: scan a front, capture its back, import gallery images, stage cards in memory, edit contact fields, and export a batch JSON file.

## Run
Install Flutter SDK, then:
```bash
flutter create --platforms android .
flutter pub get
flutter run
```
