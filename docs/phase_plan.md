## Phase-by-Phase Plan (with concrete outputs)

Use this as the living north star. Each phase lists: objective, deliverables (file paths), tests/metrics, and a day-by-day micro-plan for the first week of that phase.

### Phase 0 — Software Baseline (Python, ~2 weeks)
- **Objective**: Establish dense attention reference, ground-truth sparsity maps, and a software model of the magnitude pre-screener.
- **Deliverables**
  - `python/baseline_vit.py` — train/eval ViT-Tiny or 2-layer transformer on CIFAR-10; save checkpoints.
  - `python/log_attention.py` — dump per-layer attention matrices for a held-out validation split.
  - `python/compute_sparsity.py` — compute thresholds vs. sparsity histograms; save `.npz` masks.
  - `python/prescreener_sim.py` — software version of L1-upper-bound masking; reports accuracy drop vs dense.
- **Tests / Metrics**
  - Accuracy drop <5% vs dense on CIFAR-10.
  - Per-threshold CSV: `threshold, sparsity_ratio, fp_top1_acc`.
  - Plots saved to `docs/img/phase0_sparsity_curve.png`.
- **First-week micro-plan**
  - Day 1: Set up env (`requirements.txt`); download CIFAR-10; verify training loop.
  - Day 2: Train small model to baseline accuracy; log validation accuracy.
  - Day 3: Instrument attention logging; save sample matrices.
  - Day 4: Implement sparsity histogram + mask generator; sweep thresholds.
  - Day 5: Prototype prescreener_sim; compare predicted mask vs ground truth IoU.

### Phase 1 — Magnitude Pre-Screener RTL (SystemVerilog, ~4 weeks)
- **Objective**: Pipelined module `magnitude_prescreener` producing 1-bit valid per Q/K block pair.
- **Deliverables**
  - `rtl/magnitude_prescreener.sv` — parameterized widths, pipeline depth; includes abs units, adder tree, threshold register.
  - `tb/magnitude_prescreener_tb.sv` — self-checking SV testbench, random vectors + golden model compare.
  - `tb/sva/magnitude_prescreener_assert.sv` — SVA for no false negatives (upper-bound proof).
- **Tests / Metrics**
  - Latency 2–3 cycles; meets target Fmax (set in synthesis script).
  - Assertion: if `|Q|1 * |K|1 >= threshold` then `valid_out` must be 1.
- **First-week micro-plan**
  - Day 1: Fix-point format spec (total bits, frac bits) document in `docs/fixed_point.md`.
  - Day 2: Draft module interface; write skeleton in RTL.
  - Day 3: Implement abs + adder tree; parameterize vector length.
  - Day 4: Add threshold register + pipeline registers; hook up valid flag.
  - Day 5: Write TB + SVA; run 1k random cases.

### Phase 2 — Sparse Systolic PE Array (SystemVerilog, ~4 weeks)
- **Objective**: 4×4 or 8×8 PE array with `valid_in` gating to skip MACs on masked blocks.
- **Deliverables**
  - `rtl/pe.sv` — single PE with valid gating, accumulator hold logic.
  - `rtl/pe_array.sv` — systolic array wrapper with streaming Q/K blocks.
  - `tb/pe_array_tb.sv` — random block tests with and without masks.
- **Tests / Metrics**
  - When `valid_in=0`, no accumulator change and downstream stalls proven via SVA.
  - Throughput: 1 MAC/cycle when valid; compute/skip ratio matches mask density.

### Phase 3 — Softmax + Mask (SystemVerilog, ~2 weeks)
- **Objective**: Masked softmax using log-sum-exp and LUT exp.
- **Deliverables**
  - `rtl/softmax_masked.sv` with LUT BRAM init file in `rtl/lut/exp_lut.mem`.
  - `tb/softmax_masked_tb.sv` — compares against Python fixed-point golden.
- **Tests / Metrics**
  - Max absolute error vs Python ref within tolerance (documented in TB).
  - Masked positions force output zero; proven with SVA.

### Phase 4 — Memory Interface + Control FSM (SystemVerilog, ~2 weeks)
- **Objective**: Top-level orchestrating LOAD→PRESCREEN→COMPUTE→WRITEBACK with double buffering.
- **Deliverables**
  - `rtl/top_dynasparse.sv` — integrates prescreener, PE array, softmax, SRAM/AXI-Lite.
  - `rtl/axi_lite_slave.sv` — config + data path.
  - `tb/top_system_tb.sv` — bus functional model driving AXI-Lite transactions.
- **Tests / Metrics**
  - No WRITEBACK before COMPUTE done (SVA).
  - Overlapped load/compute verified via waveform + cycle counter.

### Phase 5 — Verification (SystemVerilog + Python, ~3 weeks)
- **Objective**: End-to-end correctness checks and formal properties.
- **Deliverables**
  - `python/gen_vectors.py` — emit random Q/K and expected outputs for TB.
  - `tb/sva/` — full property suite (no invalid states, gating correctness).
  - `scripts/run_modelsim.do` — regression script.
- **Tests / Metrics**
  - Regression suite passes; formal proofs complete for key properties.

### Phase 6 — Measurement & Analysis (Python + synthesis, ~2 weeks)
- **Objective**: Pareto curves of accuracy vs MAC savings vs area.
- **Deliverables**
  - `scripts/sweep_thresholds.py` — runs RTL sim + Python ref across thresholds.
  - `docs/img/pareto_accuracy_mac_area.png` — main paper figure.
  - `docs/report.md` — summarized findings for paper.
- **Tests / Metrics**
  - Target point: ~70% MAC reduction with <2% accuracy loss; include area overhead percentage.

---

## Suggested work cadence
Work in short loops:
1) Write spec doc (small).
2) Implement RTL slice.
3) Add TB + SVA immediately.
4) Run regression (scripts to come).
5) Check in results/plots to `docs/img`.

Keep `docs/decision_log.md` to note any parameter changes (threshold scaling, bit widths).
