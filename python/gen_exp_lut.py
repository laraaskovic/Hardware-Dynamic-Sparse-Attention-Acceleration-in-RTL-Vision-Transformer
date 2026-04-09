"""
Generate exponential LUT for softmax_masked.sv
- Range: [-8, 8]
- Step: 1/128 (~0.0078125) -> 2048 entries (addr width 11). We emit 4096 entries to match LUT_ADDR=12, mirroring for simplicity.
- Output format: hex words for Q0.16 fixed point exp(x).
"""

import numpy as np
from pathlib import Path


def main():
    out_path = Path("rtl/lut/exp_lut.mem")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    min_x, max_x = -8.0, 8.0
    step = 1 / 128.0
    xs = np.arange(min_x, max_x, step, dtype=np.float64)
    vals = np.exp(xs)
    scaled = np.clip(np.round(vals * (1 << 16)), 0, (1 << 16) - 1).astype(np.uint32)

    # Pad to 4096 entries
    if len(scaled) < 4096:
        pad = np.full(4096 - len(scaled), scaled[-1], dtype=np.uint32)
        scaled = np.concatenate([scaled, pad])
    elif len(scaled) > 4096:
        scaled = scaled[:4096]

    with out_path.open("w") as f:
        for v in scaled:
            f.write(f"{v:04x}\n")
    print(f"Wrote {len(scaled)} entries to {out_path}")


if __name__ == "__main__":
    main()
