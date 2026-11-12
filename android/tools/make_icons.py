"""Kimogram Android launcher icons, built from the iOS icon (Logo.png) and the
transparent mark (mark_full.png).

usage: python3 make_icons.py <Logo.png> <mark_full.png> <bg.png> <out_dir>
Writes res/ files under <out_dir>/TMessagesProj/src/main/res and store/ icons.
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw

logo_p, mark_p, bg_p, out = sys.argv[1:5]
RES = os.path.join(out, 'TMessagesProj/src/main/res')
MARK = Image.open(mark_p).convert('RGBA')
BG = Image.open(bg_p).convert('RGB')          # 1024, Logo.png background without the mark
SCALE, OX, OY = 0.4646, -83, -98             # mark_full -> Logo.png (1024) placement
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def mark_on(size):
    """Mark placed exactly as on the iOS icon, on a transparent size x size canvas."""
    k = size / 1024.0
    w = int(round(MARK.width * SCALE * k)); h = int(round(MARK.height * SCALE * k))
    m = MARK.resize((w, h), Image.LANCZOS)
    c = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c.alpha_composite(m, (int(round(OX * k)), int(round(OY * k))))
    return c


def full_logo(size):
    c = BG.resize((size, size), Image.LANCZOS).convert('RGBA')
    c.alpha_composite(mark_on(size))
    return c


def layer(size, fg):
    """108dp adaptive layer: the 72dp visible part equals the iOS icon."""
    inner = int(round(size * 72 / 108))
    off = (size - inner) // 2
    if fg:
        c = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        c.alpha_composite(mark_on(inner), (off, off))
        return c
    inner_img = np.array(BG.resize((inner, inner), Image.LANCZOS))
    pad = np.pad(inner_img, ((off, size - inner - off), (off, size - inner - off), (0, 0)), mode='edge')
    return Image.fromarray(pad).convert('RGB')


def masked(img, radius_frac):
    S = img.width * 4
    big = img.resize((S, S), Image.LANCZOS)
    mask = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(mask)
    if radius_frac >= 0.5:
        d.ellipse((0, 0, S - 1, S - 1), fill=255)
    else:
        d.rounded_rectangle((0, 0, S - 1, S - 1), int(S * radius_frac), fill=255)
    big.putalpha(mask)
    return big.resize((img.width, img.height), Image.LANCZOS)


def save(img, rel):
    p = os.path.join(RES, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)


for name, k in DENS.items():
    L = int(round(108 * k)); I = int(round(48 * k))
    fg = layer(L, True); bg = layer(L, False)
    for n in ('icon_foreground', 'icon_foreground_round', 'icon_foreground_sa'):
        save(fg, f'mipmap-{name}/{n}.png')
    save(bg, f'mipmap-{name}/kimogram_icon_background.png')
    # Telegram's clip layer draws its plane; ours is fully transparent.
    for n in ('icon_background_clip', 'icon_background_clip_round'):
        save(Image.new('RGBA', (L, L), (0, 0, 0, 0)), f'mipmap-{name}/{n}.png')
    mono = Image.new('RGBA', (L, L), (255, 255, 255, 0))
    mono.putalpha(fg.getchannel('A'))
    save(mono, f'mipmap-{name}/kimogram_icon_mono.png')
    logo = full_logo(I * 4)
    save(masked(logo, 0.2237).resize((I, I), Image.LANCZOS), f'mipmap-{name}/ic_launcher.png')
    save(masked(logo, 0.5).resize((I, I), Image.LANCZOS), f'mipmap-{name}/ic_launcher_round.png')
    save(masked(logo, 0.5).resize((I, I), Image.LANCZOS).convert('RGBA'), f'drawable-{name}/ic_launcher_dr.png')

store = os.path.join(out, 'store')
os.makedirs(store, exist_ok=True)
full_logo(1024).convert('RGB').resize((512, 512), Image.LANCZOS).save(os.path.join(store, 'play-icon-512.png'))
print('icons written')

# In-app logo for the "Настройки Kimogram" row: just the mark, no background (24dp square).
bb = MARK.getbbox()
crop = MARK.crop(bb)
side = max(crop.width, crop.height)
sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
sq.alpha_composite(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
for name, k in DENS.items():
    S = int(round(24 * k))
    save(sq.resize((S, S), Image.LANCZOS), f'drawable-{name}/kimogram_settings_logo.png')
