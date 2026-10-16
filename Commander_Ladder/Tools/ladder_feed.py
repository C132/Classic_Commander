#!/usr/bin/env python3
"""Commander Ladder feed: arena ratings from Blizzard's web API, as a Lua file the game loads.

    python3 -I ladder_feed.py probe   # check credentials, namespaces and endpoints; changes nothing
    python3 -I ladder_feed.py run     # pull the ladders + wanted profiles, write CommanderLadderData.lua

The game only tells an addon another player's rating through an inspect (own faction, ~28 yards).
Everyone else comes from here: the same web API ironforge.pro reads. Commander_Muster merges it
with what it has seen in game (its D11); the newest reading wins per bracket.

Credentials live in the macOS login Keychain, stored by Devin with:
    security add-generic-password -a "$USER" -s commander-battlenet-client-id -w
    security add-generic-password -a "$USER" -s commander-battlenet-client-secret -w
They are read with `security find-generic-password` and never printed, logged or written.

Standard library only. Run with `python3 -I` so nothing beside this file is imported.
"""

import base64
import glob
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
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

REQUESTS_PER_SECOND = 20     # the API allows 100/s
REQUESTS_PER_HOUR = 30000    # the API allows 36,000/h
MAX_WANTED_PER_RUN = 800     # names looked up by profile in one run (3 requests each)
CARRY_SECONDS = 7 * 86400    # how long an entry not refreshed this run is kept

PROBE_CHARACTER = ("dreamscythe", "polypopin")
PROBE_EXPECTED = {2: 1534, 3: 1531, 5: 1605}   # ironforge.pro, 2026-10-16


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
    """(status, headers, body bytes) for one request. Never raises on an HTTP status."""
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as err:
        return err.code, dict(err.headers or {}), err.read() or b""


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
        raise FeedError(f"{path} ({namespace}): gave up after repeated throttling")


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
        parts.append(f"t = {int(entry['t'])}")
        lines.append(f"        [{lua_string(key)}] = {{ {', '.join(parts)} }},")
    lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_atomically(path, text):
    """Write via a temp file in the same folder and rename, so the game never loads half a file."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=".ladder-", suffix=".lua", dir=str(path.parent))
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
# The two commands
# ---------------------------------------------------------------------------

def connect():
    client_id = keychain(KEYCHAIN_ID)
    client_secret = keychain(KEYCHAIN_SECRET)
    return Api(client_id, client_secret)


def discover(api, say=print):
    """Which namespaces answer, which pvp regions and seasons exist. Returns a dict."""
    found = {"dynamic": None, "profile": None, "regions": [], "realms": ({}, {})}
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
    regions = ids_from(api.get("/data/wow/pvp-region/index", ns), "pvp_regions", "regions")
    say(f"  pvp regions: {regions or 'none'}")
    for region in regions:
        season = current_season(api.get(f"/data/wow/pvp-region/{region}/pvp-season/index", ns))
        say(f"    region {region}: current season {season}")
        if season is not None:
            found["regions"].append((region, season))
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
    for region, season in found["regions"]:
        for label, size in BRACKETS.items():
            board = api.get(f"/data/wow/pvp-region/{region}/pvp-season/{season}/pvp-leaderboard/{label}",
                            found["dynamic"])
            players = parse_leaderboard(board, found["realms"][0])
            sample = next(iter(players.items()), None)
            say(f"    region {region} season {season} {label}: {len(players)} entries"
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

    for region, region_season in found["regions"]:
        season = max(season or 0, region_season)
        for label, size in BRACKETS.items():
            board = api.get(f"/data/wow/pvp-region/{region}/pvp-season/{region_season}/pvp-leaderboard/{label}",
                            found["dynamic"])
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
        # Newest wishes first; names already on the ladder need no profile call
        for key, _ in sorted(wanted.items(), key=lambda kv: -kv[1]):
            if looked_up >= MAX_WANTED_PER_RUN:
                break
            if key in players:
                continue
            name, _, realm = key.partition("-")
            slug = by_name.get(realm) or realm.lower()
            entry = {"t": now}
            for label, size in BRACKETS.items():
                path = f"/profile/wow/character/{urllib.parse.quote(slug)}/{urllib.parse.quote(name.lower())}/pvp-bracket/{label}"
                parsed = parse_bracket(api.get(path, profile_ns))
                if parsed:
                    entry[size] = parsed
            looked_up += 1
            if len(entry) > 1:
                players[key] = entry

    carried = carry_over(read_previous(), players, now, season)
    data = {"generated": now, "region": REGION, "namespace": namespace, "season": season, "players": players}
    write_atomically(DATA_FILE, render_lua(data))
    say(f"Commander Ladder: {len(players)} players written ({from_ladder} from the ladder, "
        f"{looked_up} wanted names looked up, {carried} carried over), {api.requests} requests. "
        f"/reload in game to load them.")
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    try:
        if command == "probe":
            return probe()
        if command == "run":
            return run()
    except FeedError as err:
        print(f"Commander Ladder: {err}", file=sys.stderr)
        return 1
    print(__doc__.strip().splitlines()[0])
    print("usage: python3 -I ladder_feed.py probe|run")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
