#!/usr/bin/env python3
"""Draw the Matrix-rain desktop wallpaper with a "> SYSTEM ONLINE_" panel.

usage: wallpaper.py OUTPUT.png HOSTNAME [WIDTHxHEIGHT]
"""
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

MONO = "/usr/share/fonts/truetype/ubuntu/UbuntuMono[wght].ttf"
BOLD = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Bold.ttf"
REGULAR = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf"
GREEN = (0, 255, 102)
CHARS = "01<>{}[]#$%&*+=/\\|ABCDEFabcdef0123456789"


def rain(width, height, scale):
    img = Image.new("RGB", (width, height), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(MONO, round(18 * scale))
    col_w, row_h = round(14 * scale), round(20 * scale)
    rows = height // row_h + 1
    rng = random.Random(1337)
    for x in range(0, width, col_w):
        if rng.random() < 0.35:
            continue
        length = rng.randint(6, 40)
        start = rng.randint(-10, rows)
        for i in range(length):
            y = start + i
            if not 0 <= y <= rows:
                continue
            head = i == length - 1
            g = int(30 + 170 * (i / length) ** 2)
            colour = (255, 255, 255) if head else (int(g * 0.3), g, int(g * 0.35))
            draw.text((x, y * row_h), rng.choice(CHARS), font=font, fill=colour)
    return Image.blend(img, img.filter(ImageFilter.GaussianBlur(3)), 0.35)


def main():
    out, host = sys.argv[1], sys.argv[2]
    width, height = map(int, (sys.argv[3] if len(sys.argv) > 3 else "1920x1080").split("x"))
    scale = height / 1080

    img = rain(width, height, scale)
    draw = ImageDraw.Draw(img)
    big = ImageFont.truetype(BOLD, round(88 * scale))
    small = ImageFont.truetype(REGULAR, round(26 * scale))
    title = "> SYSTEM ONLINE_"
    sub = f"all services running  ::  root@{host}"
    tw, sw = draw.textlength(title, font=big), draw.textlength(sub, font=small)
    box_w, box_h = max(tw, sw) + 80 * scale, 210 * scale
    bx, by = (width - box_w) / 2, height / 2 - 110 * scale

    glow = Image.new("RGB", (width, height), (0, 0, 0))
    ImageDraw.Draw(glow).rectangle([bx, by, bx + box_w, by + box_h], outline=GREEN, width=round(6 * scale))
    img = ImageChops.lighter(img, glow.filter(ImageFilter.GaussianBlur(10 * scale)))

    draw = ImageDraw.Draw(img)
    draw.rectangle([bx, by, bx + box_w, by + box_h], fill=(0, 8, 0), outline=GREEN, width=max(2, round(2 * scale)))
    draw.text(((width - tw) / 2, by + 30 * scale), title, font=big, fill=GREEN)
    draw.text(((width - sw) / 2, by + 150 * scale), sub, font=small, fill=(120, 255, 150))
    img.save(out)


if __name__ == "__main__":
    main()
