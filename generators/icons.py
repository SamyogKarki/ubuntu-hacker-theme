#!/usr/bin/env python3
"""Build the Papirus-Hacker icon theme from the installed Papirus theme.

- folders: Papirus already ships green folders, so the blue ones are symlinked to them
- apps: every colour in each app icon is mapped, by brightness, onto a neon-green ramp

usage: icons.py OUTPUT_THEME_DIR
"""
import colorsys
import os
import re
import shutil
import sys

SRC = "/usr/share/icons/Papirus"
HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")


def green(match):
    h = match.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    # black -> very dark green, white -> pale mint, so shapes keep their contrast
    R, G, B = colorsys.hls_to_rgb(145 / 360, 0.06 + 0.82 * lum, 1.0)
    return "#%02x%02x%02x" % (round(R * 255), round(G * 255), round(B * 255))


def folders(dst):
    count = 0
    for size in os.listdir(SRC):
        src_dir = f"{SRC}/{size}/places"
        if not os.path.isdir(src_dir):
            continue
        os.makedirs(f"{dst}/{size}/places", exist_ok=True)
        for name in os.listdir(src_dir):
            path = f"{src_dir}/{name}"
            if not os.path.islink(path):
                continue
            target = os.readlink(path)
            if "-blue" not in target:
                continue
            green_target = target.replace("-blue", "-green", 1)
            if os.path.exists(f"{src_dir}/{green_target}"):
                os.symlink(f"{src_dir}/{green_target}", f"{dst}/{size}/places/{name}")
                count += 1
    return count


def apps(dst):
    # @2x sets are skipped: they are only used on HiDPI screens and double the disk use
    sizes = [d for d in os.listdir(SRC) if "@2x" not in d and os.path.isdir(f"{SRC}/{d}/apps")]
    files = links = 0
    for size in sizes:
        src_dir, out_dir = f"{SRC}/{size}/apps", f"{dst}/{size}/apps"
        os.makedirs(out_dir, exist_ok=True)
        pending_links = []
        for name in os.listdir(src_dir):
            path = f"{src_dir}/{name}"
            if os.path.islink(path):
                pending_links.append(name)
            elif name.endswith(".svg"):
                with open(path, encoding="utf-8", errors="replace") as f:
                    data = HEX.sub(green, f.read())
                with open(f"{out_dir}/{name}", "w", encoding="utf-8") as f:
                    f.write(data)
                files += 1
        for name in pending_links:
            target = os.readlink(f"{src_dir}/{name}")
            out = f"{out_dir}/{name}"
            # same-folder links follow the green copy; anything else points back at Papirus
            if "/" not in target and os.path.exists(f"{out_dir}/{target}"):
                os.symlink(target, out)
            else:
                os.symlink(os.path.realpath(f"{src_dir}/{name}"), out)
            links += 1
    return files, links


def main():
    dst = sys.argv[1]
    if not os.path.isdir(SRC):
        sys.exit("Papirus icon theme not found (sudo apt install papirus-icon-theme)")
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(dst)
    with open(f"{SRC}/index.theme") as f:
        index = f.read()
    index = re.sub(r"(?m)^Name=.*", "Name=Papirus-Hacker", index)
    index = re.sub(r"(?m)^Inherits=.*", "Inherits=Papirus-Dark,Papirus,breeze-dark,hicolor", index)
    with open(f"{dst}/index.theme", "w") as f:
        f.write(index)
    n_folders = folders(dst)
    n_apps, n_links = apps(dst)
    print(f"green folders: {n_folders}, recoloured app icons: {n_apps} (+{n_links} links)")


if __name__ == "__main__":
    main()
