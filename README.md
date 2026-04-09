## DYNASPARSE: Hardware-Native Dynamic Sparse Attention Engine

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

### High-level milestones
1) **Software baseline** — dense attention logging, sparsity maps, prescreener algorithm simulation.
2) **Magnitude pre-screener RTL** — pipelined L1-norm bound, parameterized threshold register.
3) **Sparse systolic array** — valid-gated PEs, timing-aligned with prescreener.
4) **Softmax + mask** — log-sum-exp with LUT exp, masked inputs to -INF.
5) **Memory + control** — double-buffered SRAM path, AXI4-Lite register map, top FSM.
6) **Verification** — self-checking testbench + SVA invariants, formal where possible.
7) **Measurement** — accuracy vs MAC savings vs area Pareto sweep.

### How to use this guide
We will proceed phase-by-phase. Each phase has a checklist in `docs/phase_plan.md` and concrete deliverables with file paths. Start at Phase 0 unless otherwise directed.

### Phase 0 quickstart
- Install deps: `python -m venv .venv && .\.venv\Scripts\activate && pip install -r python/requirements.txt`
- Train baseline: `python python/baseline_vit.py --epochs 20 --batch-size 128 --save checkpoints/vit_tiny.pt`
- Log attention: `python python/log_attention.py --ckpt checkpoints/vit_tiny.pt --max-batches 20` (per-head saved after this change)
- Sparsity sweep plot: `python python/compute_sparsity.py --npz checkpoints/vit_tiny.attn.npz`
- Prescreener IoU check: `python python/prescreener_sim.py --npz checkpoints/vit_tiny.attn.npz --alpha 0.1`
- Visualize attention + masks: `python python/vis_attention.py --npz checkpoints/vit_tiny.attn.npz --sample 0 --layer 0 --head 0 --alpha 0.1` → saves to `docs/img/attn_s0_l0_h0.png`

### Current status (Phase 0 → 1)
- CIFAR-10 ViT baseline trained on CPU: best val_acc ≈ 0.709.
- Sparsity sweep (alpha as fraction of per-head max): 0.1 → 41% zeros, 0.2 → 76% zeros, 0.3 → 90% zeros (docs/phase0_sparsity.csv, plot in docs/img/).
- Prescreener software proxy at alpha=0.1: true sparsity 0.409, predicted sparsity 0.027, mask IoU 0.606 (docs/phase0_prescreener_iou.txt).
- RTL prescreener implemented with 2-cycle pipeline; self-checking TB and SVA “no false negatives” property in place (magnitude_prescreener.sv, tb/magnitude_prescreener_tb.sv).

### Next steps (Phase 1–2 plan)
1) **Validate fixed-point margins**: extract Q/K L1 statistics from logged data; adjust SUM_W/PROD_W if overflow headroom <20%; record in docs/decision_log.md and docs/fixed_point.md.
2) **Prescreener timing/synthesis**: run ModelSim TB + Questa/Quartus/Vivado synthesis to confirm Fmax target and area; capture resource table in docs.
3) **Integrate sparse systolic array**: implement `pe.sv` and `pe_array.sv` with `valid_in` gating, align mask timing with prescreener output.
4) **Softmax masking**: add masked log-sum-exp RTL with LUT exp and verify against Python fixed-point model.
5) **Top-level FSM + AXI-lite**: orchestrate LOAD→PRESCREEN→COMPUTE→WRITEBACK with double buffering; provide Python BFM TB.
6) **Measurement sweep**: automate threshold sweeps (Python + RTL sim) to produce Pareto curves (accuracy vs MAC saved vs area) for paper figures.

### Paper-ready artifacts to collect
- Attention heatmaps + masks: run `vis_attention.py` on multiple samples/heads; store in `docs/img/`.
- SVA proof or coverage reports for prescreener invariant.
- Synthesis summary (LUTs/FFs/DSPs) and post-P&R Fmax for prescreener and full array.
- Pareto plot showing dynamic sparsity vs fixed 50% baseline.
