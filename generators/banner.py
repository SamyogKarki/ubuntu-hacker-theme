#!/usr/bin/env python3
"""Turn a name into a block-letter terminal banner (used as the fastfetch logo).

The text is rendered with a real font, then every pair of pixel rows becomes one line of
half-block characters, so any name works without needing figlet fonts.

usage: banner.py NAME OUTPUT.txt
"""
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-ExtraBold.ttf"
HEIGHT_PX = 12  # 12 pixel rows -> 6 terminal lines
MAX_CHARS = 10


def main():
    name = sys.argv[1].upper()[:MAX_CHARS]
    out = sys.argv[2]
    font = ImageFont.truetype(FONT, HEIGHT_PX + 4)
    left, top, right, bottom = font.getbbox(name)
    img = Image.new("L", (right - left + 2, bottom - top + 2), 0)
    ImageDraw.Draw(img).text((1 - left, 1 - top), name, font=font, fill=255)
    width, height = img.size
    if height % 2:
        height += 1
    on = lambda x, y: y < img.size[1] and img.getpixel((x, y)) > 110

    lines = []
    for y in range(0, height, 2):
        row = ""
        for x in range(width):
            upper, lower = on(x, y), on(x, y + 1)
            row += "█" if upper and lower else "▀" if upper else "▄" if lower else " "
        lines.append("  " + row.rstrip())
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
