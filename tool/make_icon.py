#!/usr/bin/env python3
"""Draw the app icon and write every size Android and the web need.

Vector-ish, drawn at 4x and downsampled, so the edges stay clean at 48px. Run
after changing anything here:

    python3 tool/make_icon.py
"""

import math
import os
from PIL import Image, ImageDraw

# Palette, matching lib/ui/theme.dart.
DEEP = (14, 26, 34)
SEA_DARK = (24, 74, 96)
SEA = (46, 122, 147)
SAIL = (242, 231, 209)
SAIL_SHADE = (206, 191, 165)
HULL = (122, 84, 48)
HULL_DARK = (86, 58, 33)
MAST = (74, 56, 38)
BRASS = (217, 164, 65)


def draw_icon(size: int, *, bg: bool = True, inset: float = 0.0) -> Image.Image:
    """Render at 4x then downsample, which is what keeps the rigging crisp."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if bg:
        # A deep sea-to-night gradient, drawn as horizontal bands.
        for y in range(s):
            t = y / s
            c = (
                int(DEEP[0] + (SEA_DARK[0] - DEEP[0]) * t),
                int(DEEP[1] + (SEA_DARK[1] - DEEP[1]) * t),
                int(DEEP[2] + (SEA_DARK[2] - DEEP[2]) * t),
            )
            d.line([(0, y), (s, y)], fill=c)

    # Everything below is in 0..1 units of the icon, then scaled — so the
    # adaptive foreground can be drawn inset without redoing the geometry.
    def P(x, y):
        k = 1.0 - inset * 2
        return (s * (inset + x * k), s * (inset + y * k))

    # --- Sails -------------------------------------------------------------
    # A sail is a triangle whose trailing edge bellies away from the mast:
    # head at the top of the mast, foot along the boom, leech curved by the
    # wind. Bulging both edges just makes an oval, which is what a blob is.
    def sail(head, foot_x, foot_y, belly, fill):
        pts = [P(*head)]
        for i in range(1, 25):
            t = i / 24
            # Quadratic Bezier from head to clew, pulled out by `belly`.
            cx = head[0] + belly
            cy = head[1] + (foot_y - head[1]) * 0.45
            x = (1 - t) ** 2 * head[0] + 2 * (1 - t) * t * cx + t**2 * foot_x
            y = (1 - t) ** 2 * head[1] + 2 * (1 - t) * t * cy + t**2 * foot_y
            pts.append(P(x, y))
        pts.append(P(head[0], foot_y))  # back along the boom to the mast
        d.polygon(pts, fill=fill)

    # Mainsail to starboard, foresail to port and a little smaller.
    sail((0.50, 0.13), 0.78, 0.585, belly=0.26, fill=SAIL)
    sail((0.485, 0.25), 0.24, 0.585, belly=-0.20, fill=SAIL_SHADE)

    # --- Mast --------------------------------------------------------------
    mw = 0.016
    d.polygon(
        [P(0.50 - mw, 0.11), P(0.50 + mw, 0.11), P(0.50 + mw, 0.63), P(0.50 - mw, 0.63)],
        fill=MAST,
    )

    # --- Hull --------------------------------------------------------------
    hull = [
        P(0.20, 0.62),
        P(0.80, 0.62),
        P(0.71, 0.78),
        P(0.29, 0.78),
    ]
    d.polygon(hull, fill=HULL)
    # Shadowed underside.
    d.polygon([P(0.29, 0.78), P(0.71, 0.78), P(0.685, 0.815), P(0.315, 0.815)],
              fill=HULL_DARK)
    # A brass strake along the gunwale.
    d.polygon(
        [P(0.20, 0.62), P(0.80, 0.62), P(0.792, 0.655), P(0.208, 0.655)],
        fill=BRASS,
    )

    # --- Water -------------------------------------------------------------
    for i, (y, amp, alpha) in enumerate([(0.855, 0.016, 235), (0.915, 0.013, 170)]):
        pts = []
        for k in range(49):
            t = k / 48
            pts.append(P(0.06 + t * 0.88, y + math.sin(t * math.pi * 3 + i) * amp))
        d.line(pts, fill=SEA + (alpha,), width=max(2, int(s * 0.022)), joint="curve")

    return img.resize((size, size), Image.LANCZOS)


ROOT = os.path.join(os.path.dirname(__file__), "..")

ANDROID = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Adaptive foregrounds are 108dp with only the middle 72dp guaranteed visible,
# so the ship is drawn inset to survive whatever mask the launcher applies.
ADAPTIVE = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def main() -> None:
    for density, px in ANDROID.items():
        out = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{density}")
        os.makedirs(out, exist_ok=True)
        draw_icon(px).save(os.path.join(out, "ic_launcher.png"))

    for density, px in ADAPTIVE.items():
        out = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{density}")
        os.makedirs(out, exist_ok=True)
        draw_icon(px, bg=False, inset=0.22).save(
            os.path.join(out, "ic_launcher_foreground.png")
        )

    web = os.path.join(ROOT, "web")
    os.makedirs(os.path.join(web, "icons"), exist_ok=True)
    draw_icon(512).save(os.path.join(web, "icons", "Icon-512.png"))
    draw_icon(192).save(os.path.join(web, "icons", "Icon-192.png"))
    draw_icon(512, bg=False, inset=0.10).save(
        os.path.join(web, "icons", "Icon-maskable-512.png")
    )
    draw_icon(192, bg=False, inset=0.10).save(
        os.path.join(web, "icons", "Icon-maskable-192.png")
    )
    draw_icon(32).save(os.path.join(web, "favicon.png"))

    # The Play Store listing wants a 512 square, and a feature graphic.
    store = os.path.join(ROOT, "store")
    os.makedirs(store, exist_ok=True)
    draw_icon(512).save(os.path.join(store, "play-icon-512.png"))
    print("icons written")


if __name__ == "__main__":
    main()
