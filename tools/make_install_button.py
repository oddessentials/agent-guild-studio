import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

if len(sys.argv) != 2:
    raise SystemExit("Usage: python tools/make_install_button.py <fonts folder>")
FONTS = sys.argv[1]
OUT = ".github/assets"

W, H = 760, 212
PX, PY, PW, PH = 46, 42, 668, 128
CUT = 24
CY = PY + PH / 2
EMBLEM_X = PX + 86
STAMP_X, STAMP_Y = PX + PW - 64, PY + 8
STAMP_RED = "#ff4a3d"

WINDOWS = "M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-12.9-1.801"
APPLE = ("M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 "
         "1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 "
         "3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559"
         "-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052"
         "-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701")


def font(name, weight):
    f = TTFont(os.path.join(FONTS, name))
    if "fvar" in f:
        f = instancer.instantiateVariableFont(f, {"wght": weight})
    return f


def outline(f, text, size, tracking):
    glyphs = f.getGlyphSet()
    cmap = f.getBestCmap()
    scale = size / f["head"].unitsPerEm
    pen = SVGPathPen(glyphs)
    x = 0.0
    for i, ch in enumerate(text):
        name = cmap[ord(ch)]
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        x += glyphs[name].width * scale
        if i < len(text) - 1:
            x += tracking * size
    return pen.getCommands(), x


def chamfer(x, y, w, h, c):
    return (
        f"M{x + c},{y} H{x + w - c} L{x + w},{y + c} V{y + h - c} "
        f"L{x + w - c},{y + h} H{x + c} L{x},{y + h - c} V{y + c} Z"
    )


def svg(theme):
    cinzel = font("cinzel.woff2", 800)
    exo = font("exo2.woff2", 600)
    title, title_w = outline(cinzel, "INSTALL NOW", 47, 0.07)
    sub, sub_w = outline(exo, "AGENT GUILD: STUDIO", 12.5, 0.2)

    logo = 14
    logos_w = logo * 2 + 11
    gap = 16
    text_l = PX + 178
    text_r = PX + PW - 66
    title_x = text_l + (text_r - text_l - title_w) / 2
    sub_x = text_l + (text_r - text_l - sub_w - gap - logos_w) / 2
    sub_y = CY + 40
    logos_x = sub_x + sub_w + gap
    logos_y = sub_y - logo + 2
    divider_x = PX + 160
    stamp_text, stamp_w = outline(font("exo2.woff2", 900), "BETA", 28, 0.12)
    stamp_outer_w = stamp_w + 34
    stamp_outer_h = 46
    stamp_l = STAMP_X - stamp_outer_w / 2
    stamp_t = STAMP_Y - stamp_outer_h / 2

    frame = chamfer(PX, PY, PW, PH, CUT)
    plate = chamfer(PX + 3, PY + 3, PW - 6, PH - 6, CUT - 1.2)
    rim = chamfer(PX + 9, PY + 9, PW - 18, PH - 18, CUT - 3.7)

    if theme == "dark":
        halo = '<path d="{0}" fill="#e8c47c" opacity=".55" filter="url(#halo)"/>'.format(frame)
        drop = '<path d="{0}" fill="#000" opacity=".6" transform="translate(0 8)" filter="url(#drop)"/>'.format(frame)
    else:
        halo = '<path d="{0}" fill="#c99a45" opacity=".35" filter="url(#halo)"/>'.format(frame)
        drop = '<path d="{0}" fill="#1a1206" opacity=".35" transform="translate(0 10)" filter="url(#drop)"/>'.format(frame)

    chevrons = "".join(
        f'<path class="chev c{i}" d="M{PX + PW - 58 + i * 12},{CY - 9} l8,9 l-8,9" />'
        for i in range(3)
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="t">
<title id="t">Install Agent Guild: Studio beta for Windows or macOS</title>
<defs>
  <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff3cf"/><stop offset=".28" stop-color="#f6dc9c"/>
    <stop offset=".55" stop-color="#e8c47c"/><stop offset=".78" stop-color="#b8893d"/>
    <stop offset="1" stop-color="#f1d08a"/>
  </linearGradient>
  <linearGradient id="goldText" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff6dc"/><stop offset=".42" stop-color="#f3d58f"/>
    <stop offset=".62" stop-color="#d9ac5c"/><stop offset="1" stop-color="#a87a32"/>
  </linearGradient>
  <linearGradient id="frameSheen" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#8a6326"/><stop offset=".18" stop-color="#f6dc9c"/>
    <stop offset=".5" stop-color="#c99a45"/><stop offset=".82" stop-color="#f6dc9c"/>
    <stop offset="1" stop-color="#8a6326"/>
  </linearGradient>
  <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1b2029"/><stop offset=".55" stop-color="#0d1015"/>
    <stop offset="1" stop-color="#07090d"/>
  </linearGradient>
  <radialGradient id="aura" cx="{EMBLEM_X}" cy="{CY}" r="190" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#2f6bed" stop-opacity=".46"/>
    <stop offset=".45" stop-color="#2f6bed" stop-opacity=".12"/>
    <stop offset="1" stop-color="#2f6bed" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="core" cx=".5" cy=".38" r=".7">
    <stop offset="0" stop-color="#1c3a78"/><stop offset="1" stop-color="#0a0e18"/>
  </radialGradient>
  <linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#fff2cc" stop-opacity="0"/>
    <stop offset=".5" stop-color="#fff2cc" stop-opacity=".26"/>
    <stop offset="1" stop-color="#fff2cc" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="hair" x1="0" y1="{PY + 18}" x2="0" y2="{PY + PH - 18}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#e8c47c" stop-opacity="0"/>
    <stop offset=".5" stop-color="#e8c47c" stop-opacity=".7"/>
    <stop offset="1" stop-color="#e8c47c" stop-opacity="0"/>
  </linearGradient>
  <filter id="halo" x="-20%" y="-60%" width="140%" height="220%"><feGaussianBlur stdDeviation="14"/></filter>
  <filter id="drop" x="-20%" y="-60%" width="140%" height="220%"><feGaussianBlur stdDeviation="9"/></filter>
  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="engrave" x="-5%" y="-30%" width="110%" height="160%">
    <feDropShadow dx="0" dy="2" stdDeviation="1.4" flood-color="#000" flood-opacity=".85"/>
  </filter>
  <filter id="ink" x="-10%" y="-20%" width="120%" height="140%">
    <feTurbulence type="fractalNoise" baseFrequency=".5" numOctaves="2" seed="7" result="grain"/>
    <feColorMatrix in="grain" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -3.5 3.1" result="wear"/>
    <feComposite in="SourceGraphic" in2="wear" operator="in"/>
  </filter>
  <clipPath id="inside"><path d="{plate}"/></clipPath>
</defs>
<style>
  .sweep {{ animation: sweep 5.5s cubic-bezier(.45,0,.25,1) infinite; }}
  .pulse {{ animation: pulse 2.8s ease-in-out infinite; transform-origin: {EMBLEM_X}px {CY}px; }}
  .orbit {{ animation: spin 18s linear infinite; transform-origin: {EMBLEM_X}px {CY}px; }}
  .chev {{ fill: none; stroke: #e8c47c; stroke-width: 2.4; stroke-linecap: round; stroke-linejoin: round; opacity: .4; animation: chev 1.8s ease-in-out infinite; }}
  .c1 {{ animation-delay: .2s; }} .c2 {{ animation-delay: .4s; }}
  @keyframes sweep {{ 0% {{ transform: translateX(-260px) skewX(-22deg); }} 55%, 100% {{ transform: translateX({PW + 260}px) skewX(-22deg); }} }}
  @keyframes pulse {{ 0%, 100% {{ opacity: .45; transform: scale(.94); }} 50% {{ opacity: .9; transform: scale(1.06); }} }}
  @keyframes spin {{ to {{ transform: rotate(360deg); }} }}
  @keyframes chev {{ 0%, 100% {{ opacity: .35; }} 40% {{ opacity: 1; }} }}
  @media (prefers-reduced-motion: reduce) {{
    .sweep {{ display: none; }} .pulse, .orbit, .chev {{ animation: none; }} .chev {{ opacity: .7; }}
  }}
</style>
{drop}
{halo}
<path d="{frame}" fill="url(#frameSheen)"/>
<path d="{frame}" fill="url(#gold)" opacity=".55"/>
<path d="{plate}" fill="url(#plate)"/>
<g clip-path="url(#inside)">
  <rect x="{PX}" y="{PY}" width="{PW}" height="{PH}" fill="url(#aura)"/>
  <path d="M{PX},{PY + 3.6} H{PX + PW}" stroke="#f6dc9c" stroke-opacity=".35" stroke-width="1"/>
  <rect class="sweep" x="{PX}" y="{PY - 40}" width="150" height="{PH + 80}" fill="url(#sweep)"/>
</g>
<path d="{rim}" fill="none" stroke="#e8c47c" stroke-opacity=".22" stroke-width="1"/>
<circle class="pulse" cx="{EMBLEM_X}" cy="{CY}" r="40" fill="#5b8cff" opacity=".6" filter="url(#glow)"/>
<g class="orbit">
  <ellipse cx="{EMBLEM_X}" cy="{CY}" rx="50" ry="16" fill="none" stroke="url(#gold)" stroke-width="1.3" stroke-opacity=".75" transform="rotate(-24 {EMBLEM_X} {CY})"/>
  <circle cx="{EMBLEM_X + 50 * 0.9135:.2f}" cy="{CY - 50 * 0.4067:.2f}" r="2.6" fill="#fff3cf"/>
</g>
<circle cx="{EMBLEM_X}" cy="{CY}" r="35" fill="url(#gold)"/>
<circle cx="{EMBLEM_X}" cy="{CY}" r="31.5" fill="url(#core)"/>
<circle cx="{EMBLEM_X}" cy="{CY}" r="27.5" fill="none" stroke="#e8c47c" stroke-opacity=".35" stroke-width="1"/>
<path d="M{EMBLEM_X - 5},{CY - 18} H{EMBLEM_X + 5} V{CY - 2} H{EMBLEM_X + 12} L{EMBLEM_X},{CY + 11} L{EMBLEM_X - 12},{CY - 2} H{EMBLEM_X - 5} Z" fill="url(#goldText)" stroke="#fff3cf" stroke-opacity=".5" stroke-width=".8" stroke-linejoin="round"/>
<path d="M{EMBLEM_X - 15},{CY + 14} V{CY + 18} H{EMBLEM_X + 15} V{CY + 14}" fill="none" stroke="url(#goldText)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M{divider_x},{PY + 18} V{PY + PH - 18}" stroke="url(#hair)" stroke-width="1"/>
<path d="M{divider_x - 3},{CY} l3,-3 l3,3 l-3,3 Z" fill="#e8c47c"/>
<g filter="url(#engrave)">
  <path transform="translate({title_x:.2f} {CY + 14})" d="{title}" fill="url(#goldText)"/>
</g>
<path transform="translate({sub_x:.2f} {sub_y})" d="{sub}" fill="#a9b0c4"/>
<g fill="#c8cede" aria-hidden="true">
  <path transform="translate({logos_x:.2f} {logos_y:.2f}) scale({logo / 24})" d="{WINDOWS}"/>
  <path transform="translate({logos_x + logo + 11:.2f} {logos_y:.2f}) scale({logo / 24})" d="{APPLE}"/>
</g>
{chevrons}
<g transform="rotate(-8 {STAMP_X} {STAMP_Y})" filter="url(#ink)" opacity=".95">
  <rect x="{stamp_l:.2f}" y="{stamp_t:.2f}" width="{stamp_outer_w:.2f}" height="{stamp_outer_h}" rx="5" fill="none" stroke="{STAMP_RED}" stroke-width="3.5"/>
  <rect x="{stamp_l + 5:.2f}" y="{stamp_t + 5:.2f}" width="{stamp_outer_w - 10:.2f}" height="{stamp_outer_h - 10}" rx="3" fill="none" stroke="{STAMP_RED}" stroke-width="1.2"/>
  <path transform="translate({STAMP_X - stamp_w / 2:.2f} {STAMP_Y + 10})" d="{stamp_text}" fill="{STAMP_RED}" stroke="{STAMP_RED}" stroke-width=".9"/>
</g>
</svg>
"""


os.makedirs(OUT, exist_ok=True)
for theme in ("dark", "light"):
    path = os.path.join(OUT, f"install-now-{theme}.svg")
    with open(path, "w", encoding="utf-8", newline=chr(10)) as fh:
        fh.write(svg(theme))
    print(path, os.path.getsize(path), "bytes")
