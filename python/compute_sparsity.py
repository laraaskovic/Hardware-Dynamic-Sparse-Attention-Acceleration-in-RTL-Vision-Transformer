"""
Compute sparsity statistics and threshold sweeps from saved attention matrices.
Input: .npz produced by baseline_vit or log_attention with key 'attn' (N, L, H, S, S)
Outputs:
  - CSV of threshold vs sparsity ratio and accuracy (if provided)
  - Plot saved to docs/img/phase0_sparsity_curve.png
"""

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--npz", type=str, required=True, help="Path to attention npz file")
    p.add_argument("--alpha-list", type=str, default="0.05,0.1,0.2,0.3", help="Comma list of thresholds as fraction of max")
    p.add_argument("--csv-out", type=str, default="docs/phase0_sparsity.csv")
    p.add_argument("--plot-out", type=str, default="docs/img/phase0_sparsity_curve.png")
    return p.parse_args()


def main():
    args = parse_args()
    data = np.load(args.npz)
    attn = data["attn"]  # shape (N, L, H, S, S)
    val_acc = float(data.get("val_acc", np.nan))

    alphas = [float(x) for x in args.alpha_list.split(",")]
    rows = [("alpha", "sparsity_ratio", "val_acc")]

    max_vals = attn.max(axis=(-1, -2), keepdims=True)  # per sample/layer/head

    sparsities = []
    for alpha in alphas:
        mask = attn > (alpha * max_vals)
        ratio = 1.0 - mask.mean()  # fraction of zeros
        sparsities.append((alpha, ratio))
        rows.append((alpha, ratio, val_acc))

    # write CSV
    Path(args.csv_out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.csv_out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(rows)

    # plot
    plt.figure(figsize=(6, 4))
    plt.plot([a for a, _ in sparsities], [s for _, s in sparsities], marker="o")
    plt.xlabel("Alpha (fraction of max attention)")
    plt.ylabel("Sparsity ratio (zeros)")
    plt.title("Attention sparsity vs threshold")
    plt.grid(True, ls="--", alpha=0.5)
    Path(args.plot_out).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(args.plot_out, dpi=200, bbox_inches="tight")

    print(f"Saved CSV to {args.csv_out}")
    print(f"Saved plot to {args.plot_out}")


if __name__ == "__main__":
    main()
