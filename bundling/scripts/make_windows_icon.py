#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a Windows or macOS application icon from a source PNG."
    )
    parser.add_argument("source_png")
    parser.add_argument("dest_icon")
    args = parser.parse_args()

    try:
        from PIL import Image
    except ModuleNotFoundError:
        raise SystemExit(
            "Pillow is required to generate Windows/macOS icon files."
        )

    source = Path(args.source_png)
    dest = Path(args.dest_icon)
    source_image = Image.open(source).convert("RGBA")

    if dest.suffix.lower() == ".ico":
        sizes = [(size, size) for size in [16, 32, 48, 64, 128, 256]]
        fmt = "ICO"
    else:
        sizes = [(size, size) for size in [16, 32, 48, 64, 128, 256, 512, 1024]]
        fmt = "ICNS"

    source_image.save(dest, format=fmt, sizes=sizes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
