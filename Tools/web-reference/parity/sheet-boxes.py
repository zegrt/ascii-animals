# The numbers webGlyphsMatchChrome pins, from Chrome's glyph sheets (sheet.mjs): per glyph, the ink box (rows and
# columns with coverage > 0.25) and the total ink, in a 12 x 17 cell at 1x and 2x.
#   python3 sheet-boxes.py <dir with sheet-chrome-1x.png and sheet-chrome-2x.png>
import sys
import numpy as np
from PIL import Image

GLYPHS = [":", ";", "t", "%", "S", "X", "8", "#", "@", ".", "'", ",", "`", "o", "-", "*", "·", "¯", "_", "/", "\\", "|", "+", "x", "O", "°", "v", "0"]
for s in (1, 2):
    a = np.asarray(Image.open(f"{sys.argv[1]}/sheet-chrome-{s}x.png").convert("L")).astype(float) / 255
    sw = 12 * s
    out = []
    for g in "|-_¯/*x@O":
        c = a[:, GLYPHS.index(g) * sw:(GLYPHS.index(g) + 1) * sw]
        ys, xs = np.where(c > 0.25)
        out.append(f'("{g}", {ys.min()}, {ys.max()}, {xs.min()}, {xs.max()}, {c.sum():.1f})')
    print(f"{s}: [" + ", ".join(out) + "],")
