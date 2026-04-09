## Hardware-Native Dynamic Sparse Attention Engine

This repository implements an RTL-only, input-dependent sparsity predictor for attention. A magnitude-based pre-screener produces a per-block bitmask on the fly; a systolic PE array skips computation wherever the mask is zero, enabling higher and variable sparsity ratios than fixed 2:4 GPU cores.

### Research-style overview
- **Problem**: Fixed sparsity (e.g., GPU 2:4) ignores that important token pairs change per input. This wastes MACs and energy.
- **Idea**: A tiny RTL pre-screener uses L1 norms of Q/K blocks to upper-bound dot-product magnitude. If even the bound is below a threshold, skip that block. The mask is produced every input, in hardware, no software intervention.
- **Claim**: With <5% accuracy loss, this predictor can gate 60–80% of MACs on ViT-style attention, beating fixed 50% sparsity limits.
- **Hypothesis**: Magnitude-based upper bound is sufficient to avoid false negatives when threshold-scaled appropriately; area overhead stays small versus MAC array.

### Repository layout
- `docs/` — architecture notes, timelines, diagrams, measurement plans.
- `rtl/` — SystemVerilog for prescreener, PE array, softmax, FSM, AXI-lite bridge.
- `tb/` — SystemVerilog + Python co-simulation benches and SVA properties.
- `python/` — PyTorch baseline (ViT-Tiny/2-layer transformer) and data generators.
- `scripts/` — helper scripts for synthesis, plotting, and automation.
