#!/usr/bin/env python3
"""Renders Resonance's app icon (HQ-463) and builds Resources/AppIcon.icns with iconutil.

The figure is a real standing wave: six plane waves crossing at 30 degrees add up to a 12-fold cymatic pattern,
cut by a circular plate, in gold on an indigo-to-violet macOS rounded square. 16 and 32 px use a simpler figure
(16: plate ring and centre; 32: plus a six-petal rose; 64: the wave at twice the wavelength) so they stay crisp.

Usage: python3 scripts/render-icon.py      (needs numpy and Pillow; run from anywhere)
Writes Resources/AppIcon.icns and docs/icon/ (master-1024.png and preview-{16,32,128,512}.png).
"""
import math
import os
import shutil
import subprocess
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Palette
INDIGO_DEEP = np.array([14, 10, 46]) / 255.0     # corners
INDIGO = np.array([34, 22, 92]) / 255.0          # body
VIOLET = np.array([92, 52, 170]) / 255.0         # glow behind the plate
GOLD = np.array([236, 196, 106]) / 255.0         # the wave
GOLD_HOT = np.array([255, 238, 190]) / 255.0     # antinodes, centre


def grid(n):
    """Pixel-centre coordinates in icon units: the 1024 canvas maps to [-512, 512]."""
    c = (np.arange(n) + 0.5) / n * 1024.0 - 512.0
    x, y = np.meshgrid(c, c)
    return x, -y


def squircle_alpha(x, y, px):
    """macOS Big Sur grid: an 824 px rounded square (continuous corners) centred in 1024."""
    half, n = 412.0, 5.0
    d = (np.abs(x) / half) ** n + (np.abs(y) / half) ** n
    edge = (d ** (1.0 / n) - 1.0) * half          # ~signed distance in icon units
    aa = 1024.0 / px                               # one output pixel
    return np.clip(0.5 - edge / aa, 0.0, 1.0)


def mix(a, b, t):
    t = np.clip(t, 0.0, 1.0)[..., None]
    return a * (1.0 - t) + b * t


def background(x, y):
    r = np.hypot(x, y + 40.0) / 560.0
    col = mix(INDIGO, INDIGO_DEEP, (r - 0.35) / 0.75)
    col = mix(col, VIOLET, np.exp(-(r / 0.42) ** 2) * 0.85)
    return col


def line(dist, width, px):
    """Coverage of a stroke `width` icon units wide, at distance `dist` from its centre line."""
    aa = 1024.0 / px
    return np.clip((width / 2.0 - np.abs(dist)) / aa + 0.5, 0.0, 1.0)


PLATE_R = 300.0


def full_figure(x, y, px, wavelength=60.0, stroke=8.0):
    """12-fold standing wave: sum of six plane waves at 0, 30, ... 150 degrees."""
    r = np.hypot(x, y)
    k = 2.0 * math.pi / wavelength
    f = np.zeros_like(x)
    for j in range(6):
        a = j * math.pi / 6.0
        f += np.cos(k * (x * math.cos(a) + y * math.sin(a)))
    f /= 6.0                                       # f in [-1, 1], 1 at the centre
    # Sand gathers on the nodal lines (f == 0): draw them as thin gold strokes, sharpened by the gradient.
    gy, gx = np.gradient(f)
    g = np.hypot(gx, gy) + 1e-6
    dist = np.abs(f) / g * (1024.0 / px)           # distance to the nodal line, icon units
    nodes = line(dist, stroke, px)
    inside = np.clip((PLATE_R - 14.0 - r) / (1024.0 / px), 0.0, 1.0)
    fade = np.clip(1.0 - (r / (PLATE_R - 10.0)) ** 6, 0.0, 1.0) * 0.55 + 0.45
    wave = nodes * inside * fade
    # Antinode glow at the centre and the plate ring.
    halo = np.exp(-(r / (wavelength * 0.55)) ** 2) * 0.9
    ring = line(r - PLATE_R, 16.0, px)
    ring_soft = np.exp(-((r - PLATE_R) / 34.0) ** 2) * 0.25
    return wave, halo, ring, ring_soft


def mid_figure(x, y, px):
    """64 px: the same standing wave at twice the wavelength, so its lines stay apart."""
    return full_figure(x, y, px, wavelength=120.0, stroke=14.0)


def small_figure(x, y, px):
    """32 px: plate ring, six-petal rose r = R|cos 3t|, bright centre."""
    r = np.hypot(x, y)
    t = np.arctan2(y, x)
    R = 240.0
    rose = R * np.abs(np.cos(3.0 * t))
    # distance in radius along the ray is a fair stroke distance away from the centre
    petals = line(r - rose, 46.0, px) * (r < R + 30.0)
    ring = line(r - 330.0, 56.0, px)
    halo = np.exp(-(r / 70.0) ** 2) * 1.0
    return petals, halo, ring, np.zeros_like(r)


def tiny_figure(x, y, px):
    """16 px: only the plate ring and a gold centre: a resonating plate, read at a glance."""
    r = np.hypot(x, y)
    ring = line(r - 310.0, 84.0, px)
    dot = np.clip((110.0 - r) / (1024.0 / px) + 0.5, 0.0, 1.0)
    halo = np.exp(-(r / 90.0) ** 2) * 0.6
    return dot, halo, ring, np.zeros_like(r)


def figure_for(px):
    if px <= 16:
        return tiny_figure
    if px <= 32:
        return small_figure
    if px <= 64:
        return mid_figure
    return full_figure


def render(px, ss=4):
    n = px * ss
    x, y = grid(n)
    col = background(x, y)
    wave, halo, ring, ring_soft = figure_for(px)(x, y, n)
    col = mix(col, GOLD * 0.9 + VIOLET * 0.1, ring_soft)
    col = mix(col, GOLD, np.maximum(wave, ring))
    col = mix(col, GOLD_HOT, halo)
    alpha = squircle_alpha(x, y, n)
    rgba = np.dstack([np.clip(col, 0, 1), alpha])
    # Premultiplied downsample so the edge stays clean.
    rgba[..., :3] *= rgba[..., 3:4]
    rgba = rgba.reshape(px, ss, px, ss, 4).mean(axis=(1, 3))
    a = rgba[..., 3:4]
    rgba[..., :3] = np.where(a > 0, rgba[..., :3] / np.maximum(a, 1e-6), 0)
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def main():
    sizes = {16: None, 32: None, 64: None, 128: None, 256: None, 512: None, 1024: None}
    for px in sizes:
        sizes[px] = render(px, ss=4 if px <= 512 else 2)

    docs = os.path.join(ROOT, "docs", "icon")
    os.makedirs(docs, exist_ok=True)
    sizes[1024].save(os.path.join(docs, "master-1024.png"))
    for px in (16, 32, 128, 512):
        sizes[px].save(os.path.join(docs, f"preview-{px}.png"))

    work = tempfile.mkdtemp()
    iconset = os.path.join(work, "AppIcon.iconset")
    os.makedirs(iconset)
    for base in (16, 32, 128, 256, 512):
        sizes[base].save(os.path.join(iconset, f"icon_{base}x{base}.png"))
        sizes[base * 2].save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
    out = os.path.join(ROOT, "Resources", "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", "-o", out, iconset], check=True)
    shutil.rmtree(work)
    print(out)


if __name__ == "__main__":
    main()
