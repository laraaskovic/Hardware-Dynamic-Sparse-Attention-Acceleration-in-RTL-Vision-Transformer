"""
dynasparse_animation.py

Matplotlib + numpy only animation of the DYNASPARSE pipeline.
Styles: dark navy background (#1a1a2e), teal (#00d4aa), amber (#f4a261), muted gray (#444466), white text.
Stages (2–3s each) inspired by 3Blue1Brown flow:
 1) Attention problem grid
 2) What is a block (dot product)
 3) Pre-screener trick (L1 upper bound, threshold, SKIP)
 4) Bitmask formation across grid
 5) Systolic array with gating
 6) Pareto payoff scatter

Usage:
  python dynasparse_animation.py           # play all stages
  python dynasparse_animation.py --stage 3 # jump to stage 3 for debugging
Saves MP4 if ffmpeg is available, otherwise opens an interactive window.
"""

import argparse
import math
import shutil
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import matplotlib.animation as animation
import numpy as np

# Colors / style
BG = "#0f1326"       # deep navy
TEAL = "#00d4aa"     # active
AMBER = "#f4a261"    # highlight
MUTED = "#3b3f5c"    # inactive
WHITE = "#f8f8ff"
# Global font
mpl.rcParams["font.family"] = "DejaVu Sans"
mpl.rcParams["text.color"] = WHITE
mpl.rcParams["axes.labelcolor"] = WHITE
mpl.rcParams["xtick.color"] = WHITE
mpl.rcParams["ytick.color"] = WHITE


def ease(t):
    # smooth sine ease in/out, t in [0,1]
    return 0.5 - 0.5 * math.cos(math.pi * max(0.0, min(1.0, t)))


def stage_dots(ax, stage, total=6):
    ax.clear()
    ax.set_xlim(0, total)
    ax.set_ylim(0, 1)
    ax.axis("off")
    for i in range(total):
        color = TEAL if i < stage else MUTED
        ax.text(i + 0.5, 0.5, "●", ha="center", va="center", color=color, fontsize=14)


class DynasparseAnimator:
    def __init__(self, start_stage=1):
        self.start_stage = start_stage
        self.fig = plt.figure(figsize=(8, 6), facecolor=BG)
        gs = self.fig.add_gridspec(6, 6)
        self.ax = self.fig.add_subplot(gs[0:5, 0:6])
        self.ax_stage = self.fig.add_subplot(gs[5, 0:6])
        self.fig.patch.set_facecolor(BG)
        self.ax.set_facecolor(BG)
        self.ax_stage.set_facecolor(BG)
        for spine in self.ax.spines.values():
            spine.set_visible(False)
        for spine in self.ax_stage.spines.values():
            spine.set_visible(False)
        self.stage_titles = [
            "The attention problem",
            "What is a block?",
            "The pre-screener trick",
            "The bitmask",
            "The systolic array",
            "The Pareto payoff",
        ]
        self.total_stages = len(self.stage_titles)
        # precompute grid coordinates for 8x8
        self.grid_size = 8
        self.grid_boxes = []
        # stage 5 systolic
        self.dim = 4
        self.pe_circles = []
        # stage 6 points
        self.pareto_points = [(0.14, 0.3), (0.41, 0.12), (0.6, 0.03), (0.7, 0.018), (0.9, 0.08)]

    def init_stage(self):
        self.ax.clear()
        self.ax.set_xlim(0, 10)
        self.ax.set_ylim(0, 10)
        self.ax.axis("off")
        self.ax.set_facecolor(BG)

    def draw_title(self, stage_idx, alpha=1.0, subtitle=None):
        self.ax.text(
            0.5,
            9.5,
            f"{stage_idx+1}. {self.stage_titles[stage_idx]}",
            color=WHITE,
            ha="left",
            va="center",
            fontsize=14,
            alpha=alpha,
            weight="bold",
        )
        if subtitle:
            self.ax.text(
                0.5,
                8.9,
                subtitle,
                color=WHITE,
                ha="left",
                va="center",
                fontsize=10,
                alpha=alpha,
            )

    # Stage 1
    def frame_stage1(self, t):
        self.init_stage()
        self.draw_title(0, alpha=ease(t), subtitle="Brute-force dense attention on FPGA: every block, every time.")
        size = self.grid_size
        for i in range(size):
            for j in range(size):
                val = ease(t)
                color = AMBER
                rect = patches.Rectangle(
                    (1 + j * 0.6, 1 + i * 0.6), 0.5, 0.5, facecolor=color, edgecolor=BG, alpha=val
                )
                self.ax.add_patch(rect)
        if t > 0.7:
            self.ax.text(
                1,
                6.5,
                "262,144 dot products for a 512-token sequence",
                color=WHITE,
                fontsize=10,
            )
        if t > 0.85:
            self.ax.add_patch(
                patches.Rectangle((1, 1), 0.5 * size, 0.5 * size, fill=False, edgecolor="red", linewidth=2, alpha=0.6)
            )
            self.ax.text(1, 5.8, "Wasteful compute/energy", color="red", fontsize=12)

    # Stage 2
    def frame_stage2(self, t):
        self.init_stage()
        self.draw_title(1, alpha=ease(t), subtitle="One Q×K block → 8 multiplies + adder tree in hardware.")
        q = np.array([2, -1, 3, -2, 1, -3, 2, 0])
        k = np.array([1, 2, -1, 2, -2, 1, 0, 3])
        for idx, val in enumerate(q):
            self.ax.add_patch(
                patches.Rectangle((1 + idx * 0.8, 6), 0.7, 0.7, facecolor=AMBER, edgecolor=BG)
            )
            self.ax.text(1.35 + idx * 0.8, 6.35, f"{val}", ha="center", va="center", color=BG)
        self.ax.text(0.3, 6.35, "Q", color=WHITE, fontsize=12)
        for idx, val in enumerate(k):
            self.ax.add_patch(
                patches.Rectangle((1 + idx * 0.8, 4.5), 0.7, 0.7, facecolor=AMBER, edgecolor=BG)
            )
            self.ax.text(1.35 + idx * 0.8, 4.85, f"{val}", ha="center", va="center", color=BG)
        self.ax.text(0.3, 4.85, "K", color=WHITE, fontsize=12)
        # connections appearing with time
        max_lines = int(len(q) * ease(t))
        for i in range(max_lines):
            self.ax.plot(
                [1.35 + i * 0.8, 1.35 + i * 0.8],
                [6, 5.2],
                color=WHITE,
                alpha=0.4,
                linewidth=1,
            )
        self.ax.text(1, 3.5, "Dot product = sum of 8 multiplies", color=WHITE, fontsize=12)
        if t > 0.8:
            self.ax.text(1, 2.8, "Expensive per block", color="red", fontsize=12)

    # Stage 3
    def frame_stage3(self, t):
        self.init_stage()
        self.draw_title(2, alpha=ease(t), subtitle="Predict saliency with L1 norms; 2-cycle predictor, no DSPs.")
        q = np.array([2, -1, 3, -2, 1, -3, 2, 0])
        k = np.array([1, 2, -1, 2, -2, 1, 0, 3])
        abs_q = np.abs(q)
        abs_k = np.abs(k)
        # draw abs vectors
        for idx, val in enumerate(abs_q):
            self.ax.add_patch(
                patches.Rectangle((1 + idx * 0.8, 6), 0.7, 0.7, facecolor=TEAL, edgecolor=BG)
            )
            self.ax.text(1.35 + idx * 0.8, 6.35, f"{val}", ha="center", va="center", color=BG)
        self.ax.text(0.3, 6.35, "|Q|", color=WHITE)
        for idx, val in enumerate(abs_k):
            self.ax.add_patch(
                patches.Rectangle((1 + idx * 0.8, 4.5), 0.7, 0.7, facecolor=TEAL, edgecolor=BG)
            )
            self.ax.text(1.35 + idx * 0.8, 4.85, f"{val}", ha="center", va="center", color=BG)
        self.ax.text(0.3, 4.85, "|K|", color=WHITE)
        # sums
        sum_q = abs_q.sum()
        sum_k = abs_k.sum()
        self.ax.add_patch(patches.Rectangle((1, 3), 1.2, 0.6, facecolor=TEAL, alpha=ease(t)))
        self.ax.add_patch(patches.Rectangle((3, 3), 1.2, 0.6, facecolor=TEAL, alpha=ease(t)))
        self.ax.text(1.6, 3.3, f"|Q|₁={sum_q}", color=BG, ha="center")
        self.ax.text(3.6, 3.3, f"|K|₁={sum_k}", color=BG, ha="center")
        self.ax.text(2.4, 2.4, "×", color=WHITE, fontsize=16)
        prod = sum_q * sum_k
        self.ax.add_patch(patches.Rectangle((4.8, 3), 1.6, 0.6, facecolor=AMBER, alpha=ease(t)))
        self.ax.text(5.6, 3.3, f"{prod:.0f}", color=BG, ha="center")
        self.ax.text(1, 1.8, "|Q·K| ≤ |Q|₁ × |K|₁", color=WHITE, fontsize=12)
        self.ax.text(1, 1.2, "Threshold compare → bitmask", color=WHITE, fontsize=10)
        # threshold compare
        thresh = 150
        bar_len = min(prod / (2 * thresh), 1.5)
        self.ax.add_patch(patches.Rectangle((7, 3), bar_len, 0.4, facecolor=AMBER, alpha=0.8))
        self.ax.add_patch(patches.Rectangle((7, 3), 1.5, 0.4, fill=False, edgecolor=WHITE, linestyle="--"))
        if prod < thresh:
            self.ax.text(7, 2.3, "SKIP", color="red", fontsize=14)
        else:
            self.ax.text(7, 2.3, "COMPUTE", color=TEAL, fontsize=14)

    # Stage 4
    def frame_stage4(self, t):
        self.init_stage()
        self.draw_title(3, alpha=ease(t), subtitle="Pre-screener runs ahead of compute: generate bitmask per input.")
        size = self.grid_size
        saved_ratio = ease(t) * 0.7
        teal_count = int(size * size * (1 - saved_ratio))
        # deterministic pattern: diagonal band stays compute
        mask = np.full((size, size), MUTED)
        for i in range(size):
            for j in range(size):
                if abs(i - j) < 2:
                    mask[i, j] = TEAL
        flat = mask.flatten()
        for n in range(size * size):
            i = n // size
            j = n % size
            color = flat[n] if n < teal_count else MUTED
            alpha = ease(t)
            self.ax.add_patch(
                patches.Rectangle((1 + j * 0.6, 1 + i * 0.6), 0.5, 0.5, facecolor=color, edgecolor=BG, alpha=alpha)
            )
        self.ax.text(1, 6.5, f"MACs saved: {int(saved_ratio*100)}%", color=WHITE, fontsize=12)

    # Stage 5
    def frame_stage5(self, t):
        self.init_stage()
        self.draw_title(4, alpha=ease(t), subtitle="valid_mask gates PEs; inactive tiles freeze accumulators.")
        dim = self.dim
        # draw PEs
        for i in range(dim):
            for j in range(dim):
                active = True if (i + j) % 2 == 0 else False
                color = TEAL if active else MUTED
                circ = plt.Circle((2 + j * 1.5, 6 - i * 1.5), 0.6, facecolor=color, edgecolor=BG, alpha=0.9)
                self.ax.add_patch(circ)
                acc = int(10 * ease(t) * (i + j + 1))
                self.ax.text(2 + j * 1.5, 6 - i * 1.5, f"{acc}", color=BG, ha="center", va="center")
        self.ax.text(0.5, 6, "Q stream →", color=WHITE)
        self.ax.text(3, 7.5, "K stream ↓", color=WHITE)
        self.ax.text(6.8, 1.2, "valid_mask=0 → accumulator holds", color=WHITE, fontsize=10)

    # Stage 6
    def frame_stage6(self, t):
        self.init_stage()
        self.draw_title(5, alpha=ease(t))
        self.ax.set_xlim(0, 1)
        self.ax.set_ylim(0, 0.12)
        self.ax.axis("on")
        self.ax.tick_params(colors=WHITE, labelsize=8)
        for spine in self.ax.spines.values():
            spine.set_color(WHITE)
        self.ax.set_facecolor(BG)
        self.ax.set_xlabel("MACs saved (%)", color=WHITE)
        self.ax.set_ylabel("Accuracy loss (%)", color=WHITE)
        alphas = [0.05, 0.1, 0.15, 0.2, 0.3]
        xs = [p[0] for p in self.pareto_points]
        ys = [p[1] for p in self.pareto_points]
        progress = ease(t)
        upto = int(progress * len(xs))
        for i in range(upto):
            self.ax.scatter(xs[i], ys[i], color=AMBER, s=50)
            self.ax.text(xs[i]+0.01, ys[i]+0.002, f"α={alphas[i]:.2f}", color=WHITE, fontsize=8)
        self.ax.text(0.58, 0.025, "70% MACs saved,\n<2% accuracy loss", color=TEAL, fontsize=10)
        self.ax.grid(True, color=MUTED, alpha=0.3)

    def update(self, frame):
        # Each stage lasts stage_frames frames
        stage_frames = 75  # ~2.5s at 30 fps
        stage = (frame // stage_frames) + (self.start_stage - 1)
        local_t = (frame % stage_frames) / stage_frames
        stage = min(stage, self.total_stages - 1)
        if stage == 0:
            self.frame_stage1(local_t)
        elif stage == 1:
            self.frame_stage2(local_t)
        elif stage == 2:
            self.frame_stage3(local_t)
        elif stage == 3:
            self.frame_stage4(local_t)
        elif stage == 4:
            self.frame_stage5(local_t)
        else:
            self.frame_stage6(local_t)
        stage_dots(self.ax_stage, stage + 1, total=self.total_stages)
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=int, default=1, help="Start stage (1-6) for debugging")
    args = parser.parse_args()
    start_stage = max(1, min(6, args.stage))

    animator = DynasparseAnimator(start_stage=start_stage)
    total_frames = (animator.total_stages - start_stage + 1) * 75
    ani = animation.FuncAnimation(
        animator.fig,
        animator.update,
        frames=total_frames,
        interval=1000 / 30,
        blit=False,
        repeat=False,
    )

    if animation.writers.is_available("ffmpeg") and shutil.which("ffmpeg"):
        out = Path("docs/img/dynasparse_pipeline.mp4")
        out.parent.mkdir(parents=True, exist_ok=True)
        ani.save(out, writer="ffmpeg", fps=30, dpi=150)
        print(f"Saved animation to {out}")
    else:
        plt.show()


if __name__ == "__main__":
    main()
