#!/usr/bin/env python3
"""Run offline checks without updating source data or publishing an archive."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LUA_TESTS = ("compatibility.lua", "regressions.lua", "database.lua")


def main():
    subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "Updater/tests", "-v"], cwd=ROOT, check=True)
    from build_release import runtime_files
    files = [path for path in runtime_files(ROOT, "NpcAbilitiesForever") if path.suffix == ".lua"]
    files.extend((ROOT / "Updater/tests").glob("*.lua"))
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        interpreter = shutil.which("lua5.1") or shutil.which("lua")
        if not interpreter:
            raise SystemExit("Lua tests require Lua 5.1 or the optional development package: python -m pip install lupa")
        subprocess.run([interpreter, "-e", "assert(_VERSION == 'Lua 5.1', 'Lua 5.1 is required')"], cwd=ROOT, check=True)
        # Pass paths as arguments, not executable shell text.
        with tempfile.TemporaryDirectory(prefix="npcabilities-check-") as directory:
            script = Path(directory) / "syntax.lua"
            script.write_text("for _, path in ipairs(arg) do assert(loadfile(path)) end\n", encoding="utf-8")
            subprocess.run([interpreter, str(script), *map(str, files)], cwd=ROOT, check=True)
        for test in LUA_TESTS:
            subprocess.run([interpreter, "Updater/tests/" + test], cwd=ROOT, check=True)
    else:
        # loadfile in the Lua tests resolves relative to the checkout.
        import os
        previous = Path.cwd()
        os.chdir(ROOT)
        try:
            compiler = LuaRuntime().eval("function(text, name) assert(loadstring(text, name)) end")
            for path in files:
                compiler(path.read_text(encoding="utf-8-sig"), str(path.relative_to(ROOT)))
            for test in LUA_TESTS:
                LuaRuntime().execute((ROOT / "Updater/tests" / test).read_text(encoding="utf-8"))
        finally:
            os.chdir(previous)
    print(f"PASS: Lua 5.1 syntax ({len(files)} files), Python tests and WoW simulations. No in-game test performed.")


if __name__ == "__main__":
    main()
