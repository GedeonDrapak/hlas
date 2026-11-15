# Favicons and Open Graph images for hlas.dev.
# Run: ~/Developer/video-use/.venv/bin/python web/_src/make_icons.py  (needs Pillow)
# Writes web/favicon.svg, favicon.ico, apple-touch-icon.png, icon-512.png,
# assets/og.jpg (English) and assets/og-cs.jpg (Czech and Slovak pages).
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

WEB = Path(__file__).resolve().parents[1]
FONTS = WEB / "assets" / "fonts"
BG, GREEN, WHITE = (18, 18, 18), (0, 230, 122), (237, 237, 237)

# The Hlas mark (the same path as Resources/Brand/hlas-icon.svg and the app icon), green on a dark rounded tile.
MARK_D = "M478 328C435 328 401 362 401 405V850C401 893 435 927 478 927C521 927 556 893 556 850V711C556 673 580 643 616 643H660C692 643 715 667 715 699V738C715 776 745 806 783 806C821 806 851 776 851 738V523C851 485 821 455 783 455C745 455 715 485 715 523V557C715 588 692 611 661 611H612C580 611 556 586 556 554V405C556 362 521 328 478 328Z"
MARK_H = 28 / 599  # mark height on the 48 unit tile
SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<rect width="48" height="48" rx="11" fill="#121212"/>
<path fill="#00E67A" transform="translate({24 - 626 * MARK_H:.3f} {24 - 627.5 * MARK_H:.3f}) scale({MARK_H:.5f})" d="{MARK_D}"/>
</svg>
"""


def mark_points() -> list[tuple[float, float]]:
    """The mark outline as a polygon in source units (curves sampled)."""
    import re
    tok = re.findall(r"[MCVHZ]|-?\d+(?:\.\d+)?", MARK_D)
    pts, i, cur = [], 0, (0.0, 0.0)
    while i < len(tok):
        c = tok[i]; i += 1
        if c == "M":
            cur = (float(tok[i]), float(tok[i + 1])); i += 2; pts.append(cur)
        elif c == "V":
            cur = (cur[0], float(tok[i])); i += 1; pts.append(cur)
        elif c == "H":
            cur = (float(tok[i]), cur[1]); i += 1; pts.append(cur)
        elif c == "C":
            p1 = (float(tok[i]), float(tok[i + 1])); p2 = (float(tok[i + 2]), float(tok[i + 3])); p3 = (float(tok[i + 4]), float(tok[i + 5])); i += 6
            for k in range(1, 25):
                s = k / 24; m = 1 - s
                pts.append((m ** 3 * cur[0] + 3 * m * m * s * p1[0] + 3 * m * s * s * p2[0] + s ** 3 * p3[0],
                            m ** 3 * cur[1] + 3 * m * m * s * p1[1] + 3 * m * s * s * p2[1] + s ** 3 * p3[1]))
            cur = p3
    return pts


def mark(size: int, tile: bool = True) -> Image.Image:
    s = size * 4  # draw large, downscale for smooth edges
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = s / 48
    if tile:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=11 * u, fill=BG)
    k = MARK_H * u
    d.polygon([((x - 626) * k + s / 2, (y - 627.5) * k + s / 2) for x, y in mark_points()], fill=GREEN)
    return im.resize((size, size), Image.LANCZOS)


def og(path: Path, headline: list[str], sub: str) -> None:
    W, H = 1200, 630
    photo = Image.open(WEB / "assets" / "hero.jpg").convert("RGB")
    scale = W / photo.width
    photo = photo.resize((W, round(photo.height * scale)), Image.LANCZOS)
    # Mostly sky: start near the top of the photo so only the hill crests show at the bottom.
    top = 40
    im = photo.crop((0, top, W, top + H))
    veil = Image.new("RGBA", (W, H))
    vd = ImageDraw.Draw(veil)
    for y in range(H):  # dark top for the text, photo shows below
        a = int(235 * max(0.0, 1 - y / (H * 0.98)) ** 0.6)
        vd.line((0, y, W, y), fill=(14, 14, 14, a))
    im = Image.alpha_composite(im.convert("RGBA"), veil)
    d = ImageDraw.Draw(im)
    bold = ImageFont.truetype(str(FONTS / "Satoshi-Bold.otf"), 64)
    med = ImageFont.truetype(str(FONTS / "Satoshi-Medium.otf"), 28)
    word = ImageFont.truetype(str(FONTS / "Satoshi-Bold.otf"), 30)
    im.alpha_composite(mark(64), (72, 64))
    d.text((150, 80), "HLAS", font=word, fill=WHITE, spacing=0)
    y = 190
    for line in headline:
        d.text((72, y), line, font=bold, fill=WHITE)
        y += 76
    d.text((74, y + 18), sub, font=med, fill=(205, 205, 205))
    d.text((W - 72, 80), "hlas.dev", font=med, fill=(205, 205, 205), anchor="ra")
    im.convert("RGB").save(path, "JPEG", quality=88, optimize=True, progressive=True)


(WEB / "favicon.svg").write_text(SVG)
mark(256).save(WEB / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
apple = Image.new("RGB", (180, 180), BG)  # iOS adds its own rounding
apple.paste(mark(180, tile=False), (0, 0), mark(180, tile=False))
apple.save(WEB / "apple-touch-icon.png")
mark(512).save(WEB / "icon-512.png")
og(WEB / "assets" / "og.jpg", ["Dictation for Mac and Windows", "that just works."],
   "Hold Fn, speak, release. 4 MB app, works offline.")
og(WEB / "assets" / "og-cs.jpg", ["Diktování pro Mac a Windows,", "které umí česky."],
   "Podrž Fn, mluv, pusť. 4 MB aplikace, funguje i offline.")
print("icons and og images written")
