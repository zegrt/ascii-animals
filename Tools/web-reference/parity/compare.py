# Two renders of the same scene, same size: lit pixels, mean luminance, mean absolute difference per channel, the
# best whole-image shift, and the silk-only cells (no blocks).
#   python3 compare.py <original.png> <ours.png> <cell w px> <cell h px> [light]
import sys
import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.int32)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.int32)
cw, ch = int(sys.argv[3]), int(sys.argv[4])
light = len(sys.argv) > 5 and sys.argv[5] == "light"
bg = np.array([247, 246, 243] if light else [0, 0, 0])
for img, name in ((a, "original"), (b, "ours")):
    lit = np.abs(img - bg).sum(2) > 24
    lum = (img * [0.2126, 0.7152, 0.0722]).sum(2)
    print(f"{name}: lit px {lit.sum()}  mean luminance {lum.mean():.3f}")
print(f"mean abs diff {np.abs(a - b).mean():.3f}")
best = min((np.abs(a[20:-20, 20:-20] - np.roll(np.roll(b, dy, 0), dx, 1)[20:-20, 20:-20]).mean(), dx, dy)
           for dy in range(-6, 7) for dx in range(-4, 5))
print(f"best shift dx {best[1]} dy {best[2]} -> {best[0]:.3f}")
if not light:
    la, lb = (np.asarray(Image.open(p).convert("L")).astype(float) for p in sys.argv[1:3])
    H, W = la.shape
    A = la[: H // ch * ch, : W // cw * cw].reshape(H // ch, ch, W // cw, cw)
    B = lb[: H // ch * ch, : W // cw * cw].reshape(H // ch, ch, W // cw, cw)
    sa, sb = (A > 20).sum((1, 3)), (B > 20).sum((1, 3))
    lim = cw * ch * 0.18
    m = (A.max((1, 3)) > 15) & (A.max((1, 3)) < 140) & (sa < lim) & (sb < lim)
    print(f"silk cells {m.sum()}: lit px ours/original {sb[m].sum() / sa[m].sum():.3f}, ink {B.sum((1, 3))[m].sum() / A.sum((1, 3))[m].sum():.3f}")
