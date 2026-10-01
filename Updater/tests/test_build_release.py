"""Check that the CurseForge ZIP contains runtime files and no updater data."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile

MODULE = Path(__file__).resolve().parents[1] / "build_release.py"
SPEC = importlib.util.spec_from_file_location("release_builder", MODULE)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class ReleaseTests(unittest.TestCase):
    def test_zip_contains_only_addon_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "source"
            root.mkdir()
            for name in ("NpcAbilitiesForever.toc", "NpcAbilitiesForever.lua", "NpcAbilitiesForeverCollector.lua", "embeds.xml", "LICENSE"):
                (root / name).write_text(name, encoding="utf-8")
            for name in ("Database", "Frames", "Libs", "Localization", "Updater", "reference_addons"):
                (root / name).mkdir()
            (root / "Database/forever.lua").write_text("return {}", encoding="utf-8")
            (root / "Database/forever.json").write_text("{}", encoding="utf-8")
            (root / "Libs/lib.lua").write_text("return {}", encoding="utf-8")
            (root / "Libs/tests").mkdir()
            (root / "Libs/tests/test.lua").write_text("error('not runtime')", encoding="utf-8")
            (root / "Updater/update_database.py").write_text("", encoding="utf-8")
            (root / "reference_addons/details.lua").write_text("-- reference only", encoding="utf-8")
            output = Path(temp) / "release.zip"
            builder.build_zip(root, output)
            with ZipFile(output) as archive:
                names = set(archive.namelist())
            self.assertIn("NpcAbilitiesForever/NpcAbilitiesForever.toc", names)
            self.assertIn("NpcAbilitiesForever/Database/forever.lua", names)
            self.assertIn("NpcAbilitiesForever/Libs/lib.lua", names)
            self.assertIn("NpcAbilitiesForever/LICENSE", names)
            self.assertNotIn("NpcAbilitiesForever/Database/forever.json", names)
            self.assertFalse(any("reference_addons" in name for name in names))
            self.assertFalse(any("/Updater/" in name or "/tests/" in name for name in names))

    def test_real_package_contains_all_active_loader_references(self):
        import re
        root = MODULE.parents[1]
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "addon.zip"
            builder.build_zip(root, output)
            with ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                names = set(archive.namelist())
                for name in names:
                    if name.endswith(".xml"):
                        text = re.sub(r"<!--.*?-->", "", archive.read(name).decode("utf-8-sig"), flags=re.S)
                        refs = re.findall(r'file="([^"]+)"', text)
                    elif name == "NpcAbilitiesForever/NpcAbilitiesForever.toc":
                        refs = [line.strip() for line in archive.read(name).decode("utf-8-sig").splitlines()
                                if line.strip() and not line.startswith("#")]
                    else:
                        continue
                    for ref in refs:
                        resolved = (Path(name).parent / ref.replace(chr(92), "/")).as_posix()
                        self.assertIn(resolved, names, f"Missing runtime file referenced by {name}")
                self.assertFalse(any("reference_addons/" in name or "/Updater/" in name for name in names))


if __name__ == "__main__":
    unittest.main()
