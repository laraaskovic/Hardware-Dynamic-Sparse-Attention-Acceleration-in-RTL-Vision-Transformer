"""
Baseline training script for a small Vision Transformer on CIFAR-10.
Outputs:
  - model checkpoint (.pt)
  - validation accuracy report
Use --log-attn to emit attention weights during evaluation (saved as .npz).
"""

import argparse
import math
import os
from pathlib import Path
from typing import List, Tuple

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
from tqdm import tqdm


# -------------------------
# Model components
# -------------------------


class ViTEncoderLayer(nn.Module):
    """Transformer encoder layer that always returns attention weights."""

    def __init__(self, dim: int, num_heads: int, mlp_ratio: float = 4.0, dropout: float = 0.1):
        super().__init__()
        self.norm1 = nn.LayerNorm(dim)
        self.attn = nn.MultiheadAttention(dim, num_heads, dropout=dropout, batch_first=True)
        self.norm2 = nn.LayerNorm(dim)
        hidden = int(dim * mlp_ratio)
        self.mlp = nn.Sequential(
            nn.Linear(dim, hidden),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden, dim),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        # MultiheadAttention with need_weights=True returns (B, heads, seq, seq)
        attn_input = self.norm1(x)
        attn_out, attn_weights = self.attn(attn_input, attn_input, attn_input, need_weights=True)
        x = x + attn_out
        x = x + self.mlp(self.norm2(x))
        return x, attn_weights


class SmallViT(nn.Module):
    """Compact ViT suitable for CIFAR-10."""

    def __init__(
        self,
        image_size: int = 32,
        patch_size: int = 4,
        in_channels: int = 3,
        num_classes: int = 10,
        dim: int = 128,
        depth: int = 4,
        num_heads: int = 4,
        mlp_ratio: float = 4.0,
        dropout: float = 0.1,
    ):
        super().__init__()
        assert image_size % patch_size == 0, "image dimensions must be divisible by the patch size"
        num_patches = (image_size // patch_size) ** 2
        self.patch_embed = nn.Conv2d(in_channels, dim, kernel_size=patch_size, stride=patch_size)
        self.cls_token = nn.Parameter(torch.zeros(1, 1, dim))
        self.pos_embed = nn.Parameter(torch.zeros(1, num_patches + 1, dim))
        self.pos_drop = nn.Dropout(dropout)
        self.layers = nn.ModuleList(
            [ViTEncoderLayer(dim, num_heads, mlp_ratio=mlp_ratio, dropout=dropout) for _ in range(depth)]
        )
        self.norm = nn.LayerNorm(dim)
        self.head = nn.Linear(dim, num_classes)
        self._init_weights()

    def _init_weights(self):
        nn.init.trunc_normal_(self.pos_embed, std=0.02)
        nn.init.trunc_normal_(self.cls_token, std=0.02)
        for m in self.modules():
            if isinstance(m, nn.Linear):
                nn.init.trunc_normal_(m.weight, std=0.02)
                if m.bias is not None:
                    nn.init.zeros_(m.bias)
            if isinstance(m, nn.LayerNorm):
                nn.init.ones_(m.weight)
                nn.init.zeros_(m.bias)

    def forward(self, x: torch.Tensor, return_attn: bool = False) -> Tuple[torch.Tensor, List[torch.Tensor]]:
        B = x.size(0)
        x = self.patch_embed(x)  # (B, dim, H', W')
        x = x.flatten(2).transpose(1, 2)  # (B, num_patches, dim)
        cls_tokens = self.cls_token.expand(B, -1, -1)  # (B, 1, dim)
        x = torch.cat((cls_tokens, x), dim=1)
        x = x + self.pos_embed
        x = self.pos_drop(x)

        attn_list = []
        for layer in self.layers:
            x, attn = layer(x)
            if return_attn:
                attn_list.append(attn.detach())

        x = self.norm(x)
        logits = self.head(x[:, 0])  # use CLS token
        return logits, attn_list


# -------------------------
# Data
# -------------------------


def build_dataloaders(batch_size: int, num_workers: int = 4):
    mean = (0.4914, 0.4822, 0.4465)
    std = (0.2023, 0.1994, 0.2010)
    train_tf = transforms.Compose(
        [
            transforms.RandomCrop(32, padding=4),
            transforms.RandomHorizontalFlip(),
            transforms.ToTensor(),
            transforms.Normalize(mean, std),
        ]
    )
    test_tf = transforms.Compose(
        [
            transforms.ToTensor(),
            transforms.Normalize(mean, std),
        ]
    )
    train_ds = datasets.CIFAR10(root="data", train=True, download=True, transform=train_tf)
    test_ds = datasets.CIFAR10(root="data", train=False, download=True, transform=test_tf)
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=num_workers, pin_memory=True)
    test_loader = DataLoader(test_ds, batch_size=batch_size, shuffle=False, num_workers=num_workers, pin_memory=True)
    return train_loader, test_loader


# -------------------------
# Training / eval
# -------------------------


def train_one_epoch(model, loader, optimizer, device, scaler, criterion):
    model.train()
    total_loss = 0.0
    for images, labels in tqdm(loader, desc="Train", leave=False):
        images, labels = images.to(device), labels.to(device)
        optimizer.zero_grad()
        with torch.cuda.amp.autocast(enabled=scaler is not None):
            logits, _ = model(images, return_attn=False)
            loss = criterion(logits, labels)
        if scaler:
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()
        else:
            loss.backward()
            optimizer.step()
        total_loss += loss.item() * images.size(0)
    return total_loss / len(loader.dataset)


def evaluate(model, loader, device, record_attn: bool = False, max_batches: int = None):
    model.eval()
    correct = 0
    total = 0
    attn_records = []
    with torch.no_grad():
        for b_idx, (images, labels) in enumerate(tqdm(loader, desc="Eval", leave=False)):
            images, labels = images.to(device), labels.to(device)
            logits, attn_list = model(images, return_attn=record_attn)
            pred = logits.argmax(dim=1)
            correct += (pred == labels).sum().item()
            total += labels.size(0)

            if record_attn:
                attn_records.append([a.cpu() for a in attn_list])

            if max_batches is not None and b_idx + 1 >= max_batches:
                break
    acc = correct / total
    return acc, attn_records


# -------------------------
# Attention logging helpers
# -------------------------


def stack_attn(attn_batches: List[List[torch.Tensor]]) -> np.ndarray:
    """
    attn_batches: list over batches, each element is list over layers of tensors (B, heads, seq, seq)
    Returns numpy array shape (num_samples, num_layers, heads, seq, seq)
    """
    per_layer: List[List[torch.Tensor]] = []
    # transpose dimensions to layer-major
    num_layers = len(attn_batches[0])
    for layer_idx in range(num_layers):
        layer_tensors = [batch[layer_idx] for batch in attn_batches]  # list of (B, H, S, S)
        per_layer.append(torch.cat(layer_tensors, dim=0))
    stacked = torch.stack(per_layer, dim=1)  # (N, L, H, S, S)
    return stacked.numpy()


# -------------------------
# CLI
# -------------------------


def parse_args():
    p = argparse.ArgumentParser(description="Train small ViT on CIFAR-10 and optionally log attention.")
    p.add_argument("--epochs", type=int, default=20)
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--weight-decay", type=float, default=0.05)
    p.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu")
    p.add_argument("--save", type=str, default="checkpoints/vit_tiny.pt")
    p.add_argument("--log-attn", action="store_true", help="Record attention weights on the validation set.")
    p.add_argument("--log-max-batches", type=int, default=10, help="Limit batches when logging attention (None for all).")
    p.add_argument("--num-workers", type=int, default=4)
    return p.parse_args()


def main():
    args = parse_args()
    device = torch.device(args.device)
    os.makedirs(Path(args.save).parent, exist_ok=True)

    train_loader, test_loader = build_dataloaders(args.batch_size, args.num_workers)
    model = SmallViT().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scaler = torch.cuda.amp.GradScaler() if device.type == "cuda" else None

    best_acc = 0.0
    for epoch in range(args.epochs):
        loss = train_one_epoch(model, train_loader, optimizer, device, scaler, criterion)
        val_acc, _ = evaluate(model, test_loader, device, record_attn=False)
        tqdm.write(f"Epoch {epoch+1}: loss={loss:.4f}, val_acc={val_acc:.4f}")
        if val_acc > best_acc:
            best_acc = val_acc
            torch.save({"model_state": model.state_dict(), "val_acc": val_acc}, args.save)
            tqdm.write(f"  Saved checkpoint to {args.save}")

    # Optional attention logging after training
    if args.log_attn:
        val_acc, attn_records = evaluate(model, test_loader, device, record_attn=True, max_batches=args.log_max_batches)
        attn_np = stack_attn(attn_records)
        out_path = Path(args.save).with_suffix(".attn.npz")
        np.savez_compressed(out_path, attn=attn_np, val_acc=val_acc)
        tqdm.write(f"Saved attention weights to {out_path} with shape {attn_np.shape}")


if __name__ == "__main__":
    main()
