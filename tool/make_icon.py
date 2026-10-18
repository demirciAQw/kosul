"""Koçum logosu (v6): Google renklerinde dört parçalı optik halka + mavi onay işareti.

Bu betik hem uygulama içi logoyu
(assets/icon/logo.png) hem de Android başlatıcı simgelerini
(tool/android_icon/res/...) üretir. Çalıştırmak için: python3 tool/make_icon.py
"""
import os
from PIL import Image, ImageDraw

# Google renkleri (lib/app/palette.dart ile aynı)
BLUE = (26, 115, 232)
RED = (217, 48, 37)
YELLOW = (249, 171, 0)
GREEN = (30, 142, 62)
WHITE = (255, 255, 255)
SS = 4  # süper örnekleme (kenar yumuşatma)


def mark(size, bg=True, mono=None, padding=0.0):
    """Dört renkli optik halka; sağ üstteki boşluktan mavi tik çıkar.

    bg: beyaz yuvarlatılmış kare zemin (eski tip simge).
    mono: tek renk (Android 13 temalı simgeler için), ör. (0, 0, 0).
    """
    import math
    S = size * SS
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg:
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=WHITE)
    inset = S * padding
    box = S - 2 * inset
    cx, cy = S / 2, S / 2 + box * 0.02
    R = box * 0.30
    w = int(box * 0.085)
    col = (lambda c: mono) if mono else (lambda c: c)
    # Halka dört yay: kırmızı (sol üst), sarı (sol alt), yeşil (sağ alt), mavi (sağ).
    # PIL açıları: 0° = saat 3, saat yönünde artar. Boşluk 292°–338° (sağ üst).
    arcs = [(338, 45, BLUE), (45, 135, GREEN), (135, 215, YELLOW), (215, 292, RED)]
    box_r = [cx - R, cy - R, cx + R, cy + R]
    for a0, a1, c in arcs:
        d.arc(box_r, start=a0, end=a1, fill=col(c), width=w)
    for ang, c in ((338, BLUE), (292, RED)):  # uçları yuvarla
        a = math.radians(ang)
        ex, ey = cx + (R - w / 2) * math.cos(a), cy + (R - w / 2) * math.sin(a)
        d.ellipse([ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2], fill=col(c))
    # Tik: halkanın içinden boşluğa doğru, mavi.
    a = math.radians(315)
    p1 = (cx - R * 0.50, cy + R * 0.04)
    p2 = (cx - R * 0.08, cy + R * 0.46)
    p3 = (cx + R * 1.20 * math.cos(a), cy + R * 1.20 * math.sin(a))
    lw = int(box * 0.095)
    d.line([p1, p2], fill=col(BLUE), width=lw)
    d.line([p2, p3], fill=col(BLUE), width=lw)
    for p in (p1, p2, p3):
        d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill=col(BLUE))
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
    fg = mark(int(108 * k), bg=False, padding=0.14)
    save(fg, f'{res}/drawable-{name}/ic_launcher_foreground.png')
    # Tek renk (Android 13+ temalı simgeler)
    save(mark(int(108 * k), bg=False, padding=0.14, mono=(0, 0, 0)), f'{res}/drawable-{name}/ic_launcher_monochrome.png')

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
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
''')
print('ok')
