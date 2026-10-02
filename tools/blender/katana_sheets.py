"""Labelled contact sheets of the hero katana previews (assets/previews/hero/<id>.png and
<id>_34.png, rendered by hero_katanas.py) -> assets/previews/hero/sheets/.

Run: python3 tools/blender/katana_sheets.py [preview_dir] [out_dir]
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PREV = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "previews", "hero")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PREV, "sheets")
os.makedirs(OUT, exist_ok=True)

RARITY = {"Common": (150, 150, 150), "Uncommon": (60, 170, 70), "Rare": (40, 130, 230), "Epic": (150, 60, 220),
          "Legendary": (240, 160, 20), "Mythic": (230, 40, 60), "Divine": (240, 90, 220)}


def katanas():
    src = open(os.path.join(ROOT, "src", "shared", "Config", "Katanas.lua")).read()
    out = []
    for m in re.finditer(r'Id = "(\w+)", Name = "([^"]+)", Rarity = "(\w+)".*?Source = "(\w+)"', src):
        out.append(m.groups())
    return out


def font(size, bold=True):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def cell(kid, name, rarity, source, cw=600, ch=660):
    im = Image.new("RGB", (cw, ch), (236, 236, 238))
    d = ImageDraw.Draw(im)
    x = 0
    for suf in ("", "_34"):
        p = os.path.join(PREV, kid + suf + ".png")
        if os.path.exists(p):
            src = Image.open(p).convert("RGB")
            src = src.resize((cw // 2, int(src.height * (cw // 2) / src.width)), Image.LANCZOS)
            im.paste(src.crop((0, 0, cw // 2, ch - 60)), (x, 60))
        x += cw // 2
    col = RARITY.get(rarity, (120, 120, 120))
    d.rectangle((0, 0, cw, 56), fill=col)
    d.text((14, 6), name, fill=(255, 255, 255), font=font(28))
    d.text((cw - 14, 30), "%s  %s" % (rarity, source), fill=(255, 255, 255), font=font(18, False), anchor="ra")
    d.text((14, 36), kid, fill=(255, 255, 255), font=font(14, False))
    return im


def sheet(path, items, cols=4):
    cells = [cell(*it) for it in items]
    cw, ch = cells[0].size
    rows = (len(cells) + cols - 1) // cols
    out = Image.new("RGB", (cols * cw + (cols + 1) * 10, rows * ch + (rows + 1) * 10), (60, 62, 70))
    for i, c in enumerate(cells):
        out.paste(c, (10 + (i % cols) * (cw + 10), 10 + (i // cols) * (ch + 10)))
    out.save(path)
    print("sheet", path, out.size)


def main():
    ks = katanas()
    tier = [k for k in ks if k[3] == "Tier"]
    other = [k for k in ks if k[3] != "Tier"]
    sheet(os.path.join(OUT, "katanas_tier.png"), tier, cols=6)
    sheet(os.path.join(OUT, "katanas_shop_boss.png"), other, cols=6)


main()
