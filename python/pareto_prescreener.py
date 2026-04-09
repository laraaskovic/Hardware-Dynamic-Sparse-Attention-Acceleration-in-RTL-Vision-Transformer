"""
Software-only Pareto teaser: sweep thresholds (alpha) and compute
true sparsity, predicted sparsity (upper-bound mask), and IoU.

Outputs:
- CSV: docs/pareto_prescreener.csv
- Plot: docs/img/pareto_prescreener.png (IoU vs predicted sparsity)
"""

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--npz", required=True, help="Path to attention npz")
    p.add_argument(
        "--alpha-list",
        type=str,
        default="0.05,0.1,0.15,0.2,0.25,0.3",
        help="Comma list of alphas (fraction of per-sample/layer/head max)",
    )
    p.add_argument("--csv-out", type=str, default="docs/pareto_prescreener.csv")
    p.add_argument("--plot-out", type=str, default="docs/img/pareto_prescreener.png")
    return p.parse_args()


def compute_masks(attn, alpha):
    max_vals = attn.max(axis=(-1, -2), keepdims=True)
    true_mask = attn > (alpha * max_vals)

    row_l1 = np.abs(attn).sum(axis=-1, keepdims=True)
    col_l1 = np.abs(attn).sum(axis=-2, keepdims=True)
    ub = row_l1 * col_l1
    ub_max = ub.max(axis=(-1, -2), keepdims=True)
    pred_mask = ub > (alpha * ub_max)
    return true_mask, pred_mask


def main():
    args = parse_args()
    attn = np.load(args.npz)["attn"]  # shape (N, L, H?, S, S)
    # Merge optional head dim into samples dimension for simplicity
    if attn.ndim == 5:
        N, L, H, S, _ = attn.shape
        attn = attn.reshape(N * L * H, S, S)
    elif attn.ndim == 4:
        N, L, S, _ = attn.shape
        attn = attn.reshape(N * L, S, S)
    else:
        raise ValueError(f"Unexpected attention ndim {attn.ndim}")

    alphas = [float(x) for x in args.alpha_list.split(",")]

    rows = [("alpha", "true_sparsity", "pred_sparsity", "iou")]
    pts = []
    for alpha in alphas:
        true_mask, pred_mask = compute_masks(attn, alpha)
        iou = (np.logical_and(true_mask, pred_mask).sum()) / (
            np.logical_or(true_mask, pred_mask).sum()
        )
        true_spars = 1.0 - true_mask.mean()
        pred_spars = 1.0 - pred_mask.mean()
        rows.append((alpha, true_spars, pred_spars, iou))
        pts.append((pred_spars, iou, alpha))

    Path(args.csv_out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.csv_out, "w", newline="") as f:
        csv.writer(f).writerows(rows)

    # Plot IoU vs predicted sparsity
    plt.figure(figsize=(5, 4))
    for pred_s, iou, alpha in pts:
        plt.scatter(pred_s, iou, label=f"α={alpha}")
        plt.text(pred_s + 0.01, iou, f"{alpha}", fontsize=8)
    plt.xlabel("Predicted sparsity (fraction zeros)")
    plt.ylabel("Mask IoU (pred vs true)")
    plt.title("Prescreener trade-off (software)")
    plt.grid(True, ls="--", alpha=0.5)
    plt.ylim(0, 1.0)
    plt.xlim(0, 1.0)
    plt.legend()
    Path(args.plot_out).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(args.plot_out, dpi=200, bbox_inches="tight")
    print(f"Wrote CSV to {args.csv_out}")
    print(f"Wrote plot to {args.plot_out}")


if __name__ == "__main__":
    main()
