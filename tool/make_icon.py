"""Koçum logosu: optik kabarcık + onay işareti + amber zaman noktası.

Uygulamanın tohum rengi #1F6F5C (çam yeşili). Bu betik hem uygulama içi logoyu
(assets/icon/logo.png) hem de Android başlatıcı simgelerini
(tool/android_icon/res/...) üretir. Çalıştırmak için: python3 tool/make_icon.py
"""
import os
from PIL import Image, ImageDraw

PINE = (31, 111, 92)       # #1F6F5C
PINE_DARK = (18, 77, 63)   # gölge tonu
MINT = (222, 242, 233)     # açık nane
AMBER = (245, 166, 35)     # vurgu
SS = 4                     # süper örnekleme (kenar yumuşatma)


def mark(size, bg=True, fg=(255, 255, 255), padding=0.0):
    """Logoyu size×size çizer. padding: ön plan için güvenli alan payı (0–0.5)."""
    import math
    S = size * SS
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg:
        # yukarıdan aşağı hafif degrade: açık çam → koyu çam
        grad = Image.new('RGBA', (S, S))
        gd = ImageDraw.Draw(grad)
        top, bottom = (42, 130, 108), PINE_DARK
        for y in range(S):
            t = y / (S - 1)
            gd.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
        maskimg = Image.new('L', (S, S), 0)
        ImageDraw.Draw(maskimg).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
        img.paste(grad, (0, 0), maskimg)
        d = ImageDraw.Draw(img)

    inset = S * padding
    box = S - 2 * inset
    cx, cy = S / 2, S / 2 + box * 0.02
    R = box * 0.30
    w = int(box * 0.075)
    # optik kabarcık: sağ üstte boşluk bırakan halka (tik buradan çıkar)
    d.arc([cx - R, cy - R, cx + R, cy + R], start=338, end=292, fill=fg, width=w)
    for ang in (338, 292):
        a = math.radians(ang)
        ex, ey = cx + (R - w / 2) * math.cos(a), cy + (R - w / 2) * math.sin(a)
        d.ellipse([ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2], fill=fg)
    # onay işareti: halkanın içinden boşluğa doğru taşar
    a = math.radians(315)
    p1 = (cx - R * 0.52, cy + R * 0.04)
    p2 = (cx - R * 0.10, cy + R * 0.46)
    p3 = (cx + R * 1.18 * math.cos(a), cy + R * 1.18 * math.sin(a))
    lw = int(box * 0.09)
    d.line([p1, p2], fill=fg, width=lw)
    d.line([p2, p3], fill=fg, width=lw)
    for p in (p1, p2, p3):
        d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill=fg)
    # amber zaman noktası: tikin ucunda, "tamam" anının vurgusu
    ar = box * 0.07
    ax, ay = p3[0] + box * 0.10, p3[1] - box * 0.10
    d.ellipse([ax - ar, ay - ar, ax + ar, ay + ar], fill=AMBER)
    return img.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
save(mark(512), os.path.join(root, 'assets/icon/logo.png'))
save(mark(1024), os.path.join(root, 'tool/android_icon/logo_1024.png'))

res = os.path.join(root, 'tool/android_icon/res')
dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, k in dens.items():
    # Eski tip simge (48dp): yuvarlatılmış kare, tam logo
    save(mark(int(48 * k)), f'{res}/mipmap-{name}/ic_launcher.png')
    # Uyarlanabilir simge ön planı (108dp; ortadaki 66dp güvenli alan)
    fg = mark(int(108 * k), bg=False, padding=0.17)
    save(fg, f'{res}/drawable-{name}/ic_launcher_foreground.png')
    # Tek renk (Android 13+ temalı simgeler)
    save(mark(int(108 * k), bg=False, padding=0.17, fg=(0, 0, 0)), f'{res}/drawable-{name}/ic_launcher_monochrome.png')

os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml', 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
''')
os.makedirs(f'{res}/values', exist_ok=True)
open(f'{res}/values/ic_launcher_background.xml', 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1F6F5C</color>
</resources>
''')
print('ok')
