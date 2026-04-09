## Proposed fixed-point formats

Target: fit comfortably in mid-range FPGA DSP slices while keeping softmax stable.

### Attention inputs (Q, K, V)
- Format: signed Q1.7.8 (total 16 bits; 1 sign, 7 integer, 8 fractional).
- Rationale: values after layernorm typically in [-3, 3]; 7 integer bits cover range with headroom.
- Absolute value in prescreener is simple sign-bit flip.

### Pre-screener intermediate
- |Q|₁ and |K|₁ sums grow with vector length `N`.
- Measured on CIFAR-10 ViT (10 batches, batch=64): max |q|≈4.55, |k|≈4.68; max L1 per token/head: |Q|₁≈44.3, |K|₁≈49.6 (p99.9 ≈ 39–41).
- Worst-case bound for N=64 using measured max |K|: 64 * 4.7 ≈ 301; add 20% guard → ~361.
- Recommendation: accumulator width ≥ 26 bits with ~16 fractional bits (e.g., Q9.16 → ±512 range) to retain margin. Product width ≈ 52 bits (2*SUM_W) to hold |Q|₁×|K|₁.
- Existing RTL parameters can be set as: `SUM_W = WIDTH + $clog2(VEC_LEN) + 4` (with WIDTH=16, VEC_LEN=64 → SUM_W=26), `PROD_W = 2*SUM_W`.

### Threshold register
- Store as Q5.18 to match |Q|₁ scale; host writes scaled integer value: `threshold_fixed = real_threshold * 2^18`.
- Document exact `threshold` used during sweeps in `docs/decision_log.md`.

### Softmax
- Inputs to exp are log-sum-exp shifted; use Q3.13 (16-bit) into LUT.
- Exp LUT covers [-8, 8] with step 1/128 (16384 entries) → BRAM friendly.
- Output probabilities stored as Q0.16.

### Next actions
- Validate these ranges with Phase 0 logs (actual Q/K min/max and L1 sums); adjust bit widths if overflow margin <20%.
