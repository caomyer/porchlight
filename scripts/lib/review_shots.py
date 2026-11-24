"""Copies a result bundle's named screenshots out of an `xcresulttool export attachments`
folder, each under its snapshot's name, and prints each copy with its size in pixels
(path, width, height, tab separated) for scripts/review-shots.sh to turn upright.

Only the tests' own snapshots are kept: XCTest's automatic attachments (UI snapshots,
synthesized events, the screen recording) have no file a reviewer wants.
"""
import json
import shutil
import struct
import sys
from pathlib import Path


def png_size(path):
    """A PNG's width and height, from its header."""
    with open(path, "rb") as file:
        head = file.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def snapshot_name(suggested):
    """"63-glow" from "63-glow_0_3C06....png"; None for anything that is not a snapshot."""
    if not suggested.endswith(".png") or "_0_" not in suggested:
        return None
    return suggested.split("_0_")[0]


def main(raw, out):
    manifest = json.loads((Path(raw) / "manifest.json").read_text())
    taken = set()
    for test in manifest:
        for attachment in test.get("attachments", []):
            name = snapshot_name(attachment.get("suggestedHumanReadableName", ""))
            source = Path(raw) / attachment.get("exportedFileName", "")
            if name is None or not source.is_file():
                continue
            size = png_size(source)
            if size is None:
                continue
            # Two tests may use one name: keep both.
            target = name
            count = 2
            while target in taken:
                target = f"{name}-{count}"
                count += 1
            taken.add(target)
            copy = Path(out) / f"{target}.png"
            shutil.copyfile(source, copy)
            print(f"{copy}\t{size[0]}\t{size[1]}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
