#!/usr/bin/env python3
"""Build a CurseForge ZIP containing only files loaded by the addon."""
from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIRS = ("Database", "Frames", "Libs", "Localization")
RUNTIME_EXTENSIONS = {".lua", ".xml", ".toc"}


def runtime_files(root, addon_name):
    required = [root / f"{addon_name}.toc", root / "NpcAbilitiesForever.lua", root / "NpcAbilitiesForeverCollector.lua", root / "embeds.xml", root / "LICENSE"]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing addon files: " + ", ".join(missing))
    files = list(required)
    for dirname in RUNTIME_DIRS:
        directory = root / dirname
        if not directory.is_dir():
            raise FileNotFoundError(f"Missing addon directory: {directory}")
        files.extend(path for path in directory.rglob("*")
                     if path.is_file() and path.suffix.lower() in RUNTIME_EXTENSIONS
                     and not any(part.lower() in ("test", "tests", "docs", "__pycache__")
                                 for part in path.relative_to(directory).parts))
    return sorted(set(files), key=lambda path: path.relative_to(root).as_posix())


def build_zip(root, output, addon_name="NpcAbilitiesForever"):
    root = Path(root).resolve()
    output = Path(output).resolve()
    files = runtime_files(root, addon_name)
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files:
            archive.write(path, f"{addon_name}/{path.relative_to(root).as_posix()}")
    return len(files)


def main():
    parser = argparse.ArgumentParser(description="Build a clean CurseForge addon ZIP.")
    parser.add_argument("--root", type=Path, default=ROOT, help="Addon source directory")
    parser.add_argument("--output", type=Path, default=ROOT.parent / "NpcAbilitiesForever.zip", help="Output ZIP")
    parser.add_argument("--addon-name", choices=("NpcAbilitiesForever",), default="NpcAbilitiesForever")
    args = parser.parse_args()
    count = build_zip(args.root, args.output, args.addon_name)
    print(f"{count} runtime files: {args.output.resolve()}")


if __name__ == "__main__":
    main()
