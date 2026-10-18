#!/usr/bin/env python3
"""Commander Ladder feed: arena ratings from Blizzard's web API, as a Lua file the game loads.

    python3 -I ladder_feed.py probe   # check credentials, namespaces and endpoints; changes nothing
    python3 -I ladder_feed.py fields  # the field names of one ladder entry and one profile summary
    python3 -I ladder_feed.py run     # pull the ladders + wanted profiles, write CommanderLadderData.lua

The game only tells an addon another player's rating through an inspect (own faction, ~28 yards).
Everyone else comes from here: the same web API ironforge.pro reads. Commander_Muster merges it
with what it has seen in game (its D11); the newest reading wins per bracket.

For the home realm's ladder players a run also writes who they are -- faction, class, race, last
login and guild, from each one's character profile summary (L9) -- which Commander_Recruit uses
to aim its /who sweep. Those summaries are cached in ~/Library/Caches/CommanderLadder/ (outside
the repo; COMMANDER_LADDER_CACHE overrides) and fetched again once a week.

Credentials live in the macOS login Keychain, stored by Devin with:
    security add-generic-password -a "$USER" -s commander-battlenet-client-id -w
    security add-generic-password -a "$USER" -s commander-battlenet-client-secret -w
They are read with `security find-generic-password` and never printed, logged or written.

Standard library only. Run with `python3 -I` so nothing beside this file is imported.
"""

import base64
import glob
import http.client
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent                      # .../Interface/AddOns/Commander_Ladder
GAME = ADDON.parent.parent.parent        # .../_anniversary_
DATA_FILE = ADDON / "CommanderLadderData.lua"
SV_GLOB = str(GAME / "WTF" / "Account" / "*" / "SavedVariables" / "Commander_Ladder.lua")
SHIM = HERE / "sv_to_json.lua"
LUAJIT = os.environ.get("LUAJIT", "/opt/homebrew/bin/luajit")

REGION = "us"
TOKEN_URL = "https://oauth.battle.net/token"
API_HOST = f"https://{REGION}.api.blizzard.com"
# The Anniversary namespaces first (a Feb 2026 forum reply: "classicann-{region}"), then the
# older progression-Classic ones in case the PvP endpoints only live there
DYNAMIC_NAMESPACES = [f"dynamic-classicann-{REGION}", f"dynamic-classic-{REGION}"]
PROFILE_NAMESPACES = [f"profile-classicann-{REGION}", f"profile-classic-{REGION}"]
BRACKETS = {"2v2": 2, "3v3": 3, "5v5": 5}

KEYCHAIN_ID = "commander-battlenet-client-id"
KEYCHAIN_SECRET = "commander-battlenet-client-secret"

NETWORK_ERROR = 599          # urlopen_fetch's status for a timeout, reset or DNS failure: retried like a 5xx
REQUESTS_PER_SECOND = 20     # the API allows 100/s
REQUESTS_PER_HOUR = 30000    # the API allows 36,000/h
MAX_WANTED_PER_RUN = 800     # names looked up by profile in one run (3 requests each)
CARRY_SECONDS = 7 * 86400    # how long an entry not refreshed this run is kept

PROBE_CHARACTER = ("dreamscythe", "polypopin")
PROBE_EXPECTED = {2: 1534, 3: 1531, 5: 1605}   # ironforge.pro, 2026-10-16

# Who the rated players are (L9): the character profile summary of every ladder player on these
# realms (normalized names), cached outside the repo and refreshed weekly. Commander_Recruit steers
# its /who sweep with it. Nightslayer would add ~7,900 requests a week; Devin plays Dreamscythe.
HOME_REALMS = ("Dreamscythe",)
PROFILE_CACHE = Path(os.environ.get("COMMANDER_LADDER_CACHE")
                     or Path.home() / "Library" / "Caches" / "CommanderLadder" / "profiles.json")
PROFILE_MAX_AGE = 7 * 86400      # a summary older than this is fetched again...
PROFILE_SPREAD = 2 * 86400       # ...or up to this much sooner, fixed per name, so the first fill's
                                 # ~1,600 do not all come due on the same morning
PROFILE_FORGET = 30 * 86400      # a cached summary for someone off the data this long is dropped
MAX_PROFILES_PER_RUN = 2500      # two requests each (summary, talents); the first run ~2,000
PROFILE_SCHEMA = 2               # a cached record older than this shape is fetched again (2: sex, spec)

# The game's own tokens (UnitClass / UnitRace file names), by the API's ids. 6 (death knight) and
# the later races are not TBC: a summary naming one describes nobody Recruit can /who.
CLASS_TOKENS = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN",
                8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
RACE_TOKENS = {1: "Human", 2: "Orc", 3: "Dwarf", 4: "NightElf", 5: "Scourge", 6: "Tauren",
               7: "Gnome", 8: "Troll", 10: "BloodElf", 11: "Draenei"}
RACE_FACTION = {"Human": "A", "Dwarf": "A", "NightElf": "A", "Gnome": "A", "Draenei": "A",
                "Orc": "H", "Scourge": "H", "Tauren": "H", "Troll": "H", "BloodElf": "H"}
FACTION_LETTER = {"ALLIANCE": "A", "HORDE": "H"}


class FeedError(Exception):
    pass


class MissingCredentials(FeedError):
    pass


# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

def keychain(service, runner=subprocess.run):
    """The Keychain password for `service`. Raises MissingCredentials without echoing anything."""
    user = os.environ.get("USER", "")
    try:
        done = runner(["security", "find-generic-password", "-a", user, "-s", service, "-w"],
                      capture_output=True, text=True)
    except OSError:
        raise MissingCredentials(f"could not run `security` to read {service}") from None
    value = (done.stdout or "").strip()
    if done.returncode != 0 or not value:
        raise MissingCredentials(f"Keychain item {service} is missing")
    return value


def redact(text, secrets):
    """`text` with every secret replaced. Used on anything that might reach the terminal."""
    text = str(text)
    for secret in secrets:
        if secret and len(secret) >= 4:
            text = text.replace(secret, "[redacted]")
    return text


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def urlopen_fetch(url, headers, data=None, timeout=30):
    """(status, headers, body bytes) for one request. Never raises: an HTTP status comes back as
    itself, and a network failure -- a timeout, a reset, DNS, even while reading an error's body
    (it once killed a whole run, 2026-10-18) -- as NETWORK_ERROR, which Api.get retries."""
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as err:
        try:
            body = err.read() or b""
        except (OSError, http.client.HTTPException):
            body = b""
        return err.code, dict(err.headers or {}), body
    except (OSError, http.client.HTTPException):   # URLError and TimeoutError are OSErrors
        return NETWORK_ERROR, {}, b""


class Api:
    """The Blizzard API with a token, a rate limit and a 429 backoff. `fetch` and `clock` are
    injectable so the tests run with no network."""

    def __init__(self, client_id, client_secret, fetch=urlopen_fetch, clock=time.monotonic,
                 sleep=time.sleep):
        self._id, self._secret = client_id, client_secret
        self._fetch, self._clock, self._sleep = fetch, clock, sleep
        self._token = None
        self._last = None
        self._hour_start, self._hour_count = None, 0
        self.requests = 0

    def _secrets(self):
        return [self._id, self._secret, self._token]

    def _pace(self):
        now = self._clock()
        if self._last is not None:
            wait = (1.0 / REQUESTS_PER_SECOND) - (now - self._last)
            if wait > 0:
                self._sleep(wait)
                now = self._clock()
        if self._hour_start is None or now - self._hour_start >= 3600:
            self._hour_start, self._hour_count = now, 0
        if self._hour_count >= REQUESTS_PER_HOUR:
            raise FeedError("hourly request budget spent; stopping this run")
        self._hour_count += 1
        self._last = now
        self.requests += 1

    def token(self):
        if self._token:
            return self._token
        basic = base64.b64encode(f"{self._id}:{self._secret}".encode()).decode()
        self._pace()
        status, _, body = self._fetch(
            TOKEN_URL,
            {"Authorization": f"Basic {basic}", "Content-Type": "application/x-www-form-urlencoded"},
            data=b"grant_type=client_credentials")
        if status != 200:
            raise FeedError(f"token request refused (HTTP {status}); check the Battle.net client")
        try:
            self._token = json.loads(body)["access_token"]
        except (ValueError, KeyError):
            raise FeedError("token response had no access_token") from None
        return self._token

    def get(self, path, namespace, **params):
        """The JSON at `path`, or None for a 404. Retries 429 and 5xx with backoff."""
        query = {"namespace": namespace, "locale": "en_US", **params}
        url = f"{API_HOST}{path}?{urllib.parse.urlencode(query)}"
        delay = 1.0
        for _ in range(6):
            self._pace()
            status, headers, body = self._fetch(url, {"Authorization": f"Bearer {self.token()}"})
            if status == 200:
                try:
                    return json.loads(body)
                except ValueError:
                    raise FeedError(f"{path}: response was not JSON") from None
            if status == 404:
                return None
            if status == 401:
                self._token = None   # expired: fetch a new one and try again
                continue
            if status == 429 or status >= 500:
                retry = headers.get("Retry-After") or headers.get("retry-after")
                try:
                    wait = float(retry) if retry else delay
                except ValueError:
                    wait = delay
                self._sleep(min(wait, 60))
                delay = min(delay * 2, 60)
                continue
            raise FeedError(redact(f"{path} ({namespace}): HTTP {status}", self._secrets()))
        raise FeedError(f"{path} ({namespace}): gave up after repeated throttling or network failures")


# ---------------------------------------------------------------------------
# Shapes (tolerant: the Classic PvP payloads are undocumented for Anniversary)
# ---------------------------------------------------------------------------

def normalize_realm(name):
    """A realm name the way the game's GetNormalizedRealmName() writes it: no spaces."""
    return "".join(str(name).split())


def realm_maps(index):
    """(slug -> normalized name, normalized name -> slug) from /data/wow/realm/index."""
    by_slug, by_name = {}, {}
    for realm in (index or {}).get("realms", []):
        slug, name = realm.get("slug"), realm.get("name")
        if isinstance(name, dict):
            name = name.get("en_US") or next(iter(name.values()), None)
        if slug and name:
            norm = normalize_realm(name)
            by_slug[slug] = norm
            by_name[norm] = slug
    return by_slug, by_name


def realm_from_slug(slug, by_slug):
    """The normalized realm name for a slug, guessing from the slug when the index lacks it."""
    if slug in by_slug:
        return by_slug[slug]
    return "".join(part.capitalize() for part in str(slug).split("-"))


def ids_from(index, *keys):
    """Every `id` under the first of `keys` present in `index`, e.g. pvp_regions or seasons."""
    for key in keys:
        items = (index or {}).get(key)
        if isinstance(items, list):
            out = []
            for item in items:
                if isinstance(item, dict):
                    ident = item.get("id")
                    if ident is None:
                        href = (item.get("key") or {}).get("href", "")
                        tail = href.split("?")[0].rstrip("/").split("/")[-1]
                        ident = int(tail) if tail.isdigit() else None
                    if ident is not None:
                        out.append(int(ident))
            return out
    return []


def current_season(index):
    """The current season id from a pvp-season index, else the highest listed."""
    current = (index or {}).get("current_season")
    if isinstance(current, dict) and current.get("id") is not None:
        return int(current["id"])
    seasons = ids_from(index, "seasons")
    return max(seasons) if seasons else None


def match_stats(block):
    """(won, lost) from a season_match_statistics block."""
    stats = (block or {}).get("season_match_statistics") or {}
    won, lost = int(stats.get("won") or 0), int(stats.get("lost") or 0)
    if not lost and stats.get("played") is not None:
        lost = max(int(stats["played"]) - won, 0)
    return won, lost


def parse_leaderboard(board, by_slug):
    """{ "Name-Realm": (rating, won, lost) } from one pvp-leaderboard payload."""
    out = {}
    for entry in (board or {}).get("entries", []):
        character = entry.get("character") or {}
        name = character.get("name")
        realm = character.get("realm") or {}
        slug = realm.get("slug")
        if not name or not slug:
            continue
        won, lost = match_stats(entry)
        out[f"{name}-{realm_from_slug(slug, by_slug)}"] = (int(entry.get("rating") or 0), won, lost)
    return out


def parse_bracket(payload):
    """(rating, won, lost) from a character pvp-bracket payload, or None."""
    if not payload or payload.get("rating") is None:
        return None
    won, lost = match_stats(payload)
    return int(payload["rating"]), won, lost


# ---------------------------------------------------------------------------
# Lua files in and out
# ---------------------------------------------------------------------------

def lua_global(path, name, luajit=LUAJIT):
    """A global from a Lua file, through the sandboxed sv_to_json.lua shim. None on any failure."""
    if not Path(path).exists():
        return None
    try:
        done = subprocess.run([luajit, str(SHIM), str(path), name],
                              capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if done.returncode != 0:
        return None
    try:
        return json.loads(done.stdout)
    except ValueError:
        return None


def read_wanted(paths=None, luajit=LUAJIT):
    """{ "Name-Realm": lastSeenEpoch } merged from every account's SavedVariables."""
    out = {}
    for path in (paths if paths is not None else glob.glob(SV_GLOB)):
        table = lua_global(path, "CommanderLadderWanted", luajit)
        if isinstance(table, dict):
            for key, seen in table.items():
                if isinstance(key, str) and "-" in key:
                    try:
                        seen = int(seen)
                    except (TypeError, ValueError):
                        seen = 0
                    out[key] = max(out.get(key, 0), seen)
    return out


def read_previous(path=DATA_FILE, luajit=LUAJIT):
    """The last data file as a dict, or None."""
    data = lua_global(path, "CommanderLadderData", luajit)
    return data if isinstance(data, dict) else None


def lua_string(s):
    out = ['"']
    for ch in str(s):
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch)}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def render_lua(data):
    """The data file's text: one line per player, keys sorted so runs diff cleanly."""
    lines = [
        "-- Generated by Commander_Ladder/Tools/ladder_feed.py. Do not edit; do not commit.",
        "CommanderLadderData = {",
        f"    generated = {int(data['generated'])},",
        f"    region = {lua_string(data.get('region', REGION))},",
        f"    namespace = {lua_string(data.get('namespace', ''))},",
    ]
    if data.get("season") is not None:
        lines.append(f"    season = {int(data['season'])},")
    lines.append("    players = {")
    for key in sorted(data["players"]):
        entry = data["players"][key]
        parts = []
        for size in (2, 3, 5):
            b = entry.get(size)
            if b:
                parts.append(f"[{size}] = {{ {int(b[0])}, {int(b[1])}, {int(b[2])} }}")
        if not parts:
            continue
        who = entry.get("w")
        if who:
            # faction, class, race, last login, guild (L9); the guild is left off when there is none.
            # Sex and talent tree by name (L10), each left off when not known
            fields = [lua_string(who[0]), lua_string(who[1]), lua_string(who[2]), str(int(who[3]))]
            if len(who) > 4 and who[4]:
                fields.append(lua_string(who[4]))
            if len(who) > 5 and who[5]:
                fields.append(f"sex = {lua_string(who[5])}")
            if len(who) > 6 and who[6]:
                fields.append(f"spec = {lua_string(who[6])}")
            parts.append(f"w = {{ {', '.join(fields)} }}")
        parts.append(f"t = {int(entry['t'])}")
        lines.append(f"        [{lua_string(key)}] = {{ {', '.join(parts)} }},")
    lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_atomically(path, text, suffix=".lua"):
    """Write via a temp file in the same folder and rename, so the game never loads half a file."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=".ladder-", suffix=suffix, dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def entry_from_json(raw):
    """A carried-over entry from read_previous's JSON (bracket keys arrive as strings)."""
    entry = {}
    for size in (2, 3, 5):
        b = raw.get(str(size))
        if isinstance(b, dict) and all(str(i) in b for i in (1, 2, 3)):
            entry[size] = (int(b["1"]), int(b["2"]), int(b["3"]))
    if entry and raw.get("t") is not None:
        entry["t"] = int(raw["t"])
        return entry
    return None


def carry_over(previous, players, now, season):
    """Keep last run's entries this run did not refresh, while they are under CARRY_SECONDS old
    and the season has not changed."""
    if not previous or (season is not None and previous.get("season") not in (None, season)):
        return 0
    kept = 0
    for key, raw in (previous.get("players") or {}).items():
        if key in players or not isinstance(raw, dict):
            continue
        entry = entry_from_json(raw)
        if entry and now - entry["t"] < CARRY_SECONDS:
            players[key] = entry
            kept += 1
    return kept


# ---------------------------------------------------------------------------
# Who the rated players are (L9)
# ---------------------------------------------------------------------------

def parse_summary(summary):
    """{f, c, r, g, l, x} from a character profile summary: faction letter, class and race tokens
    as the game spells them, guild name ("" for none), last login in epoch seconds (0 unknown) and
    sex ("M", "F" or ""). None when the class or race is missing or not a TBC one."""
    if not isinstance(summary, dict):
        return None
    cls = CLASS_TOKENS.get((summary.get("character_class") or {}).get("id"))
    race = RACE_TOKENS.get((summary.get("race") or {}).get("id"))
    if not (cls and race):
        return None
    faction = FACTION_LETTER.get(str((summary.get("faction") or {}).get("type") or "").upper())
    guild = (summary.get("guild") or {}).get("name") or ""
    try:
        login = int(summary.get("last_login_timestamp") or 0)
    except (TypeError, ValueError):
        login = 0
    if login > 10 ** 11:
        login //= 1000   # the retail layout sends milliseconds
    sex = {"MALE": "M", "FEMALE": "F"}.get(str((summary.get("gender") or {}).get("type") or "").upper(), "")
    return {"f": faction or RACE_FACTION[race], "c": cls, "r": race, "g": str(guild), "l": login, "x": sex}


def parse_specs(payload):
    """The talent tree a character spends most in, from the /specializations payload (L10), as the
    en_US tree name's letters in capitals ("SUBTLETY", "BEASTMASTERY", "FERALCOMBAT"); "" when it
    has none. The active group of a dual spec is read, else the first; a tree with no points is
    not listed at all."""
    groups = (payload or {}).get("specialization_groups") or []
    group = next((g for g in groups if g.get("is_active")), groups[0] if groups else None)
    best, most = "", 0
    for tree in (group or {}).get("specializations") or []:
        try:
            points = int(tree.get("spent_points") or 0)
        except (TypeError, ValueError):
            points = 0
        name = tree.get("specialization_name") or ""
        if points > most and name:
            best, most = "".join(ch for ch in str(name).upper() if "A" <= ch <= "Z"), points
    return best


def load_cache(path=None):
    """The profile cache, { "Name-Realm": {f, c, r, g, l, at} or {gone, at} }, or {}."""
    path = Path(path or PROFILE_CACHE)
    try:
        cache = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return cache if isinstance(cache, dict) else {}


def save_cache(cache, path=None):
    path = Path(path or PROFILE_CACHE)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_atomically(path, json.dumps(cache, ensure_ascii=False, sort_keys=True), suffix=".json")


def profile_max_age(key):
    """How old `key`'s summary may get: five to seven days, the same for a name every run."""
    return PROFILE_MAX_AGE - zlib.crc32(key.encode("utf-8")) % PROFILE_SPREAD


def refresh_profiles(api, namespace, keys, by_name, cache, now, limit=None, say=print):
    """Fetch the summary of every key in `keys` whose cached one is missing or about a week old
    (profile_max_age), the never-fetched first, then the oldest; at most `limit`. A 404 (renamed,
    moved, deleted) is cached as gone and asked again in a week. A spent request budget stops the
    fetching but keeps what came. Returns how many were fetched."""
    limit = MAX_PROFILES_PER_RUN if limit is None else limit

    def stale(rec):
        # a described record from before PROFILE_SCHEMA lacks fields: fetched again now
        return bool(rec) and not rec.get("gone") and int(rec.get("v") or 1) < PROFILE_SCHEMA

    due = [k for k in keys if now - int((cache.get(k) or {}).get("at") or 0) >= profile_max_age(k)
           or stale(cache.get(k))]
    due.sort(key=lambda k: (int((cache.get(k) or {}).get("at") or 0), k))
    fetched = 0
    for key in due[:limit]:
        name, _, realm = key.partition("-")
        base = f"/profile/wow/character/{urllib.parse.quote(slug_for(realm, by_name))}/{urllib.parse.quote(name.lower())}"
        try:
            summary = api.get(base, namespace)
            record = parse_summary(summary) if summary else None
            if record:
                # Their talents too (L10): one more request, a 404 is no spec
                record["s"] = parse_specs(api.get(f"{base}/specializations", namespace))
                record["v"] = PROFILE_SCHEMA
        except FeedError as err:
            say(f"Commander Ladder: profiles stopped after {fetched}: {err}")
            break
        cache[key] = dict(record or {"gone": 1}, at=now)
        fetched += 1
    return fetched


def slug_for(realm, by_name):
    return by_name.get(realm) or realm.lower()


def prune_cache(cache, keep, now):
    """Drop cached summaries for players not in `keep` and not fetched for PROFILE_FORGET."""
    keep = set(keep)
    for key in [k for k, rec in cache.items()
                if k not in keep and now - int((rec or {}).get("at") or 0) >= PROFILE_FORGET]:
        del cache[key]


def played_count(entry, size):
    b = entry.get(size) if isinstance(entry, dict) else None
    return int(b[1]) + int(b[2]) if b else None


def attach_profiles(players, cache, previous):
    """Give each home-realm player the cache knows a `w` = (faction, class, race, last login,
    guild). The last login is raised to the previous run's time when the ladder record moved
    since then: they played a match after it, so they logged in after it. The profile is a week
    old at worst; the ladder is a day old. Returns how many were described."""
    prev_players = (previous or {}).get("players") or {}
    prev_time = int((previous or {}).get("generated") or 0)
    described = 0
    for key, entry in players.items():
        if key.partition("-")[2] not in HOME_REALMS:
            continue
        rec = cache.get(key) or {}
        if rec.get("gone") or not rec.get("c"):
            continue
        last = int(rec.get("l") or 0)
        raw = prev_players.get(key)
        before = entry_from_json(raw) if isinstance(raw, dict) else None
        if isinstance(raw, dict) and isinstance(raw.get("w"), dict):
            try:
                last = max(last, int(raw["w"].get("4") or 0))
            except (TypeError, ValueError):
                pass
        if before and prev_time and any(played_count(entry, s) is not None
                                        and played_count(entry, s) != played_count(before, s)
                                        for s in (2, 3, 5)):
            last = max(last, prev_time)
        entry["w"] = (rec.get("f") or RACE_FACTION.get(rec.get("r"), ""), rec["c"], rec["r"], last,
                      rec.get("g") or "", rec.get("x") or "", rec.get("s") or "")
        described += 1
    return described


# ---------------------------------------------------------------------------
# The two commands
# ---------------------------------------------------------------------------

def connect():
    client_id = keychain(KEYCHAIN_ID)
    client_secret = keychain(KEYCHAIN_SECRET)
    return Api(client_id, client_secret)


def discover(api, say=print):
    """Which namespaces answer, and where the current season's leaderboards live.

    Two layouts exist. TBC Anniversary uses the retail one, seasons with no region level:
    /data/wow/pvp-season/{season}/pvp-leaderboard/{bracket}, about 5,000 players a bracket
    (probed 2026-10-16: season 3, 2v2/3v3/5v5 all answered). Older Classic flavours put a
    region in front: /data/wow/pvp-region/{region}/pvp-season/{season}/... The season layout
    is asked first; the region layout only when it gives nothing.

    found["boards"] is a list of (path prefix, season): a leaderboard is
    f"{prefix}/pvp-leaderboard/{bracket}".
    """
    found = {"dynamic": None, "profile": None, "boards": [], "realms": ({}, {})}
    for ns in DYNAMIC_NAMESPACES:
        index = api.get("/data/wow/realm/index", ns)
        if index and index.get("realms"):
            found["dynamic"] = ns
            found["realms"] = realm_maps(index)
            say(f"  realm index: {ns} answers, {len(found['realms'][0])} realms")
            break
        say(f"  realm index: {ns} gave nothing")
    if not found["dynamic"]:
        return found
    ns = found["dynamic"]
    season = current_season(api.get("/data/wow/pvp-season/index", ns))
    if season is not None:
        say(f"  pvp seasons: current season {season}")
        found["boards"].append((f"/data/wow/pvp-season/{season}", season))
        return found
    say("  pvp seasons: none; trying pvp regions")
    regions = ids_from(api.get("/data/wow/pvp-region/index", ns), "pvp_regions", "regions")
    say(f"  pvp regions: {regions or 'none'}")
    for region in regions:
        season = current_season(api.get(f"/data/wow/pvp-region/{region}/pvp-season/index", ns))
        say(f"    region {region}: current season {season}")
        if season is not None:
            found["boards"].append((f"/data/wow/pvp-region/{region}/pvp-season/{season}", season))
    return found


def probe(say=print):
    say("Commander Ladder probe (reads only; writes nothing)")
    try:
        api = connect()
        api.token()
    except FeedError as err:
        say(f"  {err}")
        say("VERDICT: no credentials or no token. See the docstring for the Keychain commands.")
        return 2
    say("  token: ok")
    found = discover(api, say)

    ladder_ok = False
    for prefix, season in found["boards"]:
        for label, size in BRACKETS.items():
            board = api.get(f"{prefix}/pvp-leaderboard/{label}", found["dynamic"])
            players = parse_leaderboard(board, found["realms"][0])
            sample = next(iter(players.items()), None)
            say(f"    season {season} {label}: {len(players)} entries"
                + (f", e.g. {sample[0]} {sample[1][0]}" if sample else ""))
            ladder_ok = ladder_ok or bool(players)

    profile_ok = False
    realm, name = PROBE_CHARACTER
    for ns in PROFILE_NAMESPACES:
        got = {}
        for label, size in BRACKETS.items():
            parsed = parse_bracket(api.get(f"/profile/wow/character/{realm}/{name}/pvp-bracket/{label}", ns))
            if parsed:
                got[size] = parsed
        if got:
            found["profile"] = ns
            profile_ok = True
            line = ", ".join(f"{s}v{s} {got[s][0]} ({got[s][1]}-{got[s][2]})" for s in sorted(got))
            expect = ", ".join(f"{s}v{s} {r}" for s, r in sorted(PROBE_EXPECTED.items()))
            say(f"  profile {ns}: Polypopin-Dreamscythe {line}")
            say(f"    ironforge.pro on 2026-10-16 said {expect}")
            break
        say(f"  profile {ns}: nothing for Polypopin-Dreamscythe")

    say(f"  requests made: {api.requests}")
    if ladder_ok:
        say(f"VERDICT: the ladder works ({found['dynamic']})"
            + (f"; profiles work too ({found['profile']})" if profile_ok else "; profiles do not"))
        return 0
    if profile_ok:
        say(f"VERDICT: only profiles work ({found['profile']}): the feed runs from wanted names alone")
        return 0
    say("VERDICT: neither the ladder nor profiles answered; the feed cannot run")
    return 1


def field_paths(obj, prefix=""):
    """Every key path in a JSON value with its type, never its value: ["rating (int)", ...].
    A list shows its first item's paths under "[]"."""
    out = []
    if isinstance(obj, dict):
        for key in sorted(obj):
            out += field_paths(obj[key], f"{prefix}.{key}" if prefix else str(key))
    elif isinstance(obj, list):
        out.append(f"{prefix} (list of {len(obj)})")
        if obj:
            out += field_paths(obj[0], f"{prefix}[]")
    else:
        out.append(f"{prefix} ({type(obj).__name__})")
    return out


def fields(say=print):
    """The field names of one leaderboard entry and one character profile summary for a
    PROBE_CHARACTER-realm ladder player: what the feed can learn about who is rated. Names and
    types only; the one value printed is the sample character's name."""
    say("Commander Ladder fields (reads only; writes nothing)")
    try:
        api = connect()
        api.token()
    except FeedError as err:
        say(f"  {err}")
        return 2
    found = discover(api, lambda *_: None)
    home = PROBE_CHARACTER[0]
    entry = None
    for prefix, _ in found["boards"]:
        board = api.get(f"{prefix}/pvp-leaderboard/2v2", found["dynamic"])
        for candidate in (board or {}).get("entries", []):
            if ((candidate.get("character") or {}).get("realm") or {}).get("slug") == home:
                entry = candidate
                break
        if entry:
            break
    if not entry:
        say(f"  no 2v2 leaderboard entry on {home}")
        return 1
    name = entry["character"].get("name", "")
    say(f"  leaderboard entry for {name}-{home}:")
    for line in field_paths(entry):
        say(f"    {line}")
    summary, ns_used = None, None
    for ns in PROFILE_NAMESPACES:
        summary = api.get(f"/profile/wow/character/{home}/{urllib.parse.quote(name.lower())}", ns)
        if summary:
            ns_used = ns
            break
    if not summary:
        say("  no character profile summary in either profile namespace")
        return 1
    say(f"  profile summary ({ns_used}):")
    for line in field_paths(summary):
        say(f"    {line}")
    tops = set(summary)
    for want in ("faction", "character_class", "race", "gender", "guild", "last_login_timestamp"):
        say(f"  {want}: {'present' if want in tops else 'MISSING'}"
            + (" (also on the leaderboard entry)" if want in entry else ""))
    # The talent trees (L10): field names, and the trees' names -- game data, not the player's
    specs = api.get(f"/profile/wow/character/{home}/{urllib.parse.quote(name.lower())}/specializations", ns_used)
    if not specs:
        say("  specializations: nothing")
    else:
        say("  specializations:")
        for line in field_paths(specs):
            say(f"    {line}")
        trees = [t.get("specialization_name") or (t.get("specialization") or {}).get("name")
                 for group in specs.get("specialization_groups") or []
                 for t in group.get("specializations") or []]
        say(f"  tree names: {', '.join(str(t) for t in trees if t) or 'none found'}")
    say(f"  requests made: {api.requests}")
    return 0


def run(say=print):
    try:
        api = connect()
        api.token()
    except FeedError as err:
        say(f"Commander Ladder: {err}")
        return 2
    now = int(time.time())
    found = discover(api, lambda *_: None)
    by_slug, by_name = found["realms"]
    players = {}
    season = None
    namespace = found["dynamic"] or ""

    for prefix, board_season in found["boards"]:
        season = max(season or 0, board_season)
        for label, size in BRACKETS.items():
            board = api.get(f"{prefix}/pvp-leaderboard/{label}", found["dynamic"])
            for key, value in parse_leaderboard(board, by_slug).items():
                players.setdefault(key, {"t": now})[size] = value
    from_ladder = len(players)

    profile_ns = None
    for ns in PROFILE_NAMESPACES:
        if parse_bracket(api.get(f"/profile/wow/character/{PROBE_CHARACTER[0]}/{PROBE_CHARACTER[1]}"
                                 f"/pvp-bracket/2v2", ns)) is not None:
            profile_ns = ns
            break

    wanted = read_wanted()
    looked_up = 0
    if profile_ns:
        # A "Name-*" wish has no realm (the game had a bare name, L8). The realms with
        # players on this season's ladder are tried busiest first, then every other realm the
        # index lists; the character summary says which one the name lives on (one request a
        # realm), and only that realm's brackets are fetched
        realm_counts = {}
        for key in players:
            realm_counts[key.partition("-")[2]] = realm_counts.get(key.partition("-")[2], 0) + 1
        any_realms = sorted(realm_counts, key=lambda r: -realm_counts[r])
        any_realms += [r for r in sorted(by_name) if r not in realm_counts]
        on_ladder = {}
        for key in players:
            bare = key.partition("-")[0].lower()
            on_ladder[bare] = on_ladder.get(bare, 0) + 1

        def look(name, realm):
            slug = by_name.get(realm) or realm.lower()
            entry = {"t": now}
            for label, size in BRACKETS.items():
                path = f"/profile/wow/character/{urllib.parse.quote(slug)}/{urllib.parse.quote(name.lower())}/pvp-bracket/{label}"
                parsed = parse_bracket(api.get(path, profile_ns))
                if parsed:
                    entry[size] = parsed
            return entry if len(entry) > 1 else None

        # Newest wishes first; names already on the ladder need no profile call
        # A request that keeps failing stops the lookups, not the run: the ladder is written
        try:
            for key, _ in sorted(wanted.items(), key=lambda kv: -kv[1]):
                if looked_up >= MAX_WANTED_PER_RUN:
                    break
                if key in players:
                    continue
                name, _, realm = key.partition("-")
                if realm.startswith("*"):
                    # One realm's ladder already has the name: the game matches it by name
                    if on_ladder.get(name.lower()) == 1:
                        continue
                    looked_up += 1
                    # "*Dreamscythe": the game's own realm is asked first, as the game asks it first
                    home = realm[1:]
                    order = ([home] if home else []) + [r for r in any_realms if r != home]
                    for candidate in order:
                        slug = by_name.get(candidate) or candidate.lower()
                        if api.get(f"/profile/wow/character/{urllib.parse.quote(slug)}/"
                                   f"{urllib.parse.quote(name.lower())}", profile_ns) is None:
                            continue
                        entry = look(name, candidate)
                        if entry:
                            players[f"{name}-{candidate}"] = entry
                            break
                        # Lives here but unrated: someone of that name elsewhere may be the
                        # one the game saw (a bare name could be either)
                    continue
                entry = look(name, realm)
                looked_up += 1
                if entry:
                    players[key] = entry
        except FeedError as err:
            say(f"Commander Ladder: wanted names stopped after {looked_up}: {err}")

    previous = read_previous()
    carried = carry_over(previous, players, now, season)

    # Who the home realm's rated players are, for Recruit's sweep (L9)
    profiled = described = 0
    home_keys = sorted(k for k in players if k.partition("-")[2] in HOME_REALMS)
    if profile_ns and home_keys:
        cache = load_cache()
        profiled = refresh_profiles(api, profile_ns, home_keys, by_name, cache, now, say=say)
        prune_cache(cache, home_keys, now)
        save_cache(cache)
        described = attach_profiles(players, cache, previous)

    data = {"generated": now, "region": REGION, "namespace": namespace, "season": season, "players": players}
    write_atomically(DATA_FILE, render_lua(data))
    say(f"Commander Ladder: {len(players)} players written ({from_ladder} from the ladder, "
        f"{looked_up} wanted names looked up, {carried} carried over, {described} described, "
        f"{profiled} profiles fetched), {api.requests} requests. /reload in game to load them.")
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    try:
        if command == "probe":
            return probe()
        if command == "run":
            return run()
        if command == "fields":
            return fields()
    except FeedError as err:
        print(f"Commander Ladder: {err}", file=sys.stderr)
        return 1
    print(__doc__.strip().splitlines()[0])
    print("usage: python3 -I ladder_feed.py probe|fields|run")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
