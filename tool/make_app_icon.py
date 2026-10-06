"""Draws the HealthGuide app icon and writes every Android launcher size.

The design matches the logo on the Login screen (Figma): a white heart with a pulse
line, on the app's dark green (AppTokens.brandDeep / brandDeepAccent), with a small
orange (AppTokens.cta) pulse dot. Drawn at 4x and scaled down for smooth edges.

    ai_server\\.venv\\Scripts\\python tool\\make_app_icon.py

Writes assets/icon/ (1024 px masters) and android/app/src/main/res/ (legacy icons,
adaptive icon foreground + background colour for Android 8+).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BRAND_DEEP = (5, 78, 74)        # #054E4A
BRAND_ACCENT = (12, 103, 95)    # #0C675F
ON_BRAND_MUTED = (128, 181, 174)  # #80B5AE
CTA = (195, 67, 23)             # #C34317
WHITE = (255, 255, 255)
SS = 4  # supersampling
# Adaptive icons are 108 dp but launchers show the middle ~72 dp and guarantee the middle
# 66 dp: a circle of 0.72 x 0.84 = 61% of the canvas stays inside that safe zone.
ADAPTIVE_SCALE = 0.84


def heart_points(cx, cy, scale, n=400):
    """Classic heart curve, centred, `scale` = half width in px."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x / 16 * scale, cy - y / 16 * scale - scale * 0.08))
    return pts


def draw_mark(size, with_circle=True, mark_scale=1.0):
    """The circle + heart + pulse on a transparent canvas of `size` px."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    if with_circle:
        r = S * 0.36 * mark_scale
        d.ellipse((c - r, c - r, c + r, c + r), fill=BRAND_ACCENT + (255,))
    hs = S * 0.205 * mark_scale  # heart half-width

    # Heart, then the pulse line cut through it in the circle colour.
    heart = Image.new("L", (S, S), 0)
    ImageDraw.Draw(heart).polygon(heart_points(c, c, hs), fill=255)
    img.paste(Image.new("RGBA", (S, S), WHITE + (255,)), (0, 0), heart)

    w = hs * 0.16  # line width
    pulse = [(-1.15, 0.0), (-0.42, 0.0), (-0.22, -0.42), (0.02, 0.48), (0.24, -0.16), (0.36, 0.0), (1.1, 0.0)]
    pts = [(c + x * hs, c + y * hs) for x, y in pulse]
    line = Image.new("L", (S, S), 0)
    ld = ImageDraw.Draw(line)
    ld.line(pts, fill=255, width=int(w), joint="curve")
    for p in pts:  # round the corners and both ends
        ld.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=255)
    # Inside the heart the line is cut out (circle colour); outside it is white on the circle.
    inside = Image.composite(line, Image.new("L", (S, S), 0), heart)
    outside = Image.composite(Image.new("L", (S, S), 0), line, heart)
    img.paste(Image.new("RGBA", (S, S), (BRAND_ACCENT if with_circle else BRAND_DEEP) + (255,)), (0, 0), inside)
    if with_circle:
        circle = Image.new("L", (S, S), 0)
        r = S * 0.36 * mark_scale
        ImageDraw.Draw(circle).ellipse((c - r, c - r, c + r, c + r), fill=255)
        outside = Image.composite(outside, Image.new("L", (S, S), 0), circle)
    img.paste(Image.new("RGBA", (S, S), ON_BRAND_MUTED + (255,)), (0, 0), outside)

    # Orange dot at the end of the pulse: the "live" reading.
    dot = (c + 1.1 * hs, c)
    rd = hs * 0.16
    d.ellipse((dot[0] - rd, dot[1] - rd, dot[0] + rd, dot[1] + rd), fill=CTA + (255,))
    return img.resize((size, size), Image.LANCZOS)


def full_icon(size, radius_frac=0.0):
    """Mark on the dark green square; radius_frac > 0 rounds the corners."""
    S = size * SS
    bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * radius_frac), fill=255)
    # Soft top-left highlight so the flat green is not dull.
    grad = Image.new("RGBA", (S, S), BRAND_DEEP + (255,))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-S * 0.3, -S * 0.3, S * 0.8, S * 0.8), fill=(255, 255, 255, 22))
    grad = Image.alpha_composite(grad, glow.filter(ImageFilter.GaussianBlur(S * 0.12)))
    bg.paste(grad, (0, 0), mask)
    bg = bg.resize((size, size), Image.LANCZOS)
    return Image.alpha_composite(bg, draw_mark(size))


def main():
    out = ROOT / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    full_icon(1024).save(out / "app_icon.png")                       # square master (stores, splash)
    full_icon(1024, 0.22).save(out / "app_icon_rounded.png")         # preview / documents
    # Adaptive icon foreground: 108 dp canvas, the mark kept inside the 66 dp safe zone.
    draw_mark(1024, mark_scale=ADAPTIVE_SCALE).save(out / "app_icon_foreground.png")

    res = ROOT / "android" / "app" / "src" / "main" / "res"
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, px in legacy.items():
        d = res / f"mipmap-{dpi}"
        d.mkdir(exist_ok=True)
        full_icon(px, 0.22).save(d / "ic_launcher.png")
        draw_mark(round(px * 108 / 48), mark_scale=ADAPTIVE_SCALE).save(d / "ic_launcher_foreground.png")
    any_dpi = res / "mipmap-anydpi-v26"
    any_dpi.mkdir(exist_ok=True)
    (any_dpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n', encoding="utf-8")
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#054E4A</color>\n</resources>\n', encoding="utf-8")
    print("icons written to", out, "and", res)


if __name__ == "__main__":
    main()
