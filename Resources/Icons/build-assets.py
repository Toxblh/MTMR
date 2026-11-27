#!/usr/bin/env python3
"""Regenerates MTMR/Assets.xcassets/Icons/ from Resources/Icons/manifest.json and the *.svg files.

Run from anywhere:  python3 -I Resources/Icons/build-assets.py [--check]

- one <name>.imageset per manifest icon whose SVG exists (SVG copied, template + vector preserved)
- imagesets of icons that are no longer in the manifest are removed
- missing SVGs are reported (exit code stays 0: designers may still be drawing)
- idempotent: files are only rewritten when their content changes
- --check: change nothing, exit 1 if the catalog is out of date
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CATALOG = ROOT.parent.parent / "MTMR" / "Assets.xcassets" / "Icons"
INFO = {"author": "xcode", "version": 1}


def dump(obj):
    return json.dumps(obj, indent=2, sort_keys=True) + "\n"


def imageset_contents(name):
    return dump({
        "images": [{"filename": name + ".svg", "idiom": "universal"}],
        "info": INFO,
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    })


def folder_contents():
    # provides-namespace is true because the catalog already has imagesets named "cpu", "dnd-on", ...
    # (legacy PNGs); the icons are addressed as "Icons/<name>".
    return dump({"info": INFO, "properties": {"provides-namespace": True}})


def write_if_changed(path, data, changes):
    old = path.read_bytes() if path.exists() else None
    new = data if isinstance(data, bytes) else data.encode()
    if old != new:
        changes.append(str(path.relative_to(ROOT.parent.parent)))
        if not CHECK:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(new)


CHECK = "--check" in sys.argv


def main():
    manifest = json.loads((ROOT / "manifest.json").read_text())
    names = [icon["name"] for icon in manifest]
    changes, missing = [], []

    write_if_changed(CATALOG / "Contents.json", folder_contents(), changes)
    wanted = set()
    for name in names:
        svg = ROOT / (name + ".svg")
        if not svg.is_file():
            missing.append(name)
            continue
        wanted.add(name + ".imageset")
        target = CATALOG / (name + ".imageset")
        write_if_changed(target / (name + ".svg"), svg.read_bytes(), changes)
        write_if_changed(target / "Contents.json", imageset_contents(name), changes)

    if CATALOG.is_dir():
        # exFAT volumes create "._*" AppleDouble companions next to every file; they are not part of the catalog.
        if not CHECK:
            for stray in CATALOG.rglob("._*"):
                stray.unlink()
        for entry in sorted(CATALOG.iterdir()):
            if entry.name.startswith("._"):
                continue
            if entry.name.endswith(".imageset") and entry.name not in wanted:
                changes.append("remove " + str(entry.relative_to(ROOT.parent.parent)))
                if not CHECK:
                    shutil.rmtree(entry)

    print("%d of %d icons in catalog, %d missing SVG(s)%s" % (len(wanted), len(names), len(missing), ": " + ", ".join(missing) if missing else ""))
    print("%d change(s)%s" % (len(changes), " needed" if CHECK else ""))
    for change in changes:
        print("  " + change)
    return 1 if CHECK and changes else 0


if __name__ == "__main__":
    sys.exit(main())
