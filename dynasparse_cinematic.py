"""
DYNASPARSE cinematic animation (3Blue1Brown-inspired) using only matplotlib + numpy.

Controls:
  python dynasparse_cinematic.py           # run interactively
  python dynasparse_cinematic.py --save    # save to dynasparse.mp4 (ffmpeg required)
  python dynasparse_cinematic.py --stage N # play only stage N (1-7) for debugging
"""

import argparse
import math
import shutil
from pathlib import Path

import numpy as np
import matplotlib as mpl
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import matplotlib.animation as animation

# Global style
BG = "#0a0a0f"
ACCENT = "#00ffcc"
WARN = "#ff6b35"
NEUTRAL = "#4a4a6a"
TEXT = "#e8e8f0"
SUBTEXT = "#8888aa"
DOT_INACTIVE = "#2a2a3a"

mpl.rcParams["font.family"] = "DejaVu Sans"

STAGES = [
    "the attention problem",
    "existing solutions: static masks",
    "dynasparse: hardware-native dynamic masks",
    "the magnitude pre-screener",
    "sweeping the attention matrix",
    "the sparse systolic array",
    "the research contribution",
]

# Timing
TRANS_FRAMES = 60   # 2s at 30fps (faster transitions)
HOLD_FRAMES = 80    # ~2.7s hold (tighter pacing)


def ease(t):
    t = max(0.0, min(1.0, t))
    return (1 - math.cos(math.pi * t)) / 2.0


def glow_line(ax, x1, y1, x2, y2, color, alpha=1.0):
    for lw, a in [(8, 0.08 * alpha), (4, 0.15 * alpha), (1.5, 1.0 * alpha)]:
        ax.plot([x1, x2], [y1, y2], color=color, linewidth=lw, alpha=a, solid_capstyle="round")


def glow_text(ax, x, y, s, color, size, alpha=1.0, ha="center", va="center", weight="normal"):
    for a, off in [(0.08 * alpha, 0.05), (0.15 * alpha, 0.02), (alpha, 0.0)]:
        ax.text(
            x,
            y - off,
            s,
            color=color,
            fontsize=size,
            ha=ha,
            va=va,
            alpha=a,
            weight=weight,
        )


def fancy_box(ax, x, y, w, h, face, edge=None, alpha=1.0, text=None, text_color=TEXT, size=10):
    box = patches.FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.05",
        facecolor=face,
        edgecolor=edge if edge else face,
        linewidth=1.0,
        alpha=alpha,
    )
    ax.add_patch(box)
    if text is not None:
        ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", color=text_color, fontsize=size)


class Cinematic:
    def __init__(self, start_stage=1):
        self.start_stage = start_stage
        self.total_stages = len(STAGES)
        self.fig, self.ax = plt.subplots(figsize=(9, 7))
        self.fig.patch.set_facecolor(BG)
        self.ax.set_facecolor(BG)
        self.ax.set_xlim(0, 10)
        self.ax.set_ylim(0, 10)
        self.ax.axis("off")

    # Persistent UI
    def draw_ui(self, frame, stage_idx, total_frames):
        # top-left brand
        self.ax.add_patch(patches.Circle((0.6, 9.4), 0.08, color=ACCENT, alpha=0.9))
        self.ax.text(0.8, 9.4, "DYNASPARSE", color=ACCENT, fontsize=10, ha="left", va="center")
        self.ax.text(0.8, 9.0, "dynamic sparse attention accelerator", color=NEUTRAL, fontsize=8, ha="left", va="center")
        # stage name bottom-center
        self.ax.text(
            5,
            0.4,
            f"stage {stage_idx+1} of {self.total_stages} — {STAGES[stage_idx]}",
            color=SUBTEXT,
            fontsize=9,
            ha="center",
            va="center",
        )
        # progress bar
        progress = (frame) / total_frames
        self.ax.add_patch(patches.Rectangle((0.5, 0.15), 9.0, 0.05, facecolor=DOT_INACTIVE, edgecolor=None, alpha=0.6))
        self.ax.add_patch(
            patches.Rectangle((0.5, 0.15), 9.0 * progress, 0.05, facecolor=ACCENT, edgecolor=None, alpha=0.9)
        )
        # stage dots
        for i in range(self.total_stages):
            cx = 1 + i * 1.2
            color = ACCENT if i <= stage_idx else DOT_INACTIVE
            self.ax.add_patch(patches.Circle((cx, 0.75), 0.12, facecolor=color, edgecolor=None, alpha=0.9))

    # Stage helpers
    def stage1(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        grid = 8
        cell_size = 0.5
        start_x, start_y = 2.2, 3.1
        # title
        glow_text(self.ax, 5, 8.7, "the attention problem", TEXT, 24, alpha=t)
        glow_text(self.ax, 5, 8.0, "every token looks at every other token", SUBTEXT, 14, alpha=t)
        # fill grid row by row
        idx = int(grid * grid * t)
        count = 0
        for i in range(grid):
            for j in range(grid):
                filled = count <= idx
                color = WARN if filled else NEUTRAL
                alpha = ease(min(1, max(0, t * 1.5 - 0.05 * count)))
                fancy_box(self.ax, start_x + j * cell_size, start_y + i * cell_size, cell_size, cell_size, color, alpha=alpha)
                count += 1
        # counter
        macs = min(int(t * grid * grid * 512), grid * grid * 512)
        self.ax.text(7.6, 8.7, f"compute cost: {macs} MACs", color=ACCENT, fontsize=10, ha="left", va="center")
        if t > 0.8:
            glow_text(self.ax, 5, 2.0, r"$O(n^2)$ complexity — 512 tokens = 262{,}144 dot products", WARN, 12)
            glow_text(self.ax, 5, 1.4, "most of this is wasted.", SUBTEXT, 11, ha="center", va="center")

    def stage2(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        grid = 8
        cell_size = 0.5
        start_x, start_y = 2.2, 3.1
        glow_text(self.ax, 5, 8.7, "existing solutions: static masks", TEXT, 22, alpha=t)
        glow_text(self.ax, 5, 8.0, "fixed patterns decided at training time", SUBTEXT, 13, alpha=t)
        # diagonal mask pattern
        for i in range(grid):
            for j in range(grid):
                color = NEUTRAL if abs(i - j) < 2 else WARN
                fancy_box(self.ax, start_x + j * cell_size, start_y + i * cell_size, cell_size, cell_size, color, alpha=0.9)
        glow_text(self.ax, 5, 2.2, "NVIDIA 2:4 sparsity — fixed 50% skip", ACCENT, 11)
        glow_text(self.ax, 5, 1.7, "mask never changes per input", WARN, 11)

    def stage3(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        glow_text(self.ax, 5, 8.7, "dynasparse: hardware-native dynamic masks", ACCENT, 22, alpha=t)
        glow_text(self.ax, 5, 8.0, "the mask is generated per input, in RTL, with zero software", SUBTEXT, 13, alpha=t)
        # left/right panels
        self.ax.add_patch(patches.Rectangle((0.8, 1), 4, 6.5, edgecolor=WARN, facecolor=(0, 0, 0, 0.15), linewidth=1.5))
        self.ax.add_patch(patches.Rectangle((5.2, 1), 4, 6.5, edgecolor=ACCENT, facecolor=(0, 1, 0.8, 0.07), linewidth=1.5))
        glow_text(self.ax, 2.8, 7.1, "traditional", WARN, 12)
        glow_text(self.ax, 7.2, 7.1, "dynasparse", ACCENT, 12)
        # static masks
        grid = 4
        cell = 0.5
        sx, sy = 1.2, 2
        for r in range(3):
            oy = sy + r * 1.5
            for i in range(grid):
                for j in range(grid):
                    color = NEUTRAL if abs(i - j) < 1 else WARN
                    fancy_box(self.ax, sx + j * cell, oy + i * cell, cell, cell, color, alpha=0.8)
            glow_text(self.ax, sx + 1.0, oy - 0.2, "input", SUBTEXT, 8, ha="left")
        # dynamic masks on right
        sx = 5.6
        for r in range(3):
            oy = sy + r * 1.5
            rng = np.random.default_rng(10 + r)
            mask = rng.random((grid, grid)) > 0.6
            for i in range(grid):
                for j in range(grid):
                    color = ACCENT if mask[i, j] else NEUTRAL
                    fancy_box(self.ax, sx + j * cell, oy + i * cell, cell, cell, color, alpha=0.9)
        # equation
        glow_text(self.ax, 7.2, 2.2, r"$|Q \cdot K| \leq \|Q\|_1 \cdot \|K\|_1$", ACCENT, 14)
        glow_text(self.ax, 7.2, 1.6, "if upper bound < threshold → SKIP (no false negatives)", ACCENT, 10)

    def stage4(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        glow_text(self.ax, 5, 8.7, "the magnitude pre-screener", TEXT, 22, alpha=t)
        glow_text(self.ax, 5, 8.0, "2 clock cycles, no multipliers in the predictor", SUBTEXT, 13, alpha=t)
        q = np.array([0.3, -1.2, 0.8, 0.5, -0.6, 1.4, -0.9, 0.2])
        k = np.array([1.1, -0.4, 0.7, -1.1, 0.9, -0.3, 0.5, -0.8])
        # Left: full dot
        glow_text(self.ax, 2.2, 7.0, "full dot product — expensive", WARN, 11, ha="left")
        for idx, val in enumerate(q):
            fancy_box(self.ax, 1 + idx * 0.7, 6, 0.65, 0.5, face=WARN, alpha=0.6, text=f"{val:.1f}", text_color=TEXT)
            fancy_box(self.ax, 1 + idx * 0.7, 5.2, 0.65, 0.5, face=WARN, alpha=0.6, text=f"{k[idx]:.1f}", text_color=TEXT)
            if idx < int(8 * t):
                glow_line(self.ax, 1.3 + idx * 0.7, 5.2, 1.3 + idx * 0.7, 4.6, WARN, alpha=0.6)
        if t > 0.3:
            glow_text(self.ax, 2.2, 4.2, "8 multiplications + adder tree", WARN, 10, ha="left")
        # Right: prescreener
        glow_text(self.ax, 6.2, 7.0, "pre-screener — cheap", ACCENT, 11, ha="left")
        abs_q = np.abs(q)
        abs_k = np.abs(k)
        for idx, val in enumerate(abs_q):
            fancy_box(self.ax, 5.5 + idx * 0.55, 6.0, 0.5, 0.45, face=ACCENT, alpha=0.7, text=f"{val:.1f}", text_color=BG)
            fancy_box(self.ax, 5.5 + idx * 0.55, 5.2, 0.5, 0.45, face=ACCENT, alpha=0.7, text=f"{abs_k[idx]:.1f}", text_color=BG)
        if t > 0.2:
        glow_text(self.ax, 6.0, 4.8, "|Q|₁ and |K|₁ via adders", ACCENT, 10, ha="left")
        glow_text(self.ax, 6.0, 4.3, "compare to threshold", ACCENT, 10, ha="left")
        glow_text(self.ax, 6.0, 3.8, "cycle 1: abs + sum    cycle 2: multiply + compare", SUBTEXT, 9, ha="left")
            if t > 0.5:
                glow_text(self.ax, 6.0, 2.7, "SKIP", WARN, 14)
                glow_text(self.ax, 7.0, 2.7, "COMPUTE", ACCENT, 14)

    def stage5(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        glow_text(self.ax, 5, 8.7, "sweeping the attention matrix", TEXT, 22, alpha=t)
        glow_text(self.ax, 5, 8.0, "pre-screener runs ahead of the datapath", SUBTEXT, 13, alpha=t)
        grid = 8
        cell = 0.5
        sx, sy = 1.5, 2.0
        sweep_x = sx + (grid * cell) * t
        macs_saved = int(70 * t)
        for i in range(grid):
            for j in range(grid):
                compute = (abs(i - j) < 1) or (i + j) % 3 == 0
                color = ACCENT if compute else NEUTRAL
                alpha = 0.9 if (sx + j * cell) < sweep_x else 0.3
                fancy_box(self.ax, sx + j * cell, sy + i * cell, cell, cell, color=color, alpha=alpha)
                if not compute and (sx + j * cell) < sweep_x:
                    self.ax.text(sx + j * cell + cell / 2, sy + i * cell + cell / 2, "×", color=DOT_INACTIVE, ha="center", va="center")
        # sweep line
        glow_line(self.ax, sweep_x, sy, sweep_x, sy + grid * cell, ACCENT, alpha=0.6)
        self.ax.text(7.8, 1.8, f"MACs saved: ~{macs_saved}%", color=ACCENT, fontsize=11)
        if t > 0.7:
            glow_text(self.ax, 5, 1.2, "~70% of MACs eliminated", ACCENT, 14)
            glow_text(self.ax, 5, 0.7, "mask arrives at PE array before data — zero stall cycles", SUBTEXT, 10)

    def stage6(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        glow_text(self.ax, 5, 8.7, "the sparse systolic array", TEXT, 22, alpha=t)
        glow_text(self.ax, 5, 8.0, "valid_mask = 0 → accumulator frozen", SUBTEXT, 13, alpha=t)
        dim = 4
        spacing = 1.5
        start_x, start_y = 2.0, 2.0
        for i in range(dim):
            for j in range(dim):
                compute = (i + j) % 3 == 0
                color = ACCENT if compute else DOT_INACTIVE
                circ = patches.Circle((start_x + j * spacing, start_y + i * spacing), 0.6, facecolor=color, edgecolor=None, alpha=0.9)
                self.ax.add_patch(circ)
                acc = int(10 * (i + j + 1) * t)
                self.ax.text(start_x + j * spacing, start_y + i * spacing, f"{acc}", color=BG, ha="center", va="center")
                if not compute:
                    self.ax.text(start_x + j * spacing, start_y + i * spacing - 0.7, "hold", color=SUBTEXT, ha="center", fontsize=8)
        glow_text(self.ax, 7.5, 2.5, "dense: 16 PEs active\nsparse: ~5 PEs active", SUBTEXT, 10, ha="left")
        glow_text(self.ax, 7.5, 1.3, "SVA: mask=0 → accumulator unchanged", SUBTEXT, 9, ha="left", weight="light")

    def stage7(self, local_f):
        t = ease(local_f / (TRANS_FRAMES + HOLD_FRAMES))
        glow_text(self.ax, 5, 8.7, "the research contribution", TEXT, 22, alpha=t)
        glow_text(self.ax, 5, 8.0, "accuracy vs compute — a tradeoff curve nobody has measured in RTL", SUBTEXT, 13, alpha=t)
        self.ax.set_xlim(0, 10)
        self.ax.set_ylim(0, 10)
        # axes
        self.ax.plot([1, 9], [2, 2], color=SUBTEXT, alpha=0.6, lw=1)
        self.ax.plot([1, 1], [2, 8], color=SUBTEXT, alpha=0.6, lw=1)
        self.ax.text(9.1, 2, "MACs saved (%)", color=TEXT, fontsize=10, ha="right", va="center")
        self.ax.text(1, 8.2, "accuracy loss (%)", color=TEXT, fontsize=10, ha="left", va="center")
        points = [(4.1, 2.5), (5.8, 3.0), (7.0, 3.5), (7.6, 4.1), (9.0, 5.5)]
        labels = ["α=0.05", "α=0.10", "α=0.15", "α=0.20", "α=0.30"]
        for idx, (x, y) in enumerate(points):
            if idx <= int(t * len(points)):
                self.ax.add_patch(patches.Circle((x, y), 0.12, facecolor=ACCENT, edgecolor=None, alpha=0.9))
                self.ax.text(x + 0.2, y + 0.15, labels[idx], color=TEXT, fontsize=9)
        # sweet spot box
        self.ax.add_patch(
            patches.Rectangle((6.0, 2.2), 2.0, 1.8, fill=False, edgecolor=ACCENT, linestyle="--", linewidth=1.2, alpha=0.8)
        )
        self.ax.text(7.0, 4.2, "target operating region", color=ACCENT, fontsize=10, ha="center")
        if t > 0.7:
            glow_text(self.ax, 5, 6.8, "this curve = the paper", ACCENT, 18)
            glow_text(self.ax, 5, 6.0, "first hardware-native dynamic sparse attention pre-screener in RTL", SUBTEXT, 11)

    def draw_stage(self, stage_idx, local_frame):
        self.ax.cla()
        self.ax.set_facecolor(BG)
        self.ax.set_xlim(0, 10)
        self.ax.set_ylim(0, 10)
        self.ax.axis("off")
        if stage_idx == 0:
            self.stage1(local_frame)
        elif stage_idx == 1:
            self.stage2(local_frame)
        elif stage_idx == 2:
            self.stage3(local_frame)
        elif stage_idx == 3:
            self.stage4(local_frame)
        elif stage_idx == 4:
            self.stage5(local_frame)
        elif stage_idx == 5:
            self.stage6(local_frame)
        else:
            self.stage7(local_frame)

    def animate(self, frame, total_frames, stage_frames):
        # Map global frame to stage and local frame
        stage_idx = (frame // stage_frames) + (self.start_stage - 1)
        if stage_idx >= self.total_stages:
            stage_idx = self.total_stages - 1
        local_frame = frame % stage_frames
        self.draw_stage(stage_idx, local_frame)
        self.draw_ui(frame + (self.start_stage - 1) * stage_frames, stage_idx, total_frames)
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=int, default=1, help="Start at stage N (1-7) and play to end of animation")
    parser.add_argument("--save", action="store_true", help="Save to dynasparse.mp4 with ffmpeg writer")
    args = parser.parse_args()

    start_stage = max(1, min(7, args.stage))
    stage_frames = TRANS_FRAMES + HOLD_FRAMES
    total_frames = stage_frames * (len(STAGES) - start_stage + 1)

    cine = Cinematic(start_stage=start_stage)

    ani = animation.FuncAnimation(
        cine.fig,
        lambda f: cine.animate(f, total_frames, stage_frames),
        frames=total_frames,
        interval=1000 / 30,
        blit=False,
        repeat=False,
    )

    if args.save:
        if animation.writers.is_available("ffmpeg") and shutil.which("ffmpeg"):
            out = Path("dynasparse.mp4")
            ani.save(out, writer="ffmpeg", fps=30, dpi=150)
            print(f"Saved to {out}")
        else:
            print("ffmpeg not available; falling back to interactive display")
            plt.show()
    else:
        plt.show()


if __name__ == "__main__":
    main()
