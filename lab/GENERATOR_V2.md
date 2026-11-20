# HelloScan Lab

## v2 dataset generator

Creates synthetic front/back business-card image pairs and JSON labels with randomized palettes, layout families, optional missing fields, multiple contact details, and image degradation augmentation.

> All names, phone numbers, and addresses are fabricated. Domains use reserved `.example` placeholders.

```bash
python -m pip install pillow
python src/synthetic_cards.py --out data/synthetic-v2 --count 1000 --seed 42
```

## Dataset splits
The generator assigns split labels based on layout family. This is a simple layout-family holdout to avoid test leakage, not a substitute for a final evaluation set of real, permissioned cards. For meaningful evaluation, keep the test set private and add cards photographed on actual phones.

## Current roadmap
1. Synthetic generator and schema
2. Dataset inspection and quality audit
3. Benchmark candidate mobile multimodal model(s)
4. Fine-tune the chosen single model
5. Quantize to 4-bit, measure extraction quality and device resource usage
6. Android integration and offline smoke tests
