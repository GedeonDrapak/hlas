# Favicons and Open Graph images for hlas.dev.
# Run: ~/Developer/video-use/.venv/bin/python web/_src/make_icons.py  (needs Pillow)
# Writes web/favicon.svg, favicon.ico, apple-touch-icon.png, icon-512.png,
# assets/og.jpg (English) and assets/og-cs.jpg (Czech and Slovak pages).
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

WEB = Path(__file__).resolve().parents[1]
FONTS = WEB / "assets" / "fonts"
BG, GREEN, WHITE = (18, 18, 18), (0, 230, 122), (237, 237, 237)

# The mark on a dark rounded tile: on a white Google results page the white
# middle bar of the bare mark would disappear.
SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<rect width="48" height="48" rx="11" fill="#121212"/>
<rect x="11" y="16" width="7" height="16" rx="3.5" fill="#00E67A"/>
<rect x="22" y="10" width="7" height="28" rx="3.5" fill="#EDEDED"/>
<circle cx="36" cy="24" r="3.5" fill="#00E67A"/>
</svg>
"""


def mark(size: int, tile: bool = True) -> Image.Image:
    s = size * 4  # draw large, downscale for smooth edges
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = s / 48
    if tile:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=11 * u, fill=BG)
    d.rounded_rectangle((11 * u, 16 * u, 18 * u, 32 * u), radius=3.5 * u, fill=GREEN)
    d.rounded_rectangle((22 * u, 10 * u, 29 * u, 38 * u), radius=3.5 * u, fill=WHITE)
    d.ellipse((32.5 * u, 20.5 * u, 39.5 * u, 27.5 * u), fill=GREEN)
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
