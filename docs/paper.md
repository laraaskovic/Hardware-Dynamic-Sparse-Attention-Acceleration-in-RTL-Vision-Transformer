# DYNASPARSE: A Hardware-Native Magnitude-Based Pre-Screener for Dynamic Sparse Attention Acceleration in RTL

## Abstract
Transformer attention is quadratic in sequence length, motivating sparse computation. Production GPUs expose fixed sparsity patterns (e.g., 2:4) that fail to exploit input-dependent structure. We present **DYNASPARSE**, a fully RTL, hardware-native pre-screener that predicts block-level attention saliency on-the-fly and gates a systolic array accordingly. The core insight is to upper-bound dot-product magnitude using only L1 norms of query/key blocks, avoiding multipliers in the predictor. Our SystemVerilog implementation integrates a 2-cycle pre-screener, a valid-gated systolic array, masked softmax, and a control FSM with AXI-Lite, targeting FPGA prototypes. Software baselines on CIFAR-10 ViT show 41–90% sparsity across reasonable thresholds. Measured Q/K statistics guide fixed-point formats (Q1.7.8 inputs; 26‑bit accumulators; 52‑bit products). We provide self-checking testbenches, assertions, exp LUT generation, and a ModelSim regression script. This document summarizes architecture, design choices, verification strategy, and an experimental plan to produce Pareto curves of accuracy loss vs. MAC reduction vs. area, forming the core publishable results.

## 1. Introduction
Self-attention enables global context modeling but scales quadratically with sequence length. Software-level sparsity (pruning, pattern-based masks) and hardware fixed sparsity (e.g., NVIDIA 2:4) offer limited adaptivity: salient token pairs vary per input (physics paper vs. recipe). A hardware-software split reintroduces CPU overhead and latency. We instead co-design **dynamic, input-dependent sparsity entirely in hardware**: a fast pre-screener predicts which attention block pairs matter before full dot-products, emitting a mask that directly gates computation in the accelerator datapath.

## 2. Problem Statement and Goal
Given block-partitioned Q and K (size VEC_LEN each, fixed-point), decide at run time which block pairs to compute. We seek:
- ≥60% MAC reduction with <5% top-1 accuracy loss (CIFAR-10 ViT baseline).
- No software involvement at inference; mask generated per input in RTL.
- Area overhead small relative to the MAC array; timing compatible with FPGA fabric (100–200 MHz targets).

## 3. Baseline and Data Characterization
- Model: Small ViT (4 layers, 4 heads, dim=128) trained on CIFAR-10. Validation accuracy: 0.709 (CPU training).
- Attention sparsity (fraction zeros when threshold = α·max): α=0.1 → 41%, α=0.2 → 76%, α=0.3 → 90% (docs/phase0_sparsity.csv, docs/img/phase0_sparsity_curve.png).
- Q/K magnitude stats (10 batches): max |q|=4.55, |k|=4.68; max L1 per token/head |Q|₁=44.3, |K|₁=49.6; p99.9 ≈39–41 (docs/phase1_qk_stats.json). These inform accumulator widths.

## 4. Architectural Overview
Pipeline (docs/architecture_overview.md + mermaid diagram):
1) **Load buffers**: Q/K blocks streamed from SRAM (double-buffered).
2) **Magnitude pre-screener**: computes |Q|₁·|K|₁ upper bound in 2 cycles; compares to threshold to emit `mask`.
3) **Latency aligner**: shifts Q/K blocks to match pre-screener latency.
4) **Sparse systolic array**: DIM×DIM PEs; `valid_mask` gates MACs and holds accumulators when 0.
5) **Masked softmax**: log-sum-exp, exp LUT, zeroes masked positions.
6) **FSM + AXI-Lite**: IDLE→LOAD_Q→LOAD_K→PRESCREEN→COMPUTE→SOFTM→WRITEBACK; host config via AXI-Lite.

## 5. Key Design Choices
### 5.1 Pre-screener bound
Use L1 norms: `UB = |Q|₁·|K|₁`. By Cauchy–Schwarz, `|Q·K| ≤ ||Q||₂||K||₂ ≤ |Q|₁·|K|₁`. If UB < threshold, skip safely (no false negatives if threshold interpreted in same scale as true dot-product upper bound).

### 5.2 Fixed-point formats
- Inputs: Q1.7.8 (16-bit).
- L1 accumulators: 26 bits (Q9.16) to cover worst-case 64×4.7×1.2 guard ≈ 361.
- Product: 52 bits to hold |Q|₁·|K|₁.
- Softmax: inputs Q3.13; exp LUT Q0.16 over [-8,8] with step ~1; normalization uses integer divide (can swap for reciprocal LUT).

### 5.3 Latency and gating
Prescreener latency = 2 cycles. Data path uses a 2-stage shift to align mask with Q/K arrival at the array. `valid_mask=0` forces PEs to hold accumulators; SVA asserts no change during mask=0.

### 5.4 AXI-Lite map (current stub)
- 0x00 control (start)
- 0x04 status (done, busy)
- 0x08 threshold (low 32 bits), 0x0C threshold high if needed
Data buffers are stubbed for TB injection; production will map writes to SRAM windows.

## 6. RTL Modules
- `rtl/magnitude_prescreener.sv`: parameterized widths, exposes product monitor; TB and assertion included.
- `rtl/pe.sv`, `rtl/pe_array.sv`: valid-gated PEs; true shifting systolic mesh; TB holds accumulators when mask=0.
- `rtl/tile_prescreen_array.sv`: integrates prescreener + array with 2-cycle alignment; TB covers mask=0/1 behavior.
- `rtl/softmax_masked.sv`: masked log-sum-exp with exp LUT (`rtl/lut/exp_lut.mem`), integer normalization; TB with coarse numeric check.
- `rtl/axi_lite_slave.sv`: minimal AXI-Lite for control/threshold.
- `rtl/top_dynasparse.sv`: FSM skeleton + AXI-Lite wiring + tile hookup (softmax/data buffers currently stubbed).

## 7. Verification
### 7.1 Unit testbenches (ModelSim ready)
- `tb/magnitude_prescreener_tb.sv`: random vectors, golden bound compare, pipeline scoreboard, SVA no false negatives.
- `tb/pe_tb.sv`: valid gating and load_acc behavior.
- `tb/pe_array_tb.sv`: hold property when mask=0 across cycles.
- `tb/tile_prescreen_array_tb.sv`: end-to-end mask=0/1 paths.
- `tb/softmax_masked_tb.sv`: masked softmax against behavioral reference (tolerance).
- `tb/top_dynasparse_tb.sv`: AXI-Lite BFM skeleton; starts a block (functional checks TBD).
Run all: `vsim -c -do scripts/run_modelsims.do`.

### 7.2 Assertions
- Prescreener: product ≥ threshold ⇒ mask=1 (embedded).
- PE/array: mask=0 ⇒ accumulators hold (TB + property).
- Tile: mask alignment with data (implicit via TB; formal property to add).
- FSM: no illegal states (to add).

### 7.3 Formal (future)
Use Jasper/Questa Formal on prescreener and array gating invariants; property templates live in TBs and can be promoted.

## 8. Measurement Plan
1) **Functional correctness**: end-to-end TB comparing RTL outputs to Python golden for small sizes (DIM=2/4).
2) **MAC savings**: instrument cycle-accurate counters in tile/array; sweep threshold; report MACs computed vs. dense.
3) **Accuracy impact**: reuse Python `prescreener_sim.py` and extend to use RTL mask (exported from sim) to recompute attention; measure top-1 drop.
4) **Area/Fmax**: synthesize prescreener, array, softmax, and full top on target FPGA (Quartus/Vivado); record LUT/FF/BRAM/DSP and Fmax.
5) **Pareto**: Plot accuracy loss vs. MAC saved vs. area at multiple thresholds (docs/img/pareto_prescreener.png is software-only teaser).

## 9. Experimental Setup
- Software: PyTorch 2.11.0 CPU wheels, CIFAR-10; scripts in `python/`.
- RTL: SystemVerilog; ModelSim/Questa for sim; Quartus/Vivado for synthesis.
- Fixed-point scaling: Q1.7.8 inputs; thresholds scaled to product domain (Q9.16×Q9.16 → 52 bits).
- LUT generation: `python/gen_exp_lut.py` (range [-8,8], step ~1/128, Q0.16).

## 10. Expected Results (target)
- MAC reduction: 60–80% at thresholds 0.1–0.2 with <5% accuracy drop (guided by software sparsity).
- Prescreener area: adders/comparators only; expect negligible DSP use, moderate LUTs; latency 2 cycles @ 100–200 MHz.
- Overall speed/energy: proportional to MAC reduction minus prescreener overhead; quantify with cycle counts and post-P&R power estimates.

## 11. Related Work (concise)
- Fixed sparsity (NVIDIA 2:4) offers static patterns; cannot adapt per input.
- Learned sparsity masks require software involvement (pruning, dynamic routing) and typically run on CPU/GPU.
- Branch prediction analogy: fast, cheap predictor guiding expensive compute; our design applies this to attention sparsity.

## 12. Limitations and Risks
- Softmax currently uses integer divide; for high Fmax, replace with reciprocal LUT + multiplier.
- AXI-Lite data-plane writes are stubbed; need buffer mapping for full-system tests.
- Current TBs use small dimensions; must scale to DIM=4/8 and VEC_LEN=64 with synthesis-informed timing.
- Formal proofs not yet run; assertions exist but unproven for all inputs.

## 13. Future Work
- Complete AXI-Lite data path and SRAM buffers; run end-to-end co-sim with Python BFM.
- Add streaming V input and output accumulation for full attention (Q,K,V path).
- Explore adaptive thresholds per head/layer (register-configurable).
- Port to ASIC flow; compare energy vs. FPGA.
- Extend to structured block patterns (variable block sizes) and sequence lengths beyond CIFAR-10 patches.

## 14. Reproducibility Checklist
- Code: RTL + Python + scripts in repo; exp LUT auto-generated.
- Commands: quickstart in README; ModelSim regression in `scripts/run_modelsims.do`.
- Data: CIFAR-10 automatically downloaded by scripts.
- Randomness: TBs are seeded via $urandom; can fix seeds for determinism.

## 15. Conclusion
DYNASPARSE demonstrates that a magnitude-only, fixed-function pre-screener can be implemented with negligible multipliers, enabling dynamic, per-input sparsity masks that gate a systolic array in hardware. Early software results show high sparsity headroom; RTL implements the predictor, gating, and softmax with verification scaffolding and synthesis-friendly fixed-point choices. The remaining integration (buffers/AXI, reciprocal LUT, full-system TBs) is straightforward engineering. With MAC savings, accuracy measurements, and area reports, the resulting Pareto curves constitute a publishable contribution and a compelling demonstration for research or industrial evaluation.

---

*Repository paths: RTL under `rtl/`, testbenches under `tb/`, scripts under `scripts/`, plots under `docs/img/`, paper at `docs/paper.md`.* 
