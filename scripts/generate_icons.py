#!/usr/bin/env python3
"""Génère toutes les icônes XtremFlow à partir d'un seul dessin vectoriel.

Palette alignée sur lib/core/theme/app_colors.dart (graphite + bleu Apple).

Sorties :
  assets/branding/*.svg                       sources vectorielles
  assets/images/logo_xtremflow.png            logo in-app (fond transparent)
  assets/images/app_icon_ios.png              icône iOS (carré plein, sans alpha)
  android/.../mipmap-*/ic_launcher.png        icône legacy (tuile arrondie)
  android/.../mipmap-*/ic_launcher_round.png  icône legacy ronde
  android/.../drawable-*/ic_launcher_foreground.png  calque adaptatif
  android/.../drawable-xhdpi/banner.png       bannière Android TV / Fire TV

Usage : pip install cairosvg pillow && python3 scripts/generate_icons.py
La bannière utilise la police Inter (Bold) si elle est installée.
"""

import io
import os

import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# Couleurs du thème (app_colors.dart)
BG_TOP = "#2C2C33"  # surfaceContainerLow
BG_BOTTOM = "#1B1B1F"  # baseLevel0
BLUE = "#0A84FF"  # primaryContainer
BLUE_LIGHT = "#8AB9FF"  # primary
CYAN = "#7DD3F2"  # tertiary

DEFS = f"""
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BG_TOP}"/>
      <stop offset="1" stop-color="{BG_BOTTOM}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{BLUE}" stop-opacity="0.35"/>
      <stop offset="1" stop-color="{BLUE}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="play" x1="0.2" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="{CYAN}"/>
      <stop offset="0.55" stop-color="{BLUE}"/>
      <stop offset="1" stop-color="#0A5BD6"/>
    </linearGradient>
    <linearGradient id="streak" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="28" y2="0">
      <stop offset="0" stop-color="{CYAN}" stop-opacity="0"/>
      <stop offset="1" stop-color="{CYAN}" stop-opacity="1"/>
    </linearGradient>
    <linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.07"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>"""


def mark(cx, cy, size):
    """Le symbole : un bouton play fluide précédé de traînées de vitesse.

    Dessiné dans une boîte de 100x100 centrée sur (cx, cy), mise à l'échelle
    à `size` pixels.
    """
    s = size / 100.0
    tx, ty = cx - 50 * s, cy - 50 * s
    return f"""
  <g transform="translate({tx:.2f} {ty:.2f}) scale({s:.4f})">
    <circle cx="56" cy="50" r="50" fill="url(#glow)"/>
    <path d="M40 22 L84 50 L40 78 Z" fill="url(#play)" stroke="url(#play)"
          stroke-width="12" stroke-linejoin="round"/>
    <path d="M44 34 L66 48" stroke="#FFFFFF" stroke-opacity="0.28"
          stroke-width="4" stroke-linecap="round"/>
    <g stroke="url(#streak)" stroke-linecap="round" fill="none">
      <path d="M6 38 L28 38" stroke-width="7"/>
      <path d="M0 50 L28 50" stroke-width="7"/>
      <path d="M10 62 L28 62" stroke-width="7"/>
    </g>
  </g>"""


def svg(w, h, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}">{DEFS}{body}\n</svg>\n'
    )


def tile(size, radius_ratio, mark_ratio=0.64):
    """Tuile graphite (arrondie ou pleine) avec le symbole centré."""
    r = size * radius_ratio
    body = f"""
  <rect width="{size}" height="{size}" rx="{r}" fill="url(#bg)"/>
  <rect width="{size}" height="{size}" rx="{r}" fill="url(#shine)"/>
  <rect x="1.5" y="1.5" width="{size - 3}" height="{size - 3}" rx="{max(r - 1.5, 0)}"
        fill="none" stroke="#FFFFFF" stroke-opacity="0.06" stroke-width="3"/>
  {mark(size / 2, size / 2, size * mark_ratio)}"""
    return svg(size, size, body)


def round_tile(size):
    body = f"""
  <circle cx="{size / 2}" cy="{size / 2}" r="{size / 2}" fill="url(#bg)"/>
  <circle cx="{size / 2}" cy="{size / 2}" r="{size / 2}" fill="url(#shine)"/>
  {mark(size / 2, size / 2, size * 0.62)}"""
    return svg(size, size, body)


def adaptive_foreground(size):
    # 108dp de canevas, zone sûre de 66dp : le symbole occupe ~58% du canevas,
    # soit l'intérieur du cercle sûr quelle que soit la forme du masque.
    return svg(size, size, mark(size / 2, size / 2, size * 0.58))


def banner(w=320, h=180):
    """Bannière TV (Android TV / Fire TV) : 320x180 px en xhdpi."""
    body = f"""
  <rect width="{w}" height="{h}" fill="url(#bg)"/>
  <rect width="{w}" height="{h}" fill="url(#shine)"/>
    {mark(w * 0.25, h / 2, h * 0.56)}
  <text x="{w * 0.44}" y="{h / 2 + 11}" font-family="Inter" font-weight="bold"
        font-size="32" fill="#F5F5F7" letter-spacing="-0.6">Xtrem<tspan fill="{BLUE_LIGHT}">Flow</tspan></text>
  <text x="{w * 0.44 + 1}" y="{h / 2 + 34}" font-family="Inter" font-weight="600"
        font-size="12" fill="#98989F" letter-spacing="2.4">IPTV PLAYER</text>"""
    return svg(w, h, body)


def render(svg_text, out_path, size=None, flatten=None):
    png = cairosvg.svg2png(
        bytestring=svg_text.encode(),
        output_width=size[0] if size else None,
        output_height=size[1] if size else None,
    )
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    if flatten:
        bg = Image.new("RGBA", img.size, flatten)
        bg.alpha_composite(img)
        img = bg.convert("RGB")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    img.save(out_path, optimize=True)
    print("  ", os.path.relpath(out_path, ROOT), img.size)


def main():
    brand = os.path.join(ROOT, "assets", "branding")
    os.makedirs(brand, exist_ok=True)
    sources = {
        "icon_rounded.svg": tile(1024, 0.225),
        "icon_square.svg": tile(1024, 0),
        "icon_round.svg": round_tile(1024),
        "icon_foreground.svg": adaptive_foreground(1024),
        "tv_banner.svg": banner(),
    }
    for name, text in sources.items():
        with open(os.path.join(brand, name), "w") as f:
            f.write(text)

    print("Assets Flutter :")
    render(sources["icon_rounded.svg"], os.path.join(ROOT, "assets/images/logo_xtremflow.png"), (512, 512))
    # iOS applique son propre masque et refuse l'alpha : carré plein.
    render(sources["icon_square.svg"], os.path.join(ROOT, "assets/images/app_icon_ios.png"), (1024, 1024), flatten=BG_BOTTOM)

    print("Android :")
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for d, k in densities.items():
        legacy = round(48 * k)
        fg = round(108 * k)
        render(sources["icon_rounded.svg"], f"{RES}/mipmap-{d}/ic_launcher.png", (legacy, legacy))
        render(sources["icon_round.svg"], f"{RES}/mipmap-{d}/ic_launcher_round.png", (legacy, legacy))
        render(sources["icon_foreground.svg"], f"{RES}/drawable-{d}/ic_launcher_foreground.png", (fg, fg))
    # Bannière TV : 160x90dp -> 320x180 en xhdpi (taille de référence Google/Amazon).
    render(sources["tv_banner.svg"], f"{RES}/drawable-xhdpi/banner.png", (320, 180), flatten=BG_BOTTOM)
    render(sources["tv_banner.svg"], f"{RES}/drawable-xxhdpi/banner.png", (480, 270), flatten=BG_BOTTOM)
    render(sources["tv_banner.svg"], f"{RES}/drawable-xxxhdpi/banner.png", (640, 360), flatten=BG_BOTTOM)
    # Aperçu grand format pour les stores / README.
    render(sources["tv_banner.svg"], os.path.join(brand, "tv_banner_1280x720.png"), (1280, 720), flatten=BG_BOTTOM)


if __name__ == "__main__":
    main()
