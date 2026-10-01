"""Offline regression tests: python -m unittest discover -s Updater/tests -p test_*.py"""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "tools/update_database.py"
SPEC = importlib.util.spec_from_file_location("updater", MODULE)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


def npc_page(npc_id=30, spells=(11918,), status="unchanged", tab=True, truncated=False):
    page = 'var g_pageInfo = {type: 1, typeId: %d, name: "Test NPC"};' % npc_id
    page += '$.extend(g_npcs[%d], %s);' % (npc_id, json.dumps({"envChange": {"status": status}}))
    if tab:
        data = [{"id": value, "envChange": {"status": "unchanged"}} for value in spells]
        literal = json.dumps(data).replace('"envChange":', 'envChange:')
        page += "new Listview({template:'spell', id:'abilities', _truncated:%d, data:%s});</script>" % (truncated, literal)
    return page


class ParserTests(unittest.TestCase):
    def test_unquoted_keys_escapes_and_nested_data(self):
        data = updater.LiteralReader(r'''[{id: 30, modes: {"mode":[0]}, name: "a\"b\\c\n\u00e4"}]''').value()
        self.assertEqual(data[0]["modes"], {"mode": [0]})
        self.assertEqual(data[0]["name"], 'a"b\\c\nä')

    def test_rejects_executable_data(self):
        for source in ('[evil()]', '{name: window.location}', '{"id": 1, "id": 2}', '[1'):
            with self.subTest(source=source), self.assertRaises(updater.UpdateError):
                updater.LiteralReader(source).value()

    def test_npc_tab_and_explicit_empty(self):
        self.assertEqual(updater.parse_npc(npc_page(), 30)["spell_ids"], [11918])
        self.assertEqual(updater.parse_npc(npc_page(spells=()), 30)["spell_ids"], [])
        self.assertIsNone(updater.parse_npc(npc_page(tab=False), 30)["spell_ids"])

    def test_removed_npc_and_removed_spell(self):
        self.assertEqual(updater.parse_npc(npc_page(status="removed"), 30)["spell_ids"], [])
        page = npc_page().replace('envChange: {"status": "unchanged"}', 'envChange: {"status": "removed"}')
        self.assertEqual(updater.parse_npc(page, 30)["spell_ids"], [])

    def test_truncated_and_wrong_identity_rejected(self):
        for page in (npc_page(truncated=True), npc_page(npc_id=40), "Please verify you are human"):
            with self.subTest(page=page), self.assertRaises(updater.UpdateError):
                updater.parse_npc(page, 30)

    def test_lua_escaping(self):
        self.assertEqual(updater.lua_string('a"b\\c\n\x001|Tbad|t'), '"a\\"b\\\\c\\010\\0001||Tbad||t"')


class LimitedLookupTests(unittest.TestCase):
    def test_cache_resume_and_refresh(self):
        with tempfile.TemporaryDirectory() as temp:
            provider = updater.Wowhead(Path(temp))
            with patch.object(provider, "get", return_value=npc_page()) as get:
                provider.npc(30)
                provider.npc(30)
                self.assertEqual(get.call_count, 1)
                provider.refresh = True
                provider.npc(30)
                self.assertEqual(get.call_count, 2)


class WagoCsvTests(unittest.TestCase):
    def test_bulk_table_header_count_and_duplicates(self):
        with tempfile.TemporaryDirectory() as temp:
            provider = updater.Wago(Path(temp))
            payload = ("ID,Name_lang\n" + "".join(f"{number},Spell {number}\n" for number in range(1, 10001))).encode()
            with patch.object(provider, "cached", side_effect=lambda url, parser: parser(payload)):
                names = provider.table("SpellName", "1.60.1.70058", "en")
            self.assertEqual(len(names), 10000)
            self.assertEqual(names["10000"], {"ID": "10000", "Name_lang": "Spell 10000"})
            for bad in (b"ID,wrong\n1,x\n", payload + b"1,duplicate\n"):
                with patch.object(provider, "cached", side_effect=lambda url, parser: parser(bad)):
                    with self.assertRaises(ValueError):
                        provider.table("SpellName", "1.60.1.70058", "en")


class DownloadTests(unittest.TestCase):
    class Response(io.BytesIO):
        def geturl(self):
            return updater.WAGO_URL + "/api/builds"

    def test_download_progress_validation_and_cache(self):
        with tempfile.TemporaryDirectory() as temp, redirect_stdout(io.StringIO()) as output:
            provider = updater.Wago(Path(temp), delay=0)
            with patch.object(updater, "urlopen", return_value=self.Response(b'{"value": 42}')) as request:
                for _ in range(2):
                    result = provider.cached(updater.WAGO_URL + "/api/builds", json.loads)
                    self.assertEqual(result, {"value": 42})
                self.assertEqual(request.call_count, 1)
            self.assertIn("Download:", output.getvalue())
            self.assertIn("Download complete:", output.getvalue())
            self.assertIn("Reading cache:", output.getvalue())

    def test_total_timeout_preserves_cache_even_if_worker_finishes_later(self):
        release, finished = threading.Event(), threading.Event()
        def stalled(*args, **kwargs):
            release.wait(5)
            finished.set()
            return self.Response(b'{"new": true}')

        with tempfile.TemporaryDirectory() as temp, redirect_stdout(io.StringIO()):
            provider = updater.Wago(Path(temp), delay=0)
            url = updater.WAGO_URL + "/api/builds"
            with patch.object(updater, "urlopen", return_value=self.Response(b'{"old": true}')):
                provider.cached(url, json.loads)
            path = next(Path(temp).glob("*.data"))
            original = path.read_bytes()
            provider.refresh, provider.timeout = True, 0.05
            started = time.monotonic()
            try:
                with patch.object(updater, "urlopen", side_effect=stalled):
                    with self.assertRaisesRegex(updater.UpdateError, "timeout"):
                        provider.cached(url, json.loads)
                    self.assertLess(time.monotonic() - started, 2)
                    self.assertEqual(path.read_bytes(), original)
            finally:
                release.set()
                self.assertTrue(finished.wait(2))
            self.assertEqual(path.read_bytes(), original)

    def test_http_error_and_invalid_payload_are_not_cached(self):
        with tempfile.TemporaryDirectory() as temp, redirect_stdout(io.StringIO()):
            provider = updater.Wago(Path(temp), delay=0)
            url = updater.WAGO_URL + "/api/builds"
            with patch.object(updater, "urlopen", side_effect=updater.HTTPError(url, 403, "Forbidden", {}, None)):
                with self.assertRaisesRegex(updater.UpdateError, "HTTP 403"):
                    provider.cached(url, json.loads)
            with patch.object(updater, "urlopen", return_value=self.Response(b'not JSON')):
                with self.assertRaisesRegex(updater.UpdateError, "Invalid Wago data"):
                    provider.cached(url, json.loads)
            self.assertEqual(list(Path(temp).glob("*.data")), [])


class FakeWago:
    requests = 17
    cache_hits = 0
    def __init__(self, *args): pass
    def build(self): return "1.60.1.70058"
    def table(self, name, build, language):
        assert build == "1.60.1.70058"
        names = {"en": "Wind Spike", "de": "Windstachel", "es": "Púa de viento",
                 "fr": "Pointe du vent", "pt": "Espigão do Vento", "ru": "Шип ветра",
                 "ko": "바람 쐐기", "cn": "风之尖刺"}
        if name == "SpellName":
            return {"11918": {"Name_lang": "Gift" if language == "de" else "Poison"},
                    "99": {"Name_lang": "Neuer Zauber" if language == "de" else "New Spell"},
                    "1248802": {"Name_lang": names[language]},
                    "1301968": {"Name_lang": names[language]}}
        return {"11918": {"Description_lang": "Damage every $t1 sec."},
                "99": {"Description_lang": "Plain description."},
                "1248802": {"Description_lang": "Summons corrupted wind."},
                "1301968": {"Description_lang": "Summons corrupted wind."}}


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "Database").mkdir()
        (self.root / "Database/npcs.lua").write_text("_G['NpcAbilitiesNpcData'] = {\n[30] = {sod_spell_ids = {}, classic_spell_ids = {11918}},\n}\n", encoding="utf-8")
        (self.root / "Database/forever.lua").write_text('_G["NpcAbilitiesForeverData"] = {npcs = {}, abilities = {}}\n', encoding="utf-8")
        (self.root / "Database/npc_overrides.json").write_text('{"npcs": {}}', encoding="utf-8")
        self.args = SimpleNamespace(root=self.root, npc=None, combat_log=None, build=None, delay=0.75, cache_hours=24, refresh=False, languages=updater.DEFAULT_LOCALES, dry_run=False)

    def run_update(self, provider=FakeWago):
        with patch.object(updater, "Wago", provider), redirect_stdout(io.StringIO()):
            return updater.run(self.args)

    def overrides(self, rows):
        (self.root / "Database/npc_overrides.json").write_text(json.dumps({"npcs": rows}), encoding="utf-8")

    def test_bulk_spell_names_safe_descriptions_backup_and_idempotency(self):
        original = (self.root / "Database/forever.lua").read_bytes()
        report = self.run_update()
        self.assertEqual(report["npc_changes"], [])
        self.assertEqual(report["descriptions_with_unresolved_placeholders"], {language: 1 for language in updater.DEFAULT_LOCALES})
        snapshot = json.loads((self.root / "Database/forever.json").read_text(encoding="utf-8"))
        self.assertEqual(snapshot["build"], "1.60.1.70058")
        self.assertEqual(snapshot["abilities"]["de"]["11918"], {"name": "Gift"})
        self.assertEqual(snapshot["abilities"]["de"]["1248802"]["name"], "Windstachel")
        self.assertEqual(snapshot["abilities"]["de"]["1301968"]["name"], "Windstachel")
        self.assertEqual(snapshot["abilities"]["es"]["1248802"]["name"], "Púa de viento")
        self.assertEqual(set(snapshot["abilities"]), set(updater.DEFAULT_LOCALES))
        self.assertEqual(snapshot["npcs"], {})
        self.assertEqual((Path(report["backup"]) / "forever.lua").read_bytes(), original)
        self.assertIsNone(self.run_update()["backup"])
        self.assertIn("11918", (self.root / "Database/npcs.lua").read_text())

    def test_curated_new_npc_and_removed_old_ability(self):
        self.overrides({"30": {"spell_ids": [], "source": "checked"},
                        "270589": {"name": "New NPC", "spell_ids": [99], "source": "seen in game"}})
        report = self.run_update()
        snapshot = json.loads((self.root / "Database/forever.json").read_text(encoding="utf-8"))
        self.assertEqual(snapshot["npcs"]["30"]["spell_ids"], [])
        self.assertEqual(snapshot["npcs"]["270589"]["spell_ids"], [99])
        self.assertEqual(snapshot["abilities"]["en"]["99"]["description"], "Plain description.")
        changes = {item["id"]: item for item in report["npc_changes"]}
        self.assertEqual(changes[30]["removed_spells"], [11918])
        self.assertTrue(changes[270589]["new_to_database"])

    def test_combat_log_assigns_new_spells_and_npcs_without_deleting_old_spells(self):
        log = self.root / "WoWCombatLog.txt"
        log.write_text(
            '9/29 20:00:00.000 COMBAT_LOG_VERSION,9,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,1.60.1.70058,PROJECT_ID,1\n'
            '9/29 20:00:01.000 SPELL_CAST_START,Creature-0-1-0-1-270589-ABC,"Sturmkriecher",0x10a28,0x0,Player-1-A,"Held",0x511,0x0,1248802,"Wind Spike",0x8\n'
            '9/29 20:00:02.000 SPELL_CAST_SUCCESS,Creature-0-1-0-1-30-DEF,"Waldspinne",0x10a28,0x0,Player-1-A,"Held",0x511,0x0,1301968,"Wind Spike",0x8\n'
            '9/29 20:00:03.000 SPELL_CAST_START,Player-1-A,"Held",0x511,0x0,Creature-0-1-0-1-270589-ABC,"Sturmkriecher",0x10a28,0x0,99,"New Spell",0x8\n'
            '9/29 20:00:04.000 SPELL_DAMAGE,Creature-0-1-0-1-270589-ABC,"Sturmkriecher",0x10a28,0x0,Player-1-A,"Held",0x511,0x0,99,"New Spell",0x8\n', encoding="utf-8")
        self.args.combat_log = [log]
        report = self.run_update()
        snapshot = json.loads((self.root / "Database/forever.json").read_text(encoding="utf-8"))
        self.assertEqual(snapshot["npcs"]["270589"]["spell_ids"], [1248802])
        self.assertEqual(snapshot["npcs"]["30"]["spell_ids"], [11918, 1301968])
        self.assertEqual(report["observed_npc_updates"], 2)
        self.assertEqual(report["combat_logs"][0]["cast_events"], 2)
        self.assertIsNone(self.run_update()["backup"])

    def test_non_forever_log_is_rejected_without_changing_data(self):
        log = self.root / "WoWCombatLog.txt"
        log.write_text('9/29 20:00:00.000 COMBAT_LOG_VERSION,9,BUILD_VERSION,1.15.9,PROJECT_ID,2\n'
                       '9/29 20:00:01.000 SPELL_CAST_START,Creature-0-1-0-1-30-ABC,"Mob",0x10a28,0x0,Player-1-A,"Held",0x511,0x0,99,"Spell",0x8\n', encoding="utf-8")
        self.args.combat_log = [log]
        original = (self.root / "Database/forever.lua").read_bytes()
        with self.assertRaisesRegex(updater.UpdateError, "Not a Forever combat log"):
            self.run_update()
        self.assertEqual((self.root / "Database/forever.lua").read_bytes(), original)

    def test_configured_log_path_is_used_for_one_click_run(self):
        (self.root / "Logs").mkdir()
        log = self.root / "Logs/WoWCombatLog.txt"
        log.write_text('9/29 20:00:00.000 COMBAT_LOG_VERSION,9,BUILD_VERSION,1.60.1.70058\n'
                       '9/29 20:00:01.000 SPELL_CAST_START,Creature-0-1-0-1-270589-ABC,"Sturmkriecher",0x10a28,0x0,Player-1-A,"Held",0x511,0x0,1248802,"Wind Spike",0x8\n', encoding="utf-8")
        (self.root / "Updater/.data").mkdir(parents=True)
        (self.root / "Updater/.data/config.json").write_text(json.dumps({"combat_logs": [str(self.root)]}), encoding="utf-8")
        report = self.run_update()
        self.assertEqual(report["observed_npc_updates"], 1)

    def test_existing_wowhead_snapshot_migrates_without_losing_mappings(self):
        old = {"schema_version": 1, "source": updater.BASE_URL,
               "npcs": {"30": {"name": "NPC 30", "spell_ids": [99]}},
               "abilities": {"en": {"99": {"name": "Old name", "description": "Resolved description"},
                                    "11918": {"name": "Old poison", "description": "Resolved poison"}}, "de": {}}}
        (self.root / "Database/forever.json").write_text(json.dumps(old), encoding="utf-8")
        self.run_update()
        migrated = json.loads((self.root / "Database/forever.json").read_text(encoding="utf-8"))
        self.assertEqual(migrated["schema_version"], 2)
        self.assertEqual(migrated["npcs"], old["npcs"])
        self.assertEqual(migrated["abilities"]["en"]["99"]["description"], "Plain description.")
        self.assertNotIn("description", migrated["abilities"]["en"]["11918"])

    def test_changed_or_empty_description_removes_stale_overlay(self):
        self.run_update()
        for description in ("Changed effect: $s1", ""):
            class ChangedWago(FakeWago):
                def table(self, name, build, language):
                    rows = super().table(name, build, language)
                    if name == "Spell":
                        rows["99"]["Description_lang"] = description
                    return rows
            self.run_update(ChangedWago)
            snapshot = json.loads((self.root / "Database/forever.json").read_text(encoding="utf-8"))
            for language in updater.DEFAULT_LOCALES:
                self.assertNotIn("description", snapshot["abilities"][language]["99"])
            self.run_update()  # Restore a readable description for the next case.

    def test_render_marks_corrections_authoritative_and_log_imports_additive(self):
        snapshot = updater.empty_snapshot()
        snapshot["npcs"] = {
            "30": {"spell_ids": [], "source": "Manually checked"},
            "40": {"spell_ids": [11918], "source": "Forever combat log"},
            "41": {"spell_ids": [11918], "source": "Forever-Kampfprotokoll"},
        }
        rendered = updater.render_lua(snapshot)
        self.assertIn("[30] = {classic_spell_ids = {}, sod_spell_ids = {}, authoritative = true}", rendered)
        for npc in (40, 41):
            self.assertIn(f"[{npc}] = {{classic_spell_ids = {{11918}}, sod_spell_ids = {{}}, authoritative = false}}", rendered)

    def test_dry_run_only_writes_preview(self):
        original = (self.root / "Database/forever.lua").read_bytes()
        self.args.dry_run = True
        self.run_update()
        self.assertEqual((self.root / "Database/forever.lua").read_bytes(), original)
        self.assertFalse((self.root / "Database/forever.json").exists())
        self.assertTrue((self.root / "Updater/.data/preview-forever.lua").exists())

    def test_reset_reverts_existing_mapping(self):
        self.overrides({"30": {"spell_ids": [], "source": "checked"}})
        self.run_update()
        self.overrides({"30": {"reset": True, "source": "correction"}})
        report = self.run_update()
        snapshot = json.loads((self.root / "Database/forever.json").read_text(encoding="utf-8"))
        self.assertNotIn("30", snapshot["npcs"])
        self.assertTrue(report["npc_changes"][0]["reset_to_baseline"])
        self.assertEqual(report["npc_changes"][0]["added_spells"], [11918])

    def test_unknown_curated_spell_preserves_database(self):
        self.overrides({"30": {"spell_ids": [100], "source": "checked"}})
        original = (self.root / "Database/forever.lua").read_bytes()
        with self.assertRaisesRegex(updater.UpdateError, "without Wago names"):
            self.run_update()
        self.assertEqual((self.root / "Database/forever.lua").read_bytes(), original)

    def test_source_failure_never_replaces_live_database(self):
        original = (self.root / "Database/forever.lua").read_bytes()
        class Offline(FakeWago):
            def table(self, name, build, language): raise updater.UpdateError("HTTP 429")
        with self.assertRaises(updater.UpdateError):
            self.run_update(Offline)
        self.assertEqual((self.root / "Database/forever.lua").read_bytes(), original)
        self.assertFalse((self.root / "Database/forever.json").exists())

    def test_write_failure_restores_database_and_snapshot(self):
        self.run_update()
        original = (self.root / "Database/forever.lua").read_bytes()
        old_state = (self.root / "Database/forever.json").read_bytes()
        snapshot = json.loads(old_state)
        snapshot["abilities"]["en"]["11918"]["name"] = "Changed"
        real_write = updater.atomic_write
        calls = 0
        def fail_second(path, content):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("Disk error")
            real_write(path, content)
        with patch.object(updater, "atomic_write", fail_second), self.assertRaises(OSError):
            updater.commit_update(self.root, self.root / "Updater/.data", snapshot, updater.render_lua(snapshot))
        self.assertEqual((self.root / "Database/forever.lua").read_bytes(), original)
        self.assertEqual((self.root / "Database/forever.json").read_bytes(), old_state)

    def test_missing_state_does_not_overwrite_populated_database(self):
        self.run_update()
        (self.root / "Database/forever.json").unlink()
        with self.assertRaisesRegex(updater.UpdateError, "Snapshot"):
            self.run_update()

    def test_build_selection_is_limited_to_forever(self):
        with tempfile.TemporaryDirectory() as temp:
            provider = updater.Wago(Path(temp))
            builds = {"wow_classic_beta": [{"version": "5.5.0.70099"},
                                            {"version": "1.60.1.70009"},
                                            {"version": "1.60.1.70058"}]}
            with patch.object(provider, "cached", return_value=builds):
                self.assertEqual(provider.build(), "1.60.1.70058")

    def test_limited_wowhead_lookup_only_when_requested(self):
        self.args.npc = [30]
        class OneNpc:
            requests = 1
            cache_hits = 0
            def __init__(self, *args): pass
            def npc(self, npc_id):
                self_id = npc_id
                return {"name": f"NPC {self_id}", "spell_ids": [99]}
        with patch.object(updater, "Wowhead", OneNpc):
            report = self.run_update()
        self.assertEqual(report["scope"]["mode"], "selected")
        self.assertEqual(report["npc_changes"][0]["added_spells"], [99])


class ShippedDataTests(unittest.TestCase):
    def test_snapshot_matches_generated_runtime_data(self):
        root = MODULE.parents[2]
        snapshot = json.loads((root / "Database/forever.json").read_text(encoding="utf-8"))
        self.assertEqual(updater.render_lua(snapshot), (root / "Database/forever.lua").read_text(encoding="utf-8"))

    def test_baseline_tables_have_no_duplicate_numeric_keys(self):
        import re
        root = MODULE.parents[2]
        for path in [root / "Database/npcs.lua", root / "Database/priorities.lua", *sorted((root / "Database/Abilities").glob("*.lua"))]:
            keys = re.findall(r"^\s*\[(\d+)\]\s*=", path.read_text(encoding="utf-8-sig"), re.M)
            self.assertEqual(len(keys), len(set(keys)), str(path))


if __name__ == "__main__":
    unittest.main()
