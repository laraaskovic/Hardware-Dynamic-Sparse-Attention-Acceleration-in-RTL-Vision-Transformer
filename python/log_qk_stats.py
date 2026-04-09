"""
Compute Q/K magnitude statistics to validate fixed-point ranges.

Loads a trained checkpoint, runs a few batches of CIFAR-10, and logs:
- max |q|, |k|
- 99.9th percentile |q|, |k|
- L1 sums per token (max, p99.9)

Outputs a JSON to docs/phase1_qk_stats.json by default.
"""

import argparse
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from tqdm import tqdm

from baseline_vit import SmallViT, build_dataloaders


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", required=True, help="Path to checkpoint .pt")
    p.add_argument("--batches", type=int, default=10, help="Number of test batches to sample")
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--num-workers", type=int, default=4)
    p.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu")
    p.add_argument("--out", type=str, default="docs/phase1_qk_stats.json")
    return p.parse_args()


@torch.no_grad()
def main():
    args = parse_args()
    device = torch.device(args.device)
    _, test_loader = build_dataloaders(args.batch_size, args.num_workers)

    ckpt = torch.load(args.ckpt, map_location=device)
    model = SmallViT().to(device)
    model.load_state_dict(ckpt["model_state"])
    model.eval()

    # Collect stats
    abs_q = []
    abs_k = []
    l1_q = []
    l1_k = []

    batches = 0
    for images, _ in tqdm(test_loader, desc="QK stats"):
        images = images.to(device)
        B = images.size(0)

        # forward through patch embed + cls + pos
        x = model.patch_embed(images).flatten(2).transpose(1, 2)
        cls = model.cls_token.expand(B, -1, -1)
        x = torch.cat((cls, x), dim=1)
        x = model.pos_drop(x + model.pos_embed)

        for layer in model.layers:
            x_norm = layer.norm1(x)
            # Use PyTorch internal projection helper to get q,k
            q, k, _ = F._in_projection_packed(
                x_norm, x_norm, x_norm, layer.attn.in_proj_weight, layer.attn.in_proj_bias
            )
            # reshape to (B, seq, num_heads, head_dim)
            num_heads = layer.attn.num_heads
            head_dim = layer.attn.head_dim
            q = q.view(B, -1, num_heads, head_dim)
            k = k.view(B, -1, num_heads, head_dim)

            abs_q.append(q.abs().flatten().cpu())
            abs_k.append(k.abs().flatten().cpu())

            l1_q.append(q.abs().sum(dim=-1).flatten().cpu())  # per token per head
            l1_k.append(k.abs().sum(dim=-1).flatten().cpu())

            # continue standard layer forward
            attn_out, _ = layer.attn(x_norm, x_norm, x_norm, need_weights=False)
            x = x + attn_out
            x = x + layer.mlp(layer.norm2(x))

        batches += 1
        if batches >= args.batches:
            break

    def summarize(tensors):
        concat = torch.cat(tensors)
        return {
            "max": float(concat.max()),
            "p99.9": float(torch.quantile(concat, torch.tensor(0.999))),
            "p99": float(torch.quantile(concat, torch.tensor(0.99))),
        }

    stats = {
        "abs_q": summarize(abs_q),
        "abs_k": summarize(abs_k),
        "l1_q": summarize(l1_q),
        "l1_k": summarize(l1_k),
        "batches": batches,
        "batch_size": args.batch_size,
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(stats, f, indent=2)

    print(f"Saved Q/K stats to {out_path}")
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
