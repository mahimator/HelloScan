# HelloScan

Privacy-first visiting card scanner and information extractor.

## Current milestone

- Batch import visiting cards from images.
- Support front-only, back-only, and front/back paired scans.
- Review and edit extracted records in a batch.
- Export a structured JSON batch for CRM ingestion.
- Keep OCR inference replaceable so the UI is not tied to one model.

## Development

Install dependencies and start the dev server:

```bash
npm install
npm run dev
```

The current prototype uses manual review fields and a placeholder extraction adapter. OCR/model integration is not yet implemented.
