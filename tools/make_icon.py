#!/usr/bin/env python3
"""Generate MacView's AppIcon.iconset deterministically from code.

Follows the macOS icon conventions that bit other apps in this fleet:
  * rounded-rect plate at the **0.2249** corner-radius ratio (not a superellipse),
  * ~100px margin on a 1024 canvas (plate ~= 824px),
  * a flat near-black plate with at most a gentle top->bottom gradient — never a
    lighter perimeter ring (which reads as a gray band),
  * artwork centered.

Re-running leaves `git diff` empty. build.sh turns the iconset into AppIcon.icns
via iconutil. Requires Pillow (`pip3 install pillow`).
"""
import os
from PIL import Image, ImageDraw

CANVAS = 1024
MARGIN = 100
PLATE = CANVAS - 2 * MARGIN              # 824
RADIUS = round(0.2249 * PLATE)           # ~185 — the macOS standard ratio
SS = 4                                    # supersample for crisp anti-aliasing


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded_mask(w, h, radius):
    m = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1],
                                        radius=radius * SS, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def render_master():
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Plate: flat near-black, subtle top->bottom gradient only.
    plate = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(plate)
    top, bottom = (30, 32, 38), (14, 15, 18)
    for y in range(PLATE):
        pdraw.line([(0, y), (PLATE, y)], fill=lerp(top, bottom, y / PLATE) + (255,))
    img.paste(plate, (MARGIN, MARGIN), rounded_mask(PLATE, PLATE, RADIUS))

    # Inner "photo" viewport with a sky gradient, a sun, and mountains.
    inset = 150
    vx0, vy0 = MARGIN + inset, MARGIN + inset
    vw = CANVAS - 2 * (MARGIN + inset)
    vh = vw
    vp = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
    vpd = ImageDraw.Draw(vp)
    sky_top, sky_bottom = (58, 134, 255), (123, 97, 255)
    for y in range(vh):
        vpd.line([(0, y), (vw, y)], fill=lerp(sky_top, sky_bottom, y / vh) + (255,))

    sun_r = round(vw * 0.13)
    sun_cx, sun_cy = round(vw * 0.30), round(vh * 0.30)
    vpd.ellipse([sun_cx - sun_r, sun_cy - sun_r, sun_cx + sun_r, sun_cy + sun_r],
                fill=(255, 236, 180, 255))

    base = vh
    vpd.polygon([(vw * 0.02, base), (vw * 0.40, vh * 0.52), (vw * 0.72, base)],
                fill=(24, 28, 40, 255))
    vpd.polygon([(vw * 0.40, base), (vw * 0.72, vh * 0.40), (vw * 1.02, base)],
                fill=(40, 46, 66, 255))

    img.paste(vp, (vx0, vy0), rounded_mask(vw, vh, round(0.12 * vw)))
    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.normpath(os.path.join(here, "..", "Resources", "AppIcon.iconset"))
    os.makedirs(out, exist_ok=True)
    master = render_master()
    sizes = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    for name, px in sizes.items():
        master.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
    print(f"✓ wrote {len(sizes)} icons to {out}")


if __name__ == "__main__":
    main()
