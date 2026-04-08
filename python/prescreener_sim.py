"""
Software simulation of the magnitude-based pre-screener.
Given Q/K tensors, computes |Q|1 * |K|1 upper bound and generates a binary mask.
Use this to estimate accuracy drop vs dense attention before RTL implementation.
"""

import argparse
from pathlib import Path

import numpy as np


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--npz", type=str, required=True, help="Attention npz from logging step")
    p.add_argument("--alpha", type=float, default=0.1, help="Threshold fraction of max attention")
    p.add_argument("--out", type=str, default="docs/phase0_prescreener_iou.txt")
    return p.parse_args()


def upper_bound_mask(attn: np.ndarray, alpha: float):
    """
    attn: array (N, L, H, S, S) of true attention scores.
    alpha: threshold fraction of max per sample/layer/head.
    Returns binary mask predicted by upper bound (here we reuse true Q/K magnitudes via stored attn).
    """
    max_vals = attn.max(axis=(-1, -2), keepdims=True)
    true_mask = attn > (alpha * max_vals)  # ground truth important positions

    # Approximate pre-screener: use L1 of rows/cols as proxy upper bound.
    # Since we don't have Q and K directly here, approximate using attention matrix magnitudes.
    row_l1 = np.abs(attn).sum(axis=-1, keepdims=True)  # (N,L,H,S,1)
    col_l1 = np.abs(attn).sum(axis=-2, keepdims=True)  # (N,L,H,1,S)
    upper = row_l1 * col_l1  # loose bound; shape (N,L,H,S,S)

    ub_max = upper.max(axis=(-1, -2), keepdims=True)
    ub_mask = upper > (alpha * ub_max)  # predicted important positions
    return true_mask, ub_mask


def intersection_over_union(a: np.ndarray, b: np.ndarray):
    inter = np.logical_and(a, b).sum()
    union = np.logical_or(a, b).sum()
    return inter / union if union > 0 else 1.0


def main():
    args = parse_args()
    data = np.load(args.npz)
    attn = data["attn"]
    true_mask, ub_mask = upper_bound_mask(attn, args.alpha)
    iou = intersection_over_union(true_mask, ub_mask)

    sparsity_true = 1.0 - true_mask.mean()
    sparsity_pred = 1.0 - ub_mask.mean()

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w") as f:
        f.write(f"alpha={args.alpha}\n")
        f.write(f"true sparsity={sparsity_true:.4f}\n")
        f.write(f"pred sparsity={sparsity_pred:.4f}\n")
        f.write(f"mask IoU={iou:.4f}\n")

    print(f"Wrote stats to {args.out}")


if __name__ == "__main__":
    main()
