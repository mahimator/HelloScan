# HelloScan Lab

Research and dataset tooling for a single compact multimodal visiting-card extraction model. The deployment target is Android offline inference, with 4-bit quantization investigated from the beginning.

## Principles
- One model and one inference path in the app
- Image input, front/back pairs supported
- Canonical HelloScan JSON as the target
- Synthetic data first, permissioned real cards later
- Never invent missing fields
- Measure accuracy, latency, peak RAM and model size on real target devices
- Colab is a training workspace, not the production inference server

## Current phase
Phase 0: dataset format and synthetic card generator. This is deliberately before fine-tuning.

## Contents
- `dataset/schema.json`: training sample schema
- `src/synthetic_cards.py`: synthetic visiting-card image generator with fake data
- `notebooks/01_dataset_builder.ipynb`: Colab notebook to generate and export an initial dataset

## Run locally
```bash
python -m pip install pillow
python src/synthetic_cards.py --out data/synthetic --count 100 --seed 42
```

Generated samples are synthetic. Do not use real people's personal contact details in the public repository.
