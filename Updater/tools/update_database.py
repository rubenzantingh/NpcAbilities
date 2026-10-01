#!/usr/bin/env python3
"""Update Forever spells from Wago CSVs and NPC mappings from local combat logs."""
from __future__ import annotations

import argparse
import csv
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import html
from http.client import HTTPException
import json
import io
import os
from pathlib import Path
import re
import sys
import tempfile
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[2]
BASE_URL = "https://www.wowhead.com/forever"
WAGO_URL = "https://wago.tools"
FIELDS = ("name", "description", "mechanic", "range", "cast_time", "cooldown", "dispel_type")
LOCALES_WAGO = {
    "en": "enUS",
    "de": "deDE",
    "es": "esES",
    "fr": "frFR",
    "pt": "ptBR",
    "ru": "ruRU",
    "ko": "koKR",
    "cn": "zhCN",
}
LOCALES = set(LOCALES_WAGO)
DEFAULT_LOCALES = ["en", "de", "es", "fr", "pt", "ru", "ko", "cn"]


class UpdateError(Exception):
    """A source, validation or installation failure; existing data must survive."""


class MissingPage(UpdateError):
    pass


def progress(message):
    print(message, flush=True)


def download_wago(request, timeout):
    """Bound the entire request, including DNS/TLS and slowly streamed bodies.

    A socket timeout alone does not limit total download time. The worker only
    reads bytes; it never writes cache or addon files after cancellation.
    """
    done = threading.Event()
    state = {"received": 0}
    limit = 12 * 1024 * 1024

    def fetch():
        try:
            with urlopen(request, timeout=min(60, timeout)) as response:
                if not response.geturl().startswith(WAGO_URL + "/"):
                    raise UpdateError("Wago redirected to another site.")
                chunks = []
                while True:
                    chunk = response.read1(min(64 * 1024, limit + 1 - state["received"]))
                    if not chunk:
                        break
                    chunks.append(chunk)
                    state["received"] += len(chunk)
                    if state["received"] > limit:
                        raise UpdateError("Unexpectedly large Wago export.")
                state["data"] = b"".join(chunks)
        except Exception as error:
            state["error"] = error
        finally:
            done.set()

    started = time.monotonic()
    threading.Thread(target=fetch, daemon=True).start()
    while True:
        remaining = timeout - (time.monotonic() - started)
        if remaining <= 0:
            raise UpdateError(f"Wago request timed out (timeout {timeout:g} seconds): {request.full_url}. "
                              "Please try again later; existing addon data is preserved.")
        if done.wait(min(5, remaining)):
            if "error" in state:
                raise state["error"]
            progress(f"  Download complete: {state['received'] / 1024:.0f} KiB in {time.monotonic() - started:.1f} s")
            return state["data"]
        progress(f"  Waiting for Wago: {time.monotonic() - started:.0f} s; "
                 f"{state['received'] / 1024:.0f} KiB received (timeout {timeout:g} s)")


def timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        file.write(content.encode("utf-8"))
        file.flush()
        os.fsync(file.fileno())
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_json(path, value):
    atomic_write(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


@contextmanager
def update_lock(directory):
    """The OS releases this lock after a crash; no stale PID-file removal needed."""
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "update.lock").open("a+b") as file:
        file.seek(0)
        file.write(b"0")
        file.flush()
        file.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise UpdateError("A database update is already running.") from error
        try:
            yield
        finally:
            file.seek(0)
            if os.name == "nt":
                msvcrt.locking(file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(file, fcntl.LOCK_UN)


class LiteralReader:
    """Parse JSON-like JS data, never execute scripts. Supports unquoted object keys."""
    def __init__(self, text, position=0):
        self.text, self.position = text, position

    def skip(self):
        while self.position < len(self.text) and self.text[self.position].isspace():
            self.position += 1

    def string(self):
        quote = self.text[self.position]
        self.position += 1
        result = []
        while self.position < len(self.text):
            char = self.text[self.position]
            self.position += 1
            if char == quote:
                return "".join(result)
            if char == "\\":
                if self.position >= len(self.text):
                    break
                char = self.text[self.position]
                self.position += 1
                if char in "ux":
                    size = 4 if char == "u" else 2
                    value = self.text[self.position:self.position + size]
                    if not re.fullmatch(r"[0-9a-fA-F]{%d}" % size, value):
                        raise UpdateError("Invalid character escape in source data.")
                    result.append(chr(int(value, 16)))
                    self.position += size
                elif char in "\\/\"'":
                    result.append(char)
                elif char in "bfnrt":
                    result.append(dict(b="\b", f="\f", n="\n", r="\r", t="\t")[char])
                else:
                    raise UpdateError("Unknown character escape in source data.")
            else:
                result.append(char)
        raise UpdateError("Incomplete string in source data.")

    def value(self, depth=0):
        if depth > 40:
            raise UpdateError("Source data is nested too deeply.")
        self.skip()
        if self.position >= len(self.text):
            raise UpdateError("Incomplete source data.")
        char = self.text[self.position]
        if char in "\"'":
            return self.string()
        if char in "[{":
            mapping = char == "{"
            end = "}" if mapping else "]"
            result = {} if mapping else []
            self.position += 1
            while True:
                self.skip()
                if self.text[self.position:self.position + 1] == end:
                    self.position += 1
                    return result
                if mapping:
                    if self.text[self.position:self.position + 1] in ("'", '"'):
                        key = self.string()
                    else:
                        match = re.match(r"[A-Za-z_$][\w$]*", self.text[self.position:])
                        if not match:
                            raise UpdateError("Invalid object key in source data.")
                        key = match[0]
                        self.position += len(key)
                    self.skip()
                    if self.text[self.position:self.position + 1] != ":":
                        raise UpdateError("Missing colon in source data.")
                    self.position += 1
                    if key in result:
                        raise UpdateError("Duplicate object key in source data.")
                    result[key] = self.value(depth + 1)
                else:
                    result.append(self.value(depth + 1))
                self.skip()
                if self.text[self.position:self.position + 1] == ",":
                    self.position += 1
                elif self.text[self.position:self.position + 1] != end:
                    raise UpdateError("Unexpected data structure; update cancelled.")
        match = re.match(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true\b|false\b|null\b", self.text[self.position:])
        if match:
            self.position += len(match[0])
            return json.loads(match[0])
        raise UpdateError("Executable JavaScript expression instead of data; update cancelled.")


def listview(page, view_id):
    """Only decode the data array, not callbacks/references in the Listview config."""
    for match in re.finditer(r"new\s+Listview\s*\(\s*\{", page):
        start = match.end()
        next_script = page.find("</script>", start)
        limit = next_script if next_script >= 0 else len(page)
        # A view's identifying properties precede its data array on Wowhead.
        data_match = re.search(r"(?:\"data\"|'data'|\bdata)\s*:\s*\[", page[start:limit])
        if not data_match:
            continue
        header = page[start:start + data_match.start()]
        id_match = re.search(r"(?:\"id\"|'id'|\bid)\s*:\s*(['\"])(.*?)\1", header)
        if not id_match or id_match[2] != view_id:
            continue
        reader = LiteralReader(page, start + data_match.end() - 1)
        rows = reader.value()
        tail = page[reader.position:limit].split("new Listview", 1)[0]
        truncated = bool(re.search(r"(?:[\"']?_truncated[\"']?)\s*:\s*(?:1|true)\b", header + tail))
        return rows, truncated
    return None


def positive_id(value):
    if type(value) is not int or not 0 < value <= 2147483647:
        raise UpdateError("Invalid NPC/spell ID in source data.")
    return value


def page_identity(page, kind, entity_id):
    match = re.search(r"\b(?:var\s+)?g_pageInfo\s*=\s*", page)
    if not match:
        raise UpdateError("Wowhead page has no entity identifier (error page or changed format).")
    info = LiteralReader(page, match.end()).value()
    if info.get("type") != kind or info.get("typeId") != entity_id:
        raise UpdateError("Wowhead returned a different entity than requested.")
    return info


def env_status(row):
    change = row.get("envChange", {})
    if not isinstance(change, dict):
        raise UpdateError("Invalid Forever change data.")
    return change.get("status", "unknown")


def parse_npc(page, npc_id):
    info = page_identity(page, 1, npc_id)
    match = re.search(r"\$\.extend\(g_npcs\[" + str(npc_id) + r"\],\s*", page)
    metadata = LiteralReader(page, match.end()).value() if match else {}
    status = env_status(metadata)
    result = {"name": info["name"], "status": status, "removed": status == "removed"}
    if result["removed"]:
        return dict(result, spell_ids=[])
    view = listview(page, "abilities")
    if view is None:
        # No tab is not an explicit statement that the NPC lost all its spells.
        return dict(result, spell_ids=None)
    rows, truncated = view
    if truncated:
        raise UpdateError(f"Ability list for NPC {npc_id} is truncated.")
    ids = set()
    for row in rows:
        spell_id = positive_id(row.get("id"))
        if env_status(row) != "removed":
            ids.add(spell_id)
    return dict(result, spell_ids=sorted(ids))


class Wowhead:
    def __init__(self, directory, delay=0.75, ttl_hours=24, refresh=False):
        self.directory = directory
        self.delay, self.ttl, self.refresh = delay, ttl_hours * 3600, refresh
        self.last_request = 0
        self.requests = self.cache_hits = 0

    def get(self, url):
        for attempt in range(3):
            time.sleep(max(0, self.delay - (time.monotonic() - self.last_request)))
            self.last_request = time.monotonic()
            self.requests += 1
            request = Request(url, headers={"User-Agent": "NpcAbilitiesForever-Updater/1.0 (personal addon database update)", "Accept-Language": "en-US,en;q=0.8"})
            try:
                with urlopen(request, timeout=35) as response:
                    final_url = response.geturl()
                    if not final_url.startswith(BASE_URL + "/"):
                        raise UpdateError("Wowhead redirected to a different game version/site.")
                    data = response.read(8 * 1024 * 1024 + 1)
                    if len(data) > 8 * 1024 * 1024:
                        raise UpdateError("Unexpectedly large Wowhead response.")
                    page = data.decode("utf-8")
                    if "g_pageInfo" not in page and "new Listview" not in page:
                        raise UpdateError("Wowhead returned no data (possibly an access check). No data was replaced.")
                    return page
            except HTTPError as error:
                if error.code == 404:
                    raise MissingPage(f"Not found: {url} (404 does not prove removal).") from error
                if error.code in (401, 403, 429):
                    raise UpdateError(f"Wowhead HTTP {error.code}: Access/rate limit. Please try again later; the cache is preserved.") from error
                if error.code < 500 or attempt == 2:
                    raise UpdateError(f"Wowhead HTTP {error.code}: {url}") from error
            except (URLError, TimeoutError, OSError, UnicodeError) as error:
                if attempt == 2:
                    raise UpdateError(f"Download failed: {url}: {error}") from error
            time.sleep(2 ** attempt)
        raise UpdateError("Download failed.")

    def cached(self, url, parser):
        key = hashlib.sha256(url.encode()).hexdigest()
        path = self.directory / (key + ".json")
        if not self.refresh and path.exists():
            try:
                entry = json.loads(path.read_text(encoding="utf-8"))
                if entry.get("version") == 1 and entry.get("url") == url and time.time() - entry["time"] < self.ttl:
                    self.cache_hits += 1
                    return entry["data"]
            except (ValueError, KeyError, OSError):
                pass
        data = parser(self.get(url))
        write_json(path, {"version": 1, "url": url, "time": time.time(), "data": data})
        return data

    def npc(self, npc_id):
        return self.cached(f"{BASE_URL}/npc={npc_id}", lambda page: parse_npc(page, npc_id))


class Wago:
    """A build lookup and two CSV tables per locale; never crawl spell pages."""
    def __init__(self, directory, delay=0.75, ttl_hours=24, refresh=False):
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)
        self.delay, self.ttl, self.refresh = delay, ttl_hours * 3600, refresh
        self.last_request = 0
        self.requests = self.cache_hits = 0
        self.timeout = 120

    def cached(self, url, parser):
        path = self.directory / (hashlib.sha256(url.encode()).hexdigest() + ".data")
        if not self.refresh and path.exists() and time.time() - path.stat().st_mtime < self.ttl:
            try:
                progress(f"  Reading cache: {url}")
                result = parser(path.read_bytes())
                self.cache_hits += 1
                return result
            except (ValueError, UnicodeError, KeyError, csv.Error, UpdateError):
                progress("  Invalid cache; downloading again.")
        time.sleep(max(0, self.delay - (time.monotonic() - self.last_request)))
        self.last_request = time.monotonic()
        self.requests += 1
        request = Request(url, headers={"User-Agent": "NpcAbilitiesForever-Updater/2.0 (personal addon database update)"})
        progress(f"  Download: {url}")
        try:
            raw = download_wago(request, self.timeout)
        except HTTPError as error:
            raise UpdateError(f"Wago HTTP {error.code}; Data unchanged. For HTTP 429, please try again later.") from error
        except (URLError, TimeoutError, OSError, HTTPException) as error:
            raise UpdateError(f"Wago download failed: {error}") from error
        try:
            progress("  Validating downloaded data ...")
            result = parser(raw)
        except (ValueError, UnicodeError, KeyError, csv.Error) as error:
            raise UpdateError(f"Invalid Wago data: {url}: {error}") from error
        path.write_bytes(raw)
        return result

    def build(self):
        data = self.cached(WAGO_URL + "/api/builds", lambda raw: json.loads(raw.decode("utf-8")))
        versions = [entry["version"] for entry in data.get("wow_classic_beta", [])
                    if re.fullmatch(r"1\.60\.\d+\.\d+", entry.get("version", ""))]
        if not versions:
            raise UpdateError("No Forever build (1.60.x) found on Wago; no other client will be used.")
        return max(versions, key=lambda item: tuple(map(int, item.split("."))))

    def table(self, name, build, locale):
        query = urlencode({"build": build, "locale": LOCALES_WAGO[locale]})
        url = f"{WAGO_URL}/db2/{name}/csv?{query}"
        def parse(raw):
            reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
            required = {"ID", "Name_lang"} if name == "SpellName" else {"ID", "Description_lang"}
            if not reader.fieldnames or not required.issubset(reader.fieldnames):
                raise ValueError(f"Missing columns: {name}")
            rows = {}
            for row in reader:
                if None in row or any(value is None for value in row.values()):
                    raise ValueError(f"Malformed CSV row in {name}")
                if row["ID"] == "0":
                    continue
                key = str(positive_id(int(row["ID"])))
                if key in rows:
                    raise ValueError(f"Duplicate spell ID {key}")
                rows[key] = row
            if len(rows) < 10000:
                raise ValueError(f"Incomplete {name} export ({len(rows)} rows)")
            return rows
        return self.cached(url, parse)


def baseline_npcs(root):
    result = {}
    source = (root / "Database/npcs.lua").read_text(encoding="utf-8-sig")
    for match in re.finditer(r"\[(\d+)\]\s*=\s*\{sod_spell_ids\s*=\s*\{[^}]*\},\s*classic_spell_ids\s*=\s*\{([^}]*)\}\s*\}", source):
        result[match[1]] = sorted(set(int(value) for value in re.findall(r"\d+", match[2])))
    if not result:
        raise UpdateError("Could not read Classic baseline data.")
    return result


def empty_snapshot():
    return {"schema_version": 2, "source": WAGO_URL, "build": None, "npcs": {}, "abilities": {language: {} for language in DEFAULT_LOCALES}}


def validate_snapshot(snapshot):
    if (snapshot.get("schema_version"), snapshot.get("source")) not in ((1, BASE_URL), (2, WAGO_URL)):
        raise UpdateError("Unknown local Forever data format.")
    if not isinstance(snapshot.get("npcs"), dict) or not isinstance(snapshot.get("abilities"), dict):
        raise UpdateError("Invalid Forever data.")
    for language, spells in snapshot["abilities"].items():
        if language not in LOCALES or not isinstance(spells, dict):
            raise UpdateError("Invalid localization data.")
        for key, fields in spells.items():
            positive_id(int(key))
            if not isinstance(fields, dict) or not fields.get("name"):
                raise UpdateError("Spell has no name.")
            if any(value is not None and not isinstance(value, str) for value in fields.values()):
                raise UpdateError("Invalid spell text.")
    for key, npc in snapshot["npcs"].items():
        positive_id(int(key))
        if not isinstance(npc["spell_ids"], list):
            raise UpdateError("NPC has no valid ability list.")
        for spell_id in npc["spell_ids"]:
            positive_id(spell_id)
            # The shipped Classic spell tables remain available as a fallback.


def lua_string(value):
    if value is None:
        return "nil"
    # Literal Lua strings: never let downloaded text become code or texture markup.
    value = value.replace("|", "||")
    value = value.replace("\\", "\\\\").replace('"', '\\"')
    value = re.sub(r"[\x00-\x1f\x7f]", lambda match: "\\%03d" % ord(match[0]), value)
    return '"' + value + '"'


def render_lua(snapshot):
    validate_snapshot(snapshot)
    lines = ["-- Generated by Updater/tools/update_database.py; do not edit by hand.",
             "-- Source: " + snapshot["source"] + (" (" + snapshot["build"] + ")" if snapshot.get("build") else ""),
             '_G["NpcAbilitiesForeverData"] = {', "    npcs = {"]
    for key in sorted(snapshot["npcs"], key=int):
        ids = ", ".join(map(str, snapshot["npcs"][key]["spell_ids"]))
        authoritative = "false" if snapshot["npcs"][key].get("source") in ("Forever combat log", "Forever-Kampfprotokoll") else "true"
        lines.append(f"        [{key}] = {{classic_spell_ids = {{{ids}}}, sod_spell_ids = {{}}, authoritative = {authoritative}}},")
    lines += ["    },", "    abilities = {"]
    for language in sorted(snapshot["abilities"]):
        lines.append(f'        ["{language}"] = {{')
        for key in sorted(snapshot["abilities"][language], key=int):
            fields = snapshot["abilities"][language][key]
            values = ", ".join(field + " = " + lua_string(fields[field]) for field in FIELDS if fields.get(field) is not None)
            lines.append(f"            [{key}] = {{{values}}},")
        lines.append("        },")
    lines += ["    },", "}", ""]
    return "\n".join(lines)


def make_report(before, after, baseline, unknown, missing, scope):
    changes = []
    for key in sorted(set(before["npcs"]) | set(after["npcs"]), key=int):
        npc = after["npcs"].get(key)
        old = before["npcs"].get(key)
        old_ids = set(old["spell_ids"] if old else baseline.get(key, []))
        new_ids = set(npc["spell_ids"] if npc else baseline.get(key, []))
        added, removed = sorted(new_ids - old_ids), sorted(old_ids - new_ids)
        name_changed = bool(old and npc and old.get("name") != npc.get("name"))
        if added or removed or old is None or npc is None or name_changed:
            changes.append({"id": int(key), "name": (npc or old)["name"],
                            "new_to_database": npc is not None and key not in baseline and old is None,
                            "reset_to_baseline": npc is None,
                            "name_changed": name_changed,
                            "removed_npc": npc.get("removed", False) if npc else False,
                            "added_spells": added, "removed_spells": removed})
    new_spells = changed_spells = 0
    for language, spells in after["abilities"].items():
        for key, data in spells.items():
            old = before["abilities"].get(language, {}).get(key)
            if old is None:
                new_spells += 1
            elif old != data:
                changed_spells += 1
    return {"time": timestamp(), "source": WAGO_URL, "build": after.get("build"), "scope": scope, "npc_changes": changes,
            "new_localized_spell_entries": new_spells, "changed_localized_spell_entries": changed_spells,
            "unconfirmed_npcs_kept": unknown, "missing_pages_kept": missing}


def commit_update(root, directory, snapshot, content):
    targets = {root / "Database/forever.lua": content,
               root / "Database/forever.json": json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n"}
    if all(path.exists() and path.read_text(encoding="utf-8") == value for path, value in targets.items()):
        return None
    backup = directory / "backups" / datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    backup.mkdir(parents=True)
    old = {}
    for path in targets:
        old[path] = path.read_bytes() if path.exists() else None
        if old[path] is not None:
            (backup / path.name).write_bytes(old[path])
    try:
        # The addon only reads this single file, atomically replaced on the same volume.
        for path, value in targets.items():
            atomic_write(path, value)
    except BaseException:
        for path, value in old.items():
            if value is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, value.decode("utf-8"))
        raise
    return backup


def curated_npcs(root):
    path = root / "Database/npc_overrides.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict) or not isinstance(data.get("npcs"), dict):
        raise UpdateError("npc_overrides.json must contain an object with 'npcs'.")
    result = {}
    for key, value in data["npcs"].items():
        positive_id(int(key))
        if not isinstance(value, dict) or not isinstance(value.get("source"), str) or not value["source"].strip():
            raise UpdateError(f"NPC {key}: a source/observation is required.")
        if value.get("reset") is True:
            result[str(int(key))] = None
            continue
        ids = value.get("spell_ids")
        if not isinstance(ids, list) or any(not isinstance(item, int) or isinstance(item, bool) for item in ids):
            raise UpdateError(f"NPC {key}: spell_ids must be a list of IDs.")
        result[str(int(key))] = {"name": value.get("name") or str(key),
                                  "spell_ids": sorted({positive_id(item) for item in ids}),
                                  "source": value["source"].strip()}
    return result


def usable_description(raw):
    """Keep tooltip templates out of the UI until their tokens can be resolved."""
    if not raw or "$" in raw or "|" in raw or "\ufffd" in raw or re.search(r"<[^>]+>", raw):
        return None
    return html.unescape(raw).strip() or None


COMBAT_LINE = re.compile(r"^\ufeff?\s*\d{1,2}/\d{1,2}\s+\d{1,2}:\d{2}:\d{2}\.\d+\s+(.+)$")
CREATURE_GUID = re.compile(r"^Creature-(?:[^-]+-){4}(\d+)-[^-]+$")
CAST_EVENTS = {"SPELL_CAST_START", "SPELL_CAST_SUCCESS"}


def combat_log_paths(root, explicit):
    """Find only Forever's log, or use explicitly configured local paths."""
    paths = list(explicit or [])
    config = root / "Updater/.data/config.json"
    if not paths and config.exists():
        value = json.loads(config.read_text(encoding="utf-8-sig"))
        if not isinstance(value, dict) or not isinstance(value.get("combat_logs"), list) or any(
            not isinstance(item, str) or not item.strip() for item in value["combat_logs"]
        ):
            raise UpdateError("Updater/.data/config.json: 'combat_logs' must be a list of paths.")
        paths = [Path(item) for item in value["combat_logs"]]
    if not paths:
        if root.parent.name.lower() == "addons" and root.parent.parent.name.lower() == "interface":
            paths.append(root.parent.parent.parent / "Logs/WoWCombatLog.txt")
        for variable in ("ProgramFiles(x86)", "ProgramFiles"):
            directory = os.environ.get(variable)
            if directory:
                paths.append(Path(directory) / "World of Warcraft/_classic_beta_/Logs/WoWCombatLog.txt")
    unique = []
    for path in paths:
        path = Path(path).expanduser().resolve()
        if path.is_dir():
            path = path / ("WoWCombatLog.txt" if path.name.lower() == "logs" else "Logs/WoWCombatLog.txt")
        if path not in unique:
            unique.append(path)
    if explicit or config.exists():
        missing = [str(path) for path in unique if not path.is_file()]
        if missing:
            raise UpdateError("Combat log not found: " + ", ".join(missing))
    return [path for path in unique if path.is_file()]


def parse_combat_log(path, known_spells):
    """Read observed NPC casts only; absence of a cast never removes a spell."""
    observed = {}
    headers = casts = 0
    is_forever = False
    builds = set()
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as file:
        for line in file:
            match = COMBAT_LINE.match(line)
            if not match:
                continue
            try:
                row = next(csv.reader([match[1]]))
            except csv.Error:
                continue
            if not row:
                continue
            if row[0] == "COMBAT_LOG_VERSION":
                headers += 1
                version = row[row.index("BUILD_VERSION") + 1] if "BUILD_VERSION" in row and row.index("BUILD_VERSION") + 1 < len(row) else ""
                is_forever = bool(re.fullmatch(r"1\.60\.\d+(?:\.\d+)?", version))
                if is_forever:
                    builds.add(version)
                continue
            if not is_forever or row[0] not in CAST_EVENTS or len(row) < 12:
                continue
            guid = CREATURE_GUID.fullmatch(row[1])
            if not guid:
                continue
            try:
                flags = int(row[3], 16)
                npc_id = positive_id(int(guid[1]))
                spell_id = positive_id(int(row[9]))
            except (ValueError, UpdateError):
                continue
            if not flags & 0x800 or flags & 0x100 or str(spell_id) not in known_spells:
                continue
            name = row[2] if row[2] not in ("", "nil") and "\ufffd" not in row[2] else str(npc_id)
            npc = observed.setdefault(str(npc_id), {"name": name, "spell_ids": set()})
            npc["spell_ids"].add(spell_id)
            casts += 1
    return {"npcs": observed, "headers": headers, "builds": sorted(builds), "cast_events": casts}


def run(args):
    root = args.root.resolve()
    directory = root / "Updater/.data"
    progress(f"Updater started. Addon directory: {root}")
    progress("[1/5] Reading existing data ...")
    with update_lock(directory):
        baseline = baseline_npcs(root)
        path = root / "Database/forever.json"
        before = json.loads(path.read_text(encoding="utf-8")) if path.exists() else empty_snapshot()
        validate_snapshot(before)
        if not path.exists():
            overlay = root / "Database/forever.lua"
            if overlay.exists() and re.search(r"\[\d+\]\s*=", overlay.read_text(encoding="utf-8")):
                raise UpdateError("Forever data exists, but Database/forever.json is missing. Restore the Snapshot from a backup.")
        after = json.loads(json.dumps(before))
        after.update(schema_version=2, source=WAGO_URL)
        provider = Wago(directory / "cache", args.delay, args.cache_hours, args.refresh)
        provider.timeout = getattr(args, "timeout", 120)
        progress("[2/5] Looking up the Forever build on Wago ..." if not args.build else "[2/5] Using the specified Forever build ...")
        build = args.build or provider.build()
        if not re.fullmatch(r"1\.60\.\d+\.\d+", build):
            raise UpdateError("Only Forever builds (1.60.x) may be imported.")
        after["build"] = build
        print(f"Forever build: {build}", flush=True)
        tables = {}
        progress("[3/5] Downloading the spell catalog ...")
        for language in args.languages:
            progress(f"  Language: {language}")
            tables[language] = (provider.table("SpellName", build, language),
                                provider.table("Spell", build, language))
            print(f"{language}: {len(tables[language][0])} spell names loaded", flush=True)

        progress("[4/5] Processing spells and existing NPC associations ...")
        unknown, missing = [], []
        wowhead = None
        selected_npc_spells = set()
        if args.npc:
            wowhead = Wowhead(directory / "cache", args.delay, args.cache_hours, args.refresh)
            for npc_id in args.npc:
                try:
                    npc = wowhead.npc(npc_id)
                except MissingPage as error:
                    missing.append({"id": npc_id, "reason": str(error)})
                    continue
                if npc["spell_ids"] is None:
                    unknown.append({"id": npc_id, "name": npc["name"], "reason": "No complete abilities tab"})
                    continue
                npc["source"] = f"{BASE_URL}/npc={npc_id}"
                after["npcs"][str(npc_id)] = npc
                selected_npc_spells.update(npc["spell_ids"])

        log_reports = []
        observed_npc_ids = set()
        for log_path in combat_log_paths(root, getattr(args, "combat_log", None)):
            progress(f"  Reading combat log: {log_path}")
            observations = parse_combat_log(log_path, tables["en"][0])
            if not observations["builds"]:
                raise UpdateError(f"Not a Forever combat log (Build 1.60.x): {log_path}")
            log_reports.append({"file": str(log_path), "builds": observations["builds"],
                                "npc_count": len(observations["npcs"]), "cast_events": observations["cast_events"]})
            for key, seen in observations["npcs"].items():
                previous = after["npcs"].get(key)
                old_ids = set(previous["spell_ids"] if previous else baseline.get(key, []))
                new_ids = old_ids | seen["spell_ids"]
                if new_ids == old_ids and (previous or key in baseline):
                    continue
                after["npcs"][key] = {"name": (previous or seen)["name"],
                                       "spell_ids": sorted(new_ids), "source": "Forever combat log"}
                observed_npc_ids.add(key)

        curated = curated_npcs(root)
        for key, npc in curated.items():
            if npc is None:
                after["npcs"].pop(key, None)
            else:
                after["npcs"][key] = npc

        # Import the whole spell catalog, including spells not yet assigned to a known NPC.
        required = {int(key) for key in tables["en"][0]}
        required.update(spell for ids in baseline.values() for spell in ids)
        required.update(spell for npc in after["npcs"].values() for spell in npc["spell_ids"])
        new_npc_spells = selected_npc_spells | {spell for npc in curated.values() if npc for spell in npc["spell_ids"]}
        missing_override_spells = sorted(spell for spell in new_npc_spells if str(spell) not in tables["en"][0])
        if missing_override_spells:
            raise UpdateError(f"New NPC association contains spells without Wago names: {missing_override_spells[:20]}")
        skipped_templates = {language: 0 for language in args.languages}
        missing_names = {language: [] for language in args.languages}
        for language, (names, spells) in tables.items():
            localized = after["abilities"].setdefault(language, {})
            for spell_id in sorted(required):
                key = str(spell_id)
                name = names.get(key, {}).get("Name_lang", "").strip()
                if not name or "\ufffd" in name:
                    missing_names[language].append(spell_id)
                    continue
                fields = localized.setdefault(key, {})
                fields["name"] = name
                raw = spells.get(key, {}).get("Description_lang", "")
                description = usable_description(raw)
                if description:
                    fields["description"] = description
                else:
                    fields.pop("description", None)
                    if raw:
                        skipped_templates[language] += 1
        validate_snapshot(after)
        content = render_lua(after)
        scope = {"mode": "selected" if args.npc else "bulk", "npc_count": len(after["npcs"]), "languages": args.languages}
        report = make_report(before, after, baseline, unknown, missing, scope)
        report["spell_ids_checked"] = len(required)
        report["descriptions_with_unresolved_placeholders"] = skipped_templates
        report["missing_spell_names"] = missing_names
        report["curated_npc_entries"] = len(curated)
        report["combat_logs"] = log_reports
        report["observed_npc_updates"] = len(observed_npc_ids)
        report["dry_run"] = args.dry_run
        report["http_requests"] = provider.requests + (wowhead.requests if wowhead else 0)
        report["cache_hits"] = provider.cache_hits + (wowhead.cache_hits if wowhead else 0)
        report_path = directory / ("preview-report.json" if args.dry_run else "last-report.json")
        progress("[5/5] Writing preview ..." if args.dry_run else "[5/5] Saving data and backup ...")
        if args.dry_run:
            atomic_write(directory / "preview-forever.lua", content)
            print("Preview: addon data unchanged.")
        else:
            backup = commit_update(root, directory, after, content)
            report["backup"] = str(backup) if backup else None
            print("Update installed. In WoW: /reload" if backup else "Data is already up to date.")
        write_json(report_path, report)
        print(f"NPC entries: {len(after['npcs'])}; Changes: {len(report['npc_changes'])}; "
              f"new localized spell entries: {report['new_localized_spell_entries']}; "
              f"changed texts: {report['changed_localized_spell_entries']}")
        print(f"HTTP requests: {report['http_requests']}; Cache hits: {report['cache_hits']}; "
              f"unresolved descriptions: {skipped_templates}")
        if log_reports:
            print(f"Combat logs: {len(log_reports)}; NPC associations extended from observed spells: {len(observed_npc_ids)}")
        else:
            print("No log file imported. The addon learns new NPC spell associations in-game.")
        print(f"Report: {report_path}")
        return report


def main():
    parser = argparse.ArgumentParser(description="Update Forever spells from Wago CSVs (Python 3.10+, no extra packages).")
    parser.add_argument("--root", type=Path, default=ROOT, help="Addon directory")
    parser.add_argument("--dry-run", action="store_true", help="Generate a preview without changing addon data")
    parser.add_argument("--npc", nargs="+", type=int, help="Check only these NPC IDs on Wowhead (no full crawl)")
    parser.add_argument("--combat-log", nargs="+", type=Path, help="Import a Forever game directory or WoWCombatLog.txt to associate NPC spells")
    parser.add_argument("--build", help="Use a specific Forever build, 1.60.x")
    parser.add_argument("--languages", nargs="+", choices=sorted(LOCALES_WAGO), default=DEFAULT_LOCALES,
                        help="Wago languages (default: all supported languages; English is always required)")
    parser.add_argument("--refresh", action="store_true", help="Ignore the cache and download all requested data again")
    parser.add_argument("--cache-hours", type=float, default=24, help="Cache validity in hours")
    parser.add_argument("--delay", type=float, default=0.75, help="Minimum delay between HTTP requests (seconds, at least 0.5)")
    parser.add_argument("--timeout", type=int, default=120, help="Total timeout per Wago request in seconds (default: 120)")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("The timeout must be greater than zero.")
    if args.delay < 0.5 or args.cache_hours < 0 or (args.npc and any(value <= 0 or value > 2147483647 for value in args.npc)):
        parser.error("Invalid ID, cache duration or request delay (minimum 0.5 seconds).")
    args.languages = list(dict.fromkeys(["en"] + args.languages))
    try:
        run(args)
    except KeyboardInterrupt:
        print("\nCancelled. Downloaded data remains cached; run again to resume.", file=sys.stderr)
        return 130
    except (UpdateError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"\nERROR: {error}\nNo complete update installed. Details and cache are in Updater/.data.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
