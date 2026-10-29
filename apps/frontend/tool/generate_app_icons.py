#!/usr/bin/env python3
"""Produce platform icons from the checked-in master (requires Pillow)."""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/ffido-icon-source.png'


def canvas(source, size, fraction=0.88):
    result = Image.new('RGB', (size, size), source.getpixel((0, 0)))
    thumbnail = source.copy()
    side = max(1, round(size * fraction))
    thumbnail.thumbnail((side, side), Image.Resampling.LANCZOS)
    result.paste(thumbnail, ((size - thumbnail.width) // 2,
                             (size - thumbnail.height) // 2))
    return result


def png(source, relative, size, fraction=0.88):
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas(source, size, fraction).save(target)


def main():
    with Image.open(SOURCE) as image:
        source = image.convert('RGB')
    for platform in ('ios', 'macos'):
        directory = Path(platform) / 'Runner/Assets.xcassets/AppIcon.appiconset'
        manifest = json.loads((ROOT / directory / 'Contents.json').read_text())
        for entry in manifest['images']:
            size = round(float(entry['size'].split('x')[0]) *
                         float(entry['scale'].removesuffix('x')))
            png(source, directory / entry['filename'], size)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        png(source, f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
    for size in (192, 512):
        png(source, f'web/icons/Icon-{size}.png', size)
        # The entire mascot fits inside the central maskable safe circle.
        png(source, f'web/icons/Icon-maskable-{size}.png', size, 0.56)
    png(source, 'web/favicon.png', 32)
    png(source, 'linux/runner/resources/app_icon.png', 256)
    canvas(source, 256).save(
        ROOT / 'windows/runner/resources/app_icon.ico',
        sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)],
    )


if __name__ == '__main__':
    main()
