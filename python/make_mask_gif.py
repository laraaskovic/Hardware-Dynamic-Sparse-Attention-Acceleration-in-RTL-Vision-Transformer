"""
Create an animated GIF showing how the prescreener mask changes per input.

Frames: side-by-side attention heatmap and predicted mask for each sample.
Supports attention dumps with shape (N,L,H,S,S) or (N,L,S,S).
"""

import argparse
import io
from pathlib import Path

import imageio.v2 as imageio
import matplotlib.pyplot as plt
import numpy as np


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--npz", required=True, help="Path to attention npz")
    p.add_argument("--layer", type=int, default=0)
    p.add_argument("--head", type=int, default=0)
    p.add_argument("--alpha", type=float, default=0.1)
    p.add_argument("--samples", type=int, default=16, help="Number of samples to animate")
    p.add_argument("--start", type=int, default=0, help="Starting sample index")
    p.add_argument("--out", type=str, default="docs/img/attn_mask_animation.gif")
    return p.parse_args()


def get_slice(attn, s, layer, head):
    if attn.ndim == 5:  # (N,L,H,S,S)
        return attn[s, layer, head]
    elif attn.ndim == 4:  # (N,L,S,S)
        return attn[s, layer]
    else:
        raise ValueError(f"Unexpected attention ndim {attn.ndim}")


def make_frame(attn_slice, alpha):
    max_val = attn_slice.max()
    true_mask = attn_slice > (alpha * max_val)

    row_l1 = np.abs(attn_slice).sum(axis=-1, keepdims=True)
    col_l1 = np.abs(attn_slice).sum(axis=-2, keepdims=True)
    ub = row_l1 * col_l1
    ub_mask = ub > (alpha * ub.max())

    fig, axs = plt.subplots(1, 2, figsize=(6, 3))
    im0 = axs[0].imshow(attn_slice, cmap="viridis")
    axs[0].set_title("Attention")
    axs[0].axis("off")
    plt.colorbar(im0, ax=axs[0], fraction=0.046, pad=0.04)

    axs[1].imshow(ub_mask, cmap="Greys")
    axs[1].set_title("Pred mask")
    axs[1].axis("off")

    plt.tight_layout()
    buf = io.BytesIO()
    plt.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return imageio.imread(buf)


def main():
    args = parse_args()
    data = np.load(args.npz)
    attn = data["attn"]

    frames = []
    for s in range(args.start, min(args.start + args.samples, attn.shape[0])):
        attn_slice = get_slice(attn, s, args.layer, args.head)
        frames.append(make_frame(attn_slice, args.alpha))

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    imageio.mimsave(out_path, frames, fps=2)
    print(f"Saved animation to {out_path} ({len(frames)} frames)")


if __name__ == "__main__":
    main()
