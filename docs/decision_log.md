## Decision Log

Record parameter and architecture decisions with date and rationale.

- 2026-04-08: Initial fixed-point proposal (Q1.7.8 inputs, Q5.18 sums, 40-bit product) — subject to validation after Phase 0 statistics.
- 2026-04-08: Phase 0 results — CIFAR-10 ViT baseline val_acc=0.709 (best checkpoint); sparsity sweep (alpha:0.05→0.139, 0.1→0.409, 0.2→0.762, 0.3→0.904 zeros); prescreener sim at alpha=0.1 gives true sparsity=0.4093, predicted sparsity=0.0268, mask IoU=0.6062. Candidate threshold range for RTL: alpha 0.1–0.2; fixed-point ranges still acceptable pending L1 stats extraction.
- 2026-04-09: Q/K stats from checkpoint (10 test batches, batch=64) — max |q|=4.55, |k|=4.68; max |Q|₁=44.3, |K|₁=49.6, p99.9 ≈39–41. For VEC_LEN=64 worst-case bound ≈301; with 20% guard ≈361 → set prescreener accumulator to ≥26 bits (e.g., Q9.16) and product width ≈52 bits. Inputs remain Q1.7.8.
