"""
Visualize attention heatmaps and sparse masks for a chosen sample/layer/head.

Inputs:
  --npz: path to attention dump (from log_attention.py) with key 'attn'
  --sample: index in the dataset slice (default 0)
  --layer: layer index (default 0)
  --head: head index (default 0)
  --alpha: threshold fraction of max attention for true mask (default 0.1)

Outputs:
  docs/img/attn_s{sample}_l{layer}_h{head}.png
    Subplots: raw attention heatmap, true mask (thresholded), predicted mask using upper-bound proxy, with IoU in title.
"""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def upper_bound_mask(attn_slice: np.ndarray, alpha: float):
    # attn_slice: (S, S)
    max_val = attn_slice.max()
    true_mask = attn_slice > (alpha * max_val)

    row_l1 = np.abs(attn_slice).sum(axis=-1, keepdims=True)  # (S,1)
    col_l1 = np.abs(attn_slice).sum(axis=-2, keepdims=True)  # (1,S)
    upper = row_l1 * col_l1
    ub_max = upper.max()
    ub_mask = upper > (alpha * ub_max)
    return true_mask, ub_mask


def iou(a: np.ndarray, b: np.ndarray):
    inter = np.logical_and(a, b).sum()
    union = np.logical_or(a, b).sum()
    return inter / union if union else 1.0


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--npz", required=True, help="Path to attention npz file")
    p.add_argument("--sample", type=int, default=0)
    p.add_argument("--layer", type=int, default=0)
    p.add_argument("--head", type=int, default=0)
    p.add_argument("--alpha", type=float, default=0.1)
    p.add_argument("--out", type=str, default=None, help="Override output path")
    return p.parse_args()


def main():
    args = parse_args()
    data = np.load(args.npz)
    attn = data["attn"]  # shape (N, L, H, S, S)
    s, l, h = args.sample, args.layer, args.head
    attn_slice = attn[s, l, h]

    true_mask, ub_mask = upper_bound_mask(attn_slice, args.alpha)
    m_iou = iou(true_mask, ub_mask)

    out_path = args.out
    if out_path is None:
        out_path = Path("docs/img") / f"attn_s{s}_l{l}_h{h}.png"
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)

    fig, axs = plt.subplots(1, 3, figsize=(12, 4))
    im0 = axs[0].imshow(attn_slice, cmap="viridis")
    axs[0].set_title("Attention scores")
    fig.colorbar(im0, ax=axs[0], fraction=0.046, pad=0.04)

    axs[1].imshow(true_mask, cmap="Greys")
    axs[1].set_title(f"True mask (alpha={args.alpha})")

    axs[2].imshow(ub_mask, cmap="Greys")
    axs[2].set_title(f"Pred mask (IoU={m_iou:.2f})")

    for ax in axs:
        ax.axis("off")

    plt.tight_layout()
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    print(f"Saved {out_path} (IoU={m_iou:.3f})")


if __name__ == "__main__":
    main()
