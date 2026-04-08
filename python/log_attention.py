"""
Load a trained checkpoint and log attention matrices on the CIFAR-10 test set.
Outputs an .npz with array shape (N, L, H, S, S) where:
  N = number of samples logged
  L = layers
  H = heads
  S = sequence length (1 + num_patches)
"""

import argparse
from pathlib import Path

import numpy as np
import torch
from tqdm import tqdm

from baseline_vit import SmallViT, build_dataloaders, stack_attn


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", type=str, required=True, help="Path to checkpoint .pt")
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--num-workers", type=int, default=4)
    p.add_argument("--max-batches", type=int, default=20, help="Number of test batches to log (None for all)")
    p.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu")
    return p.parse_args()


def main():
    args = parse_args()
    device = torch.device(args.device)
    _, test_loader = build_dataloaders(args.batch_size, args.num_workers)

    ckpt = torch.load(args.ckpt, map_location=device)
    model = SmallViT().to(device)
    model.load_state_dict(ckpt["model_state"])
    model.eval()

    attn_records = []
    correct = total = 0
    with torch.no_grad():
        for b_idx, (images, labels) in enumerate(tqdm(test_loader, desc="LogAttn", leave=False)):
            images, labels = images.to(device), labels.to(device)
            logits, attn = model(images, return_attn=True)
            pred = logits.argmax(dim=1)
            correct += (pred == labels).sum().item()
            total += labels.size(0)
            attn_records.append([a.cpu() for a in attn])
            if args.max_batches is not None and b_idx + 1 >= args.max_batches:
                break

    acc = correct / total
    attn_np = stack_attn(attn_records)
    out_path = Path(args.ckpt).with_suffix(".attn.npz")
    np.savez_compressed(out_path, attn=attn_np, val_acc=acc)
    tqdm.write(f"Saved attention {attn_np.shape} to {out_path}, val_acc={acc:.4f}")


if __name__ == "__main__":
    main()
