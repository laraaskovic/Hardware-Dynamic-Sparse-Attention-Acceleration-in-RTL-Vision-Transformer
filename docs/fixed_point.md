## Proposed fixed-point formats

Target: fit comfortably in mid-range FPGA DSP slices while keeping softmax stable.

### Attention inputs (Q, K, V)
- Format: signed Q1.7.8 (total 16 bits; 1 sign, 7 integer, 8 fractional).
- Rationale: values after layernorm typically in [-3, 3]; 7 integer bits cover range with headroom.
- Absolute value in prescreener is simple sign-bit flip.

### Pre-screener intermediate
- |Q|₁ and |K|₁ sums grow with vector length `N`.
- Worst-case magnitude ≈ `N * max(|Q|)`. For N=64 and max|Q|≈3.5 → ~224.
- Use 24-bit accumulator (Q5.18) to avoid overflow; pipeline adders accordingly.
- The product |Q|₁×|K|₁ can exceed 32 bits; keep 40-bit internal product, then compare to threshold.

### Threshold register
- Store as Q5.18 to match |Q|₁ scale; host writes scaled integer value: `threshold_fixed = real_threshold * 2^18`.
- Document exact `threshold` used during sweeps in `docs/decision_log.md`.

### Softmax
- Inputs to exp are log-sum-exp shifted; use Q3.13 (16-bit) into LUT.
- Exp LUT covers [-8, 8] with step 1/128 (16384 entries) → BRAM friendly.
- Output probabilities stored as Q0.16.

### Next actions
- Validate these ranges with Phase 0 logs (actual Q/K min/max and L1 sums); adjust bit widths if overflow margin <20%.
