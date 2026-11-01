import sys
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
L = open(src, encoding='latin-1').read().split('\n')
rows = [(L[i], L[i+1], L[i+2]) for i in range(0, len(L) - 2, 3)]
pal = {}
for l in open(src + '.pal'):
    k, v = l.split(); pal[k] = tuple(int(v[i:i+2], 16) for i in (0, 2, 4))
default = {'0':(240,240,240),'1':(242,178,51),'2':(229,127,216),'3':(153,178,242),'4':(222,222,108),'5':(127,204,25),'6':(242,178,204),'7':(76,76,76),'8':(153,153,153),'9':(76,153,178),'a':(178,102,229),'b':(51,102,204),'c':(127,102,76),'d':(87,166,78),'e':(204,76,76),'f':(17,17,17)}
for k,v in default.items(): pal.setdefault(k, v)
CW, CH = 8, 12
W, H = len(rows[0][0]), len(rows)
img = Image.new('RGB', (W*CW, H*CH)); d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 11)
special = {7:'•', 4:'♦', 16:'►', 17:'◄', 24:'↑', 25:'↓', 26:'→', 27:'←', 30:'▲', 31:'▼', 15:'☼', 3:'♥', 2:'☻', 1:'☺', 8:'◘', 9:'○', 14:'♫', 18:'↕', 19:'‼', 23:'↨', 28:'∟', 29:'↔', 167:'§', 215:'×', 183:'·'}
for y, (t, f, b) in enumerate(rows):
    for x in range(W):
        ch = ord(t[x]) if x < len(t) else 32
        fg = pal.get(f[x] if x < len(f) else '0'); bg = pal.get(b[x] if x < len(b) else 'f')
        x0, y0 = x*CW, y*CH
        d.rectangle([x0, y0, x0+CW-1, y0+CH-1], fill=bg)
        if 128 <= ch <= 159:
            bits = ch - 128
            sw, sh = CW//2, CH//3
            for i in range(6):
                on = bool(bits >> i & 1) if i < 5 else False
                if on:
                    px, py = x0 + (i % 2)*sw, y0 + (i//2)*sh
                    d.rectangle([px, py, px+sw-1, py+sh-1], fill=fg)
        elif ch != 32:
            c = special.get(ch, chr(ch) if ch >= 32 else '?')
            d.text((x0, y0), c, font=font, fill=fg)
img.save(out)
