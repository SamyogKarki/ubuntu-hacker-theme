#!/usr/bin/env python3
"""Build the Hacker-Cursor theme: Ubuntu's Yaru cursors recoloured neon green with black outlines.

usage: cursor.py OUTPUT_THEME_DIR
"""
import os
import shutil
import struct
import sys

SRC = "/usr/share/icons/Yaru/cursors"
GREEN = (0x00, 0xFF, 0x66)
IMAGE_CHUNK = 0xFFFD0002


def recolor(data):
    buf = bytearray(data)
    _magic, header_size, _version, toc_count = struct.unpack_from("<4sIII", buf, 0)
    for i in range(toc_count):
        chunk_type, _subtype, pos = struct.unpack_from("<III", buf, header_size + i * 12)
        if chunk_type != IMAGE_CHUNK:
            continue
        chunk_header, _, _, _, width, height = struct.unpack_from("<IIIIII", buf, pos)
        pixels = pos + chunk_header
        for j in range(width * height):
            o = pixels + j * 4
            b, g, r, a = buf[o], buf[o + 1], buf[o + 2], buf[o + 3]
            if a == 0:
                continue
            # pixels are premultiplied: un-premultiply, then dark -> neon green, light -> black
            k = 1 - min(1.0, (0.2126 * r + 0.7152 * g + 0.0722 * b) / a)
            buf[o + 2] = round(GREEN[0] * k * a / 255)
            buf[o + 1] = round(GREEN[1] * k * a / 255)
            buf[o] = round(GREEN[2] * k * a / 255)
    return bytes(buf)


def main():
    dst = sys.argv[1]
    if not os.path.isdir(SRC):
        sys.exit("Yaru cursors not found")
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(f"{dst}/cursors")
    count = 0
    for name in os.listdir(SRC):
        src, out = f"{SRC}/{name}", f"{dst}/cursors/{name}"
        if os.path.islink(src):
            os.symlink(os.readlink(src), out)
            continue
        with open(src, "rb") as f:
            data = f.read()
        if data[:4] == b"Xcur":  # Windows .cur/.ani copies in the same folder are left as they are
            data = recolor(data)
            count += 1
        with open(out, "wb") as f:
            f.write(data)
    with open(f"{dst}/index.theme", "w") as f:
        f.write("[Icon Theme]\nName=Hacker-Cursor\nComment=Neon green Yaru cursors\nInherits=Yaru\n")
    print(f"recoloured cursors: {count}")


if __name__ == "__main__":
    main()
