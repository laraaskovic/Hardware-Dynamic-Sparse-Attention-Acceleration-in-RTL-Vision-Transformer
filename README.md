## DYNASPARSE: Hardware-Native Dynamic Sparse Attention Engine

This repository implements an RTL-only, input-dependent sparsity predictor for attention. A magnitude-based pre-screener produces a per-block bitmask on the fly; a systolic PE array skips computation wherever the mask is zero, enabling higher and variable sparsity ratios than fixed 2:4 GPU cores.

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
- Log attention: `python python/log_attention.py --ckpt checkpoints/vit_tiny.pt --max-batches 20`
- Sparsity sweep plot: `python python/compute_sparsity.py --npz checkpoints/vit_tiny.attn.npz`
- Prescreener IoU check: `python python/prescreener_sim.py --npz checkpoints/vit_tiny.attn.npz --alpha 0.1`
- Visualize attention + masks: `python python/vis_attention.py --npz checkpoints/vit_tiny.attn.npz --sample 0 --layer 0 --head 0 --alpha 0.1` → saves to `docs/img/attn_s0_l0_h0.png`
