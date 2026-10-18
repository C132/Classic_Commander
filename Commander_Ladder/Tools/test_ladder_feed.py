#!/usr/bin/env python3
"""Offline tests for ladder_feed.py: fixtures only, no network, no Keychain.

    python3 -I test_ladder_feed.py

Covers the payload parsers, realm names, the Lua writer (loaded back through luajit),
the sandboxed SavedVariables shim, carry-over between runs, the HTTP retry rules,
the home realm's profile summaries (parsed, cached a week, written as `w`), and that
credentials never reach any output.
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ladder_feed", HERE / "ladder_feed.py")
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)

LUAJIT = feed.LUAJIT
HAVE_LUAJIT = Path(LUAJIT).exists()

# Nothing here may touch the real profile cache in ~/Library/Caches
CACHE_DIR = tempfile.TemporaryDirectory()
feed.PROFILE_CACHE = Path(CACHE_DIR.name) / "profiles.json"

REALM_INDEX = {"realms": [
    {"id": 6101, "name": "Dreamscythe", "slug": "dreamscythe"},
    {"id": 6102, "name": "Living Flame", "slug": "living-flame"},
    {"id": 6103, "name": {"en_US": "Nightslayer", "de_DE": "Nachtschlitzer"}, "slug": "nightslayer"},
]}

LEADERBOARD = {"entries": [
    {"character": {"name": "Polypopin", "realm": {"slug": "dreamscythe"}}, "rating": 1534,
     "season_match_statistics": {"played": 39, "won": 21, "lost": 18}},
    {"character": {"name": "Zed", "realm": {"slug": "living-flame"}}, "rating": 1888,
     "season_match_statistics": {"played": 12, "won": 10}},
    {"character": {"name": "Ghost", "realm": {"slug": "unknown-realm"}}, "rating": 1500,
     "season_match_statistics": {"won": 1, "lost": 1}},
    {"character": {"name": "NoRealm"}, "rating": 1400},
]}

SECRET_ID, SECRET_KEY = "client-id-0123456789", "client-secret-abcdefghij"


class FakeFetch:
    """Answers queued (status, headers, body) per URL substring, records every call."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, url, headers, data=None, timeout=30):
        self.calls.append((url, headers, data))
        for needle, answers in self.routes.items():
            if needle in url:
                answer = answers.pop(0) if len(answers) > 1 else answers[0]
                status, hdrs, body = answer
                return status, hdrs, json.dumps(body).encode() if isinstance(body, (dict, list)) else body
        return 404, {}, b""


def token_route():
    return {"oauth.battle.net/token": [(200, {}, {"access_token": "tok-XYZ-123456"})]}


def make_api(routes):
    fetch = FakeFetch({**token_route(), **routes})
    t = [0.0]
    api = feed.Api(SECRET_ID, SECRET_KEY, fetch=fetch, clock=lambda: t[0],
                   sleep=lambda s: t.__setitem__(0, t[0] + s))
    return api, fetch, t


class Parsing(unittest.TestCase):

    def test_realm_names_lose_spaces(self):
        self.assertEqual(feed.normalize_realm("Living Flame"), "LivingFlame")
        by_slug, by_name = feed.realm_maps(REALM_INDEX)
        self.assertEqual(by_slug["living-flame"], "LivingFlame")
        self.assertEqual(by_name["LivingFlame"], "living-flame")
        self.assertEqual(by_slug["nightslayer"], "Nightslayer", "localized name dicts use en_US")
        self.assertEqual(feed.realm_from_slug("crusader-strike", {}), "CrusaderStrike",
                         "an unknown slug is guessed from its parts")

    def test_leaderboard(self):
        by_slug, _ = feed.realm_maps(REALM_INDEX)
        players = feed.parse_leaderboard(LEADERBOARD, by_slug)
        self.assertEqual(players["Polypopin-Dreamscythe"], (1534, 21, 18))
        self.assertEqual(players["Zed-LivingFlame"], (1888, 10, 2), "lost comes from played - won")
        self.assertEqual(players["Ghost-UnknownRealm"], (1500, 1, 1))
        self.assertNotIn("NoRealm", " ".join(players), "an entry with no realm is skipped")
        self.assertEqual(feed.parse_leaderboard(None, by_slug), {})

    def test_bracket(self):
        payload = {"rating": 1605, "season_match_statistics": {"played": 86, "won": 40, "lost": 46}}
        self.assertEqual(feed.parse_bracket(payload), (1605, 40, 46))
        self.assertIsNone(feed.parse_bracket(None))
        self.assertIsNone(feed.parse_bracket({"season_match_statistics": {}}))

    def test_indexes(self):
        self.assertEqual(feed.ids_from({"pvp_regions": [{"id": 1}, {"key": {"href": "x/pvp-region/2?ns"}}]},
                                       "pvp_regions"), [1, 2])
        self.assertEqual(feed.current_season({"current_season": {"id": 3}, "seasons": [{"id": 1}]}), 3)
        self.assertEqual(feed.current_season({"seasons": [{"id": 1}, {"id": 4}]}), 4)
        self.assertIsNone(feed.current_season({}))


class LuaFiles(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def data(self):
        return {"generated": 1792200000, "region": "us", "namespace": "dynamic-classicann-us", "season": 3,
                "players": {
                    "Polypopin-Dreamscythe": {2: (1534, 21, 18), 3: (1531, 21, 29), 5: (1605, 40, 46),
                                              "t": 1792199000},
                    'Odd"Name\\-Dreamscythe': {2: (1500, 1, 0), "t": 1792199000},
                    "Empty-Dreamscythe": {"t": 1},
                }}

    def test_render_shape(self):
        text = feed.render_lua(self.data())
        self.assertIn('["Polypopin-Dreamscythe"] = { [2] = { 1534, 21, 18 }, [3] = { 1531, 21, 29 }, '
                      '[5] = { 1605, 40, 46 }, t = 1792199000 },', text)
        self.assertNotIn("Empty-Dreamscythe", text, "a player with no brackets is not written")
        self.assertTrue(text.startswith("-- Generated"))

    @unittest.skipUnless(HAVE_LUAJIT, "luajit not installed")
    def test_render_loads_back(self):
        path = self.dir / "CommanderLadderData.lua"
        feed.write_atomically(path, feed.render_lua(self.data()))
        self.assertEqual([p.name for p in self.dir.iterdir()], ["CommanderLadderData.lua"],
                         "no temp file is left behind")
        back = feed.read_previous(path)
        self.assertEqual(back["season"], 3)
        self.assertEqual(back["players"]["Polypopin-Dreamscythe"]["5"], {"1": 1605, "2": 40, "3": 46})
        self.assertIn('Odd"Name\\-Dreamscythe', back["players"], "quotes and backslashes survive")
        entry = feed.entry_from_json(back["players"]["Polypopin-Dreamscythe"])
        self.assertEqual(entry, {2: (1534, 21, 18), 3: (1531, 21, 29), 5: (1605, 40, 46), "t": 1792199000})

    @unittest.skipUnless(HAVE_LUAJIT, "luajit not installed")
    def test_saved_variables(self):
        a = self.dir / "a.lua"
        a.write_text('CommanderLadderWanted = {\n\t["Bob-Dreamscythe"] = 100,\n\t["Ivy-Nightslayer"] = 50,\n'
                     '\t["bare"] = 7,\n}\nCommanderLadderDB = { EnableLadder = true }\n')
        b = self.dir / "b.lua"
        b.write_text('CommanderLadderWanted = { ["Bob-Dreamscythe"] = 300 }\n')
        wanted = feed.read_wanted([str(a), str(b), str(self.dir / "missing.lua")])
        self.assertEqual(wanted, {"Bob-Dreamscythe": 300, "Ivy-Nightslayer": 50},
                         "accounts merge, the newest wish wins, keys without a realm are dropped")

    @unittest.skipUnless(HAVE_LUAJIT, "luajit not installed")
    def test_shim_is_sandboxed(self):
        marker = self.dir / "touched"
        hostile = self.dir / "hostile.lua"
        hostile.write_text(f'io.open({json.dumps(str(marker))}, "w"):write("x")\nCommanderLadderWanted = {{}}\n')
        self.assertEqual(feed.read_wanted([str(hostile)]), {})
        self.assertFalse(marker.exists(), "the file could not reach io")
        self.assertIsNone(feed.lua_global(self.dir / "nope.lua", "X"))

    def test_carry_over(self):
        now = 1792200000
        previous = {"season": 3, "players": {
            "Old-Dreamscythe": {"2": {"1": 1500, "2": 5, "3": 5}, "t": now - 3 * 86400},
            "Stale-Dreamscythe": {"3": {"1": 1600, "2": 1, "3": 1}, "t": now - 8 * 86400},
            "Fresh-Dreamscythe": {"2": {"1": 1400, "2": 1, "3": 1}, "t": now - 100},
        }}
        players = {"Fresh-Dreamscythe": {2: (1450, 2, 1), "t": now}}
        self.assertEqual(feed.carry_over(previous, players, now, 3), 1)
        self.assertEqual(players["Old-Dreamscythe"][2], (1500, 5, 5), "a recent entry is kept")
        self.assertNotIn("Stale-Dreamscythe", players, "a week-old entry is dropped")
        self.assertEqual(players["Fresh-Dreamscythe"][2], (1450, 2, 1), "this run's data wins")
        players = {}
        self.assertEqual(feed.carry_over(previous, players, now, 4), 0, "a new season carries nothing")


class Http(unittest.TestCase):

    def test_token_and_get(self):
        api, fetch, _ = make_api({"/data/wow/realm/index": [(200, {}, REALM_INDEX)]})
        self.assertEqual(api.get("/data/wow/realm/index", "dynamic-classicann-us"), REALM_INDEX)
        token_call, get_call = fetch.calls
        self.assertEqual(token_call[2], b"grant_type=client_credentials")
        self.assertIn("namespace=dynamic-classicann-us", get_call[0])
        self.assertIn("locale=en_US", get_call[0])
        self.assertEqual(get_call[1]["Authorization"], "Bearer tok-XYZ-123456")
        self.assertNotIn(SECRET_KEY, get_call[0], "the secret never goes in a URL")

    def test_404_is_none_and_429_retries(self):
        api, fetch, clock = make_api({
            "/missing": [(404, {}, b"")],
            "/busy": [(429, {"Retry-After": "2"}, b""), (503, {}, b""), (200, {}, {"ok": 1})],
        })
        self.assertIsNone(api.get("/missing", "ns"))
        self.assertEqual(api.get("/busy", "ns"), {"ok": 1})
        self.assertGreaterEqual(clock[0], 3.0, "waited out Retry-After and a backoff")

    def test_expired_token_is_renewed(self):
        api, fetch, _ = make_api({"/x": [(401, {}, b""), (200, {}, {"ok": 2})]})
        self.assertEqual(api.get("/x", "ns"), {"ok": 2})
        self.assertEqual(sum(1 for c in fetch.calls if "oauth" in c[0]), 2)

    def test_pacing(self):
        api, fetch, clock = make_api({"/p": [(200, {}, {})]})
        for _ in range(10):
            api.get("/p", "ns")
        self.assertGreaterEqual(clock[0], 10 / feed.REQUESTS_PER_SECOND - 0.01, "requests are spaced")

    def test_errors_never_carry_secrets(self):
        api, _, _ = make_api({f"/{SECRET_KEY}": [(400, {}, b"")]})
        with self.assertRaises(feed.FeedError) as caught:
            api.get(f"/{SECRET_KEY}", "ns")
        self.assertNotIn(SECRET_KEY, str(caught.exception))
        self.assertEqual(feed.redact(f"a {SECRET_ID} b", [SECRET_ID]), "a [redacted] b")

    def test_refused_token(self):
        fetch = FakeFetch({"oauth.battle.net/token": [(401, {}, b"bad " + SECRET_KEY.encode())]})
        api = feed.Api(SECRET_ID, SECRET_KEY, fetch=fetch, clock=lambda: 0.0, sleep=lambda s: None)
        with self.assertRaises(feed.FeedError) as caught:
            api.token()
        self.assertNotIn(SECRET_KEY, str(caught.exception))
        self.assertNotIn(SECRET_ID, str(caught.exception))


class NetworkFailures(unittest.TestCase):
    """A timeout or reset is retried, never the end of a run (2026-10-18: one read timeout inside a
    404's body killed a 30-minute run)."""

    def with_urlopen(self, fake):
        real = feed.urllib.request.urlopen
        feed.urllib.request.urlopen = fake
        self.addCleanup(setattr, feed.urllib.request, "urlopen", real)

    def test_timeout_is_a_status(self):
        def fake(request, timeout=30):
            raise TimeoutError("The read operation timed out")
        self.with_urlopen(fake)
        self.assertEqual(feed.urlopen_fetch("https://x.test/a", {}), (feed.NETWORK_ERROR, {}, b""))

    def test_dns_failure_is_a_status(self):
        def fake(request, timeout=30):
            raise feed.urllib.error.URLError("nodename nor servname provided")
        self.with_urlopen(fake)
        self.assertEqual(feed.urlopen_fetch("https://x.test/a", {})[0], feed.NETWORK_ERROR)

    def test_timeout_reading_an_error_body(self):
        class Body:
            def read(self, *a):
                raise TimeoutError("The read operation timed out")
            def close(self):
                pass

        def fake(request, timeout=30):
            raise feed.urllib.error.HTTPError(request.full_url, 404, "Not Found", {}, Body())
        self.with_urlopen(fake)
        status, _, body = feed.urlopen_fetch("https://x.test/a", {})
        self.assertEqual((status, body), (404, b""), "the 404 still counts; the body is given up")

    def test_network_error_is_retried(self):
        api, fetch, clock = make_api({"/flaky": [(feed.NETWORK_ERROR, {}, b""), (200, {}, {"ok": 3})]})
        self.assertEqual(api.get("/flaky", "ns"), {"ok": 3})

    def test_wanted_lookups_failing_still_write_the_ladder(self):
        api, fetch, _ = make_api({
            "/data/wow/realm/index": [(200, {}, REALM_INDEX)],
            "/data/wow/pvp-season/index": [(200, {}, {"current_season": {"id": 3}})],
            "/pvp-leaderboard/": [(200, {}, LEADERBOARD)],
            "/character/dreamscythe/polypopin/pvp-bracket/": [(200, {}, {"rating": 1534})],
            "/character/dreamscythe/lowguy?": [(feed.NETWORK_ERROR, {}, b"")],
        })
        written, lines = {}, []
        saved = (feed.connect, feed.read_wanted, feed.read_previous, feed.write_atomically, feed.PROFILE_CACHE)
        real_write = feed.write_atomically
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        feed.connect = lambda: api
        feed.read_wanted = lambda: {"Lowguy-*Dreamscythe": 300}
        feed.read_previous = lambda: None
        feed.PROFILE_CACHE = Path(tmp.name) / "profiles.json"
        feed.write_atomically = lambda path, text, suffix=".lua": (
            written.__setitem__("text", text) if suffix == ".lua" else real_write(path, text, suffix=suffix))
        try:
            self.assertEqual(feed.run(lines.append), 0)
        finally:
            (feed.connect, feed.read_wanted, feed.read_previous, feed.write_atomically,
             feed.PROFILE_CACHE) = saved
        self.assertIn('["Polypopin-Dreamscythe"]', written.get("text", ""), "the ladder is written all the same")
        self.assertTrue(any("wanted names stopped" in line for line in lines), lines)


class Keychain(unittest.TestCase):

    def test_missing_item_says_so_without_values(self):
        def runner(cmd, **kw):
            return subprocess.CompletedProcess(cmd, 44, stdout="", stderr="could not be found")
        with self.assertRaises(feed.MissingCredentials) as caught:
            feed.keychain("commander-battlenet-client-secret", runner=runner)
        self.assertIn("commander-battlenet-client-secret", str(caught.exception))

    def test_present_item(self):
        def runner(cmd, **kw):
            self.assertEqual(cmd[:2], ["security", "find-generic-password"])
            self.assertEqual(cmd[-1], "-w")
            return subprocess.CompletedProcess(cmd, 0, stdout=SECRET_KEY + "\n", stderr="")
        self.assertEqual(feed.keychain("x", runner=runner), SECRET_KEY)


class Probe(unittest.TestCase):

    def test_probe_without_credentials(self):
        lines = []
        real = feed.connect
        feed.connect = lambda: (_ for _ in ()).throw(feed.MissingCredentials("Keychain item x is missing"))
        try:
            self.assertEqual(feed.probe(lines.append), 2)
        finally:
            feed.connect = real
        self.assertTrue(any("VERDICT" in line for line in lines))

    def test_probe_reads_ladder_and_profile(self):
        api, fetch, _ = make_api({
            "/data/wow/realm/index": [(200, {}, REALM_INDEX)],
            "/data/wow/pvp-region/index": [(200, {}, {"pvp_regions": [{"id": 1}]})],
            "/pvp-season/index": [(200, {}, {"current_season": {"id": 3}})],
            "/pvp-leaderboard/": [(200, {}, LEADERBOARD)],
            "/pvp-bracket/": [(200, {}, {"rating": 1534, "season_match_statistics": {"won": 21, "lost": 18}})],
        })
        lines = []
        real = feed.connect
        feed.connect = lambda: api
        try:
            self.assertEqual(feed.probe(lines.append), 0)
        finally:
            feed.connect = real
        text = "\n".join(lines)
        self.assertIn("VERDICT: the ladder works (dynamic-classicann-us)", text)
        self.assertIn("profiles work too (profile-classicann-us)", text)
        self.assertNotIn(SECRET_KEY, text)
        self.assertNotIn("tok-XYZ-123456", text, "the token is never printed")

    def test_anniversary_season_layout(self):
        """TBC Anniversary has no pvp-region level: the season index answers directly."""
        api, fetch, _ = make_api({
            "/data/wow/realm/index": [(200, {}, REALM_INDEX)],
            "/data/wow/pvp-season/index": [(200, {}, {"current_season": {"id": 3}})],
            "/data/wow/pvp-season/3/pvp-leaderboard/": [(200, {}, LEADERBOARD)],
            "/pvp-bracket/": [(200, {}, {"rating": 1534, "season_match_statistics": {"won": 21, "lost": 18}})],
        })
        found = feed.discover(api, lambda *_: None)
        self.assertEqual(found["boards"], [("/data/wow/pvp-season/3", 3)])
        lines = []
        real = feed.connect
        feed.connect = lambda: api
        try:
            self.assertEqual(feed.probe(lines.append), 0)
        finally:
            feed.connect = real
        self.assertIn("VERDICT: the ladder works", "\n".join(lines))
        self.assertFalse(any("/pvp-region/" in call[0] for call in fetch.calls),
                         "a season index that answers is not followed by a region lookup")

    def test_run_finds_realmless_names(self):
        """A "Name-*" wish (the game had no realm) is found on whichever realm it lives on."""
        rated = {"rating": 1450, "season_match_statistics": {"won": 5, "lost": 4}}
        api, fetch, _ = make_api({
            "/data/wow/realm/index": [(200, {}, REALM_INDEX)],
            "/data/wow/pvp-season/index": [(200, {}, {"current_season": {"id": 3}})],
            "/pvp-leaderboard/": [(200, {}, LEADERBOARD)],
            "/character/dreamscythe/polypopin/pvp-bracket/": [(200, {}, rated)],
            "/character/nightslayer/lowguy/pvp-bracket/": [(200, {}, rated)],
            # the summary: Lowguy lives on Nightslayer only, Nobody nowhere
            "/character/nightslayer/lowguy?": [(200, {}, {"level": 70})],
        })
        written = {}
        saved = (feed.connect, feed.read_wanted, feed.read_previous, feed.write_atomically)
        feed.connect = lambda: api
        feed.read_wanted = lambda: {"Lowguy-*Dreamscythe": 300, "Zed-*Dreamscythe": 200,
                                    "Nobody-*": 150, "Polypopin-Dreamscythe": 100}
        feed.read_previous = lambda: None
        # .lua is the data file; the profile cache (.json) goes to the test's temp path
        real_write = feed.write_atomically
        feed.write_atomically = lambda path, text, suffix=".lua": (
            written.__setitem__("text", text) if suffix == ".lua" else real_write(path, text, suffix=suffix))
        try:
            self.assertEqual(feed.run(lambda *_: None), 0)
        finally:
            feed.connect, feed.read_wanted, feed.read_previous, feed.write_atomically = saved
        text = written["text"]
        self.assertIn('["Lowguy-Nightslayer"]', text, "found on the realm it lives on")
        self.assertNotIn("Lowguy-Dreamscythe", text, "not filed under our realm by guess")
        self.assertNotIn("-*", text, "a wish's marker never reaches the data file")
        self.assertNotIn("Nobody", text, "a name that lives nowhere writes nothing")
        urls = [call[0] for call in fetch.calls]
        self.assertFalse(any("/character/" in u and "/zed" in u for u in urls),
                         "a name on one realm's ladder needs no lookup: the game matches it by name")
        self.assertFalse(any("/character/dreamscythe/lowguy/pvp-bracket" in u for u in urls),
                         "brackets are only fetched on the realm the summary found")
        summaries = [u for u in urls if "/character/" in u and "/lowguy?" in u]
        self.assertIn("/character/dreamscythe/lowguy?", summaries[0], "the game's own realm is asked first")


SUMMARY = {
    "name": "Bootii", "level": 70, "last_login_timestamp": 1792250000123,
    "faction": {"type": "HORDE", "name": "Horde"},
    "character_class": {"id": 4, "name": "Rogue"},
    "race": {"id": 10, "name": "Blood Elf"},
    "guild": {"name": "Gank Squad", "id": 9, "faction": {"type": "HORDE"}},
    "gender": {"type": "FEMALE", "name": "Female"},
}

SPECS = {"specialization_groups": [
    {"is_active": False, "specializations": [
        {"specialization_name": "Combat", "spent_points": 41}, {"specialization_name": "Assassination", "spent_points": 20}]},
    {"is_active": True, "specializations": [
        {"specialization_name": "Assassination", "spent_points": 20},
        {"specialization_name": "Subtlety", "spent_points": 41}]},
]}


class Profiles(unittest.TestCase):
    """L9: who the home realm's rated players are, for Recruit's sweep."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache_path = Path(self.tmp.name) / "c" / "profiles.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_parse_summary(self):
        self.assertEqual(feed.parse_summary(SUMMARY),
                         {"f": "H", "c": "ROGUE", "r": "BloodElf", "g": "Gank Squad", "l": 1792250000, "x": "F"},
                         "game tokens, and milliseconds become seconds")
        loner = {"character_class": {"id": 5}, "race": {"id": 4}, "last_login_timestamp": 1792250000}
        self.assertEqual(feed.parse_summary(loner),
                         {"f": "A", "c": "PRIEST", "r": "NightElf", "g": "", "l": 1792250000, "x": ""},
                         "no guild is an empty name; no faction is read from the race; no gender is unknown")
        self.assertEqual(feed.parse_summary({"character_class": {"id": 5}, "race": {"id": 5}})["r"],
                         "Scourge", "the undead are Scourge, as UnitRace spells it")
        self.assertIsNone(feed.parse_summary({"character_class": {"id": 6}, "race": {"id": 1}}),
                          "a death knight is no TBC class")
        self.assertIsNone(feed.parse_summary({"race": {"id": 1}}))
        self.assertIsNone(feed.parse_summary(None))

    def test_parse_specs(self):
        self.assertEqual(feed.parse_specs(SPECS), "SUBTLETY", "the active group's tree with the most points")
        one = {"specialization_groups": [{"specializations": [
            {"specialization_name": "Beast Mastery", "spent_points": 41},
            {"specialization_name": "Marksmanship", "spent_points": 20}]}]}
        self.assertEqual(feed.parse_specs(one), "BEASTMASTERY", "no group marked active: the first; letters only")
        self.assertEqual(feed.parse_specs({"specialization_groups": [{"is_active": True, "specializations": [
            {"specialization_name": "Feral Combat", "spent_points": 44}]}]}), "FERALCOMBAT")
        self.assertEqual(feed.parse_specs({"specialization_groups": [{"is_active": True, "specializations": []}]}), "",
                         "no talents, no spec")
        self.assertEqual(feed.parse_specs(None), "", "a 404 is no spec")

    def test_cache_round_trip(self):
        self.assertEqual(feed.load_cache(self.cache_path), {}, "no file is an empty cache")
        feed.save_cache({"Abbé-Dreamscythe": {"c": "MAGE", "at": 5}}, self.cache_path)
        self.assertEqual(feed.load_cache(self.cache_path), {"Abbé-Dreamscythe": {"c": "MAGE", "at": 5}})
        self.assertEqual([p.name for p in self.cache_path.parent.iterdir()], ["profiles.json"],
                         "the folder is made and no temp file is left")
        self.cache_path.write_text("not json")
        self.assertEqual(feed.load_cache(self.cache_path), {}, "a damaged cache starts over")

    def test_refresh_fetches_only_what_is_due(self):
        now = 1792300000
        api, fetch, _ = make_api({
            "/character/dreamscythe/bootii?": [(200, {}, SUMMARY)],
            "/character/dreamscythe/bootii/specializations?": [(200, {}, SPECS)],
            "/character/dreamscythe/old?": [(200, {}, SUMMARY)],
            "/character/dreamscythe/abb%C3%A9?": [(200, {}, SUMMARY)],
        })
        cache = {
            "Fresh-Dreamscythe": {"c": "MAGE", "r": "Human", "f": "A", "at": now - 86400, "v": feed.PROFILE_SCHEMA},
            "Old-Dreamscythe": {"c": "MAGE", "r": "Human", "f": "A", "at": now - 8 * 86400, "v": feed.PROFILE_SCHEMA},
        }
        keys = ["Bootii-Dreamscythe", "Fresh-Dreamscythe", "Old-Dreamscythe", "Gone-Dreamscythe",
                "Abbé-Dreamscythe"]
        by_name = {"Dreamscythe": "dreamscythe"}
        self.assertEqual(feed.refresh_profiles(api, "profile-classicann-us", keys, by_name, cache, now), 4)
        urls = [c[0] for c in fetch.calls if "/character/" in c[0] and "/specializations" not in c[0]]
        self.assertFalse(any("/fresh?" in u for u in urls), "a summary under a week old is not asked again")
        self.assertIn("/old?", urls[-1], "never-fetched names first, the oldest after them")
        self.assertEqual(cache["Bootii-Dreamscythe"]["s"], "SUBTLETY", "the talents are fetched with the summary")
        self.assertEqual(cache["Bootii-Dreamscythe"]["v"], feed.PROFILE_SCHEMA)
        self.assertEqual(cache["Old-Dreamscythe"]["s"], "", "no talents answer is no spec")
        self.assertEqual(sum(1 for c in fetch.calls if "/specializations" in c[0]), 3,
                         "one talents request per player described, none for a 404")
        self.assertTrue(all("namespace=profile-classicann-us" in u for u in urls))
        self.assertEqual(cache["Bootii-Dreamscythe"]["c"], "ROGUE")
        self.assertEqual(cache["Bootii-Dreamscythe"]["at"], now)
        self.assertEqual(cache["Gone-Dreamscythe"], {"gone": 1, "at": now}, "a 404 is cached as gone")
        self.assertEqual(cache["Abbé-Dreamscythe"]["r"], "BloodElf", "an accented name is asked lower-cased, encoded")
        # A week later only the ones fetched then are due again; the limit holds
        fetch.calls.clear()
        self.assertEqual(feed.refresh_profiles(api, "ns", keys, by_name, cache, now + 3600, limit=10), 0)
        self.assertEqual(feed.refresh_profiles(api, "ns", keys, by_name, cache, now + 8 * 86400, limit=2), 2)

    def test_records_from_before_the_talents_are_fetched_again(self):
        now = 1792300000
        api, fetch, _ = make_api({"/character/": [(200, {}, SUMMARY)]})
        cache = {"Early-Dreamscythe": {"c": "MAGE", "r": "Human", "f": "A", "at": now - 3600},
                 "Gone-Dreamscythe": {"gone": 1, "at": now - 3600}}
        self.assertEqual(feed.refresh_profiles(api, "ns", sorted(cache), {}, cache, now), 1)
        self.assertEqual(cache["Early-Dreamscythe"]["v"], feed.PROFILE_SCHEMA,
                         "a record written before sex and spec is fetched again at once")
        self.assertEqual(cache["Gone-Dreamscythe"]["at"], now - 3600, "a gone one waits its week")

    def test_refresh_is_spread_over_days(self):
        ages = [feed.profile_max_age(f"P{i}-Dreamscythe") for i in range(400)]
        self.assertTrue(all(5 * 86400 < a <= 7 * 86400 for a in ages), "five to seven days")
        self.assertGreater(max(ages) - min(ages), 86400, "spread, not one morning")
        self.assertEqual(feed.profile_max_age("Abbé-Dreamscythe"), feed.profile_max_age("Abbé-Dreamscythe"),
                         "the same for a name every run")

    def test_refresh_keeps_what_came_when_the_budget_runs_out(self):
        api, fetch, _ = make_api({"/character/": [(200, {}, SUMMARY)]})
        calls = [0]
        real_get = api.get

        def get(path, ns, **kw):
            calls[0] += 1
            if calls[0] > 4:   # two players' summary and talents, then the budget is spent
                raise feed.FeedError("hourly request budget spent; stopping this run")
            return real_get(path, ns, **kw)
        api.get = get
        cache, lines = {}, []
        n = feed.refresh_profiles(api, "ns", ["A-Dreamscythe", "B-Dreamscythe", "C-Dreamscythe"],
                                  {}, cache, 1792300000, say=lines.append)
        self.assertEqual(n, 2)
        self.assertEqual(sorted(cache), ["A-Dreamscythe", "B-Dreamscythe"])
        self.assertIn("profiles stopped after 2", lines[0])

    def test_prune(self):
        now = 1792300000
        cache = {"Kept-Dreamscythe": {"at": 0}, "Recent-Dreamscythe": {"at": now - 86400},
                 "Old-Dreamscythe": {"at": now - 31 * 86400}}
        feed.prune_cache(cache, ["Kept-Dreamscythe"], now)
        self.assertEqual(sorted(cache), ["Kept-Dreamscythe", "Recent-Dreamscythe"],
                         "only a summary for someone off the data a month goes")

    def test_attach(self):
        prev_time = 1792200000
        cache = {
            "Bootii-Dreamscythe": {"f": "H", "c": "ROGUE", "r": "BloodElf", "g": "Gank Squad", "l": prev_time - 5 * 86400},
            "Idle-Dreamscythe": {"f": "A", "c": "MAGE", "r": "Gnome", "g": "", "l": prev_time - 9 * 86400},
            "Gone-Dreamscythe": {"gone": 1},
            "Zed-Nightslayer": {"f": "H", "c": "MAGE", "r": "Troll", "g": "", "l": 1},
        }
        previous = {"generated": prev_time, "players": {
            "Bootii-Dreamscythe": {"2": {"1": 1500, "2": 10, "3": 10}, "t": prev_time},
            "Idle-Dreamscythe": {"3": {"1": 1700, "2": 4, "3": 4}, "t": prev_time,
                                 "w": {"1": "A", "2": "MAGE", "3": "Gnome", "4": prev_time - 2 * 86400}},
        }}
        players = {
            "Bootii-Dreamscythe": {2: (1512, 11, 10), "t": prev_time + 86400},
            "Idle-Dreamscythe": {3: (1700, 4, 4), "t": prev_time + 86400},
            "Gone-Dreamscythe": {2: (1600, 1, 1), "t": 1},
            "New-Dreamscythe": {2: (1600, 1, 1), "t": 1},
            "Zed-Nightslayer": {2: (1600, 1, 1), "t": 1},
        }
        self.assertEqual(feed.attach_profiles(players, cache, previous), 2)
        self.assertEqual(players["Bootii-Dreamscythe"]["w"], ("H", "ROGUE", "BloodElf", prev_time, "Gank Squad", "", ""),
                         "a record that moved since the last run means they logged in after it")
        self.assertEqual(players["Idle-Dreamscythe"]["w"][3], prev_time - 2 * 86400,
                         "an unchanged record keeps the newest login known, the last file's included")
        self.assertNotIn("w", players["Gone-Dreamscythe"], "a 404 describes nobody")
        self.assertNotIn("w", players["New-Dreamscythe"], "nothing cached, nothing written")
        self.assertNotIn("w", players["Zed-Nightslayer"], "only the home realm is described")

    @unittest.skipUnless(HAVE_LUAJIT, "luajit not installed")
    def test_render_w_loads_back(self):
        data = {"generated": 1792200000, "region": "us", "namespace": "dynamic-classicann-us", "season": 3,
                "players": {
                    "Bootii-Dreamscythe": {2: (1512, 11, 10), "w": ("H", "ROGUE", "BloodElf", 1792200000, 'Gank "Squad"',
                                                                    "F", "SUBTLETY"), "t": 1792200000},
                    "Loner-Dreamscythe": {3: (1700, 4, 4), "w": ("A", "PRIEST", "NightElf", 0, ""), "t": 1792200000},
                }}
        text = feed.render_lua(data)
        self.assertIn('["Bootii-Dreamscythe"] = { [2] = { 1512, 11, 10 }, w = { "H", "ROGUE", "BloodElf", '
                      '1792200000, "Gank \\"Squad\\"", sex = "F", spec = "SUBTLETY" }, t = 1792200000 },', text)
        self.assertIn('w = { "A", "PRIEST", "NightElf", 0 }, t = 1792200000', text, "no guild, no fifth field")
        path = Path(self.tmp.name) / "CommanderLadderData.lua"
        feed.write_atomically(path, text)
        back = feed.read_previous(path)
        self.assertEqual(back["players"]["Bootii-Dreamscythe"]["w"],
                         {"1": "H", "2": "ROGUE", "3": "BloodElf", "4": 1792200000, "5": 'Gank "Squad"',
                          "sex": "F", "spec": "SUBTLETY"})
        self.assertEqual(feed.entry_from_json(back["players"]["Bootii-Dreamscythe"]),
                         {2: (1512, 11, 10), "t": 1792200000}, "the ratings read back as before")

    def run_feed(self, api, previous=None):
        written = {}
        saved = (feed.connect, feed.read_wanted, feed.read_previous, feed.write_atomically, feed.PROFILE_CACHE)
        real_write = feed.write_atomically
        feed.connect = lambda: api
        feed.read_wanted = lambda: {}
        feed.read_previous = lambda: previous
        feed.PROFILE_CACHE = self.cache_path

        def write(path, text, suffix=".lua"):
            if suffix == ".lua":
                written["text"] = text
            else:
                real_write(path, text, suffix=suffix)
        feed.write_atomically = write
        try:
            self.assertEqual(feed.run(lambda *_: None), 0)
        finally:
            (feed.connect, feed.read_wanted, feed.read_previous, feed.write_atomically,
             feed.PROFILE_CACHE) = saved
        return written["text"]

    def test_run_describes_the_home_realm_once_a_week(self):
        board = {"entries": [
            {"character": {"name": "Bootii", "realm": {"slug": "dreamscythe"}}, "faction": {"type": "HORDE"},
             "rating": 1512, "season_match_statistics": {"won": 11, "lost": 10}},
            {"character": {"name": "Zed", "realm": {"slug": "nightslayer"}}, "faction": {"type": "HORDE"},
             "rating": 1888, "season_match_statistics": {"won": 10, "lost": 2}},
        ]}
        routes = {
            "/data/wow/realm/index": [(200, {}, REALM_INDEX)],
            "/data/wow/pvp-season/index": [(200, {}, {"current_season": {"id": 3}})],
            "/pvp-leaderboard/": [(200, {}, board)],
            "/character/dreamscythe/polypopin/pvp-bracket/": [(200, {}, {"rating": 1534})],
            "/character/dreamscythe/bootii?": [(200, {}, SUMMARY)],
            "/character/dreamscythe/bootii/specializations?": [(200, {}, SPECS)],
        }
        api, fetch, _ = make_api(routes)
        text = self.run_feed(api)
        self.assertIn('[5] = { 1512, 11, 10 }, w = { "H", "ROGUE", "BloodElf", 1792250000, "Gank Squad", '
                      'sex = "F", spec = "SUBTLETY" }, t = ', text)
        self.assertIn('["Zed-Nightslayer"] = { [2] = { 1888, 10, 2 }, [3] = { 1888, 10, 2 }, [5] = { 1888, 10, 2 }, t = ',
                      text, "another realm: ratings only")
        self.assertFalse(any("/character/nightslayer/zed?" in c[0] for c in fetch.calls),
                         "no summary is fetched for another realm")
        self.assertIn("Bootii-Dreamscythe", feed.load_cache(self.cache_path), "the summary is cached")
        # The next day: the cache answers, no summary is fetched again, the line is the same
        api2, fetch2, _ = make_api(routes)
        text2 = self.run_feed(api2)
        self.assertFalse(any("/character/dreamscythe/bootii?" in c[0] for c in fetch2.calls),
                         "a summary under a week old comes from the cache")
        self.assertIn('w = { "H", "ROGUE", "BloodElf", 1792250000, "Gank Squad", sex = "F", spec = "SUBTLETY" }', text2)

    def test_fields_prints_names_not_values(self):
        board = {"entries": [
            {"character": {"name": "Zed", "realm": {"slug": "nightslayer"}}, "rating": 1888},
            {"character": {"name": "Bootii", "id": 7, "realm": {"slug": "dreamscythe"}},
             "faction": {"type": "HORDE"}, "rating": 1512, "season_match_statistics": {"won": 11, "lost": 10}},
        ]}
        api, fetch, _ = make_api({
            "/data/wow/realm/index": [(200, {}, REALM_INDEX)],
            "/data/wow/pvp-season/index": [(200, {}, {"current_season": {"id": 3}})],
            "/pvp-leaderboard/2v2": [(200, {}, board)],
            "/character/dreamscythe/bootii?": [(200, {}, SUMMARY)],
        })
        lines = []
        real = feed.connect
        feed.connect = lambda: api
        try:
            self.assertEqual(feed.fields(lines.append), 0)
        finally:
            feed.connect = real
        text = "\n".join(lines)
        self.assertIn("leaderboard entry for Bootii-dreamscythe", text, "the one value: a home-realm sample's name")
        self.assertIn("faction.type (str)", text)
        self.assertIn("guild.name (str)", text)
        self.assertIn("last_login_timestamp (int)", text)
        self.assertIn("faction: present (also on the leaderboard entry)", text)
        for value in ("Gank Squad", "HORDE", "1792250000", "1512", "Blood Elf"):
            self.assertNotIn(value, text, "field values are never printed")
        self.assertNotIn("tok-XYZ-123456", text)



if __name__ == "__main__":
    unittest.main(verbosity=1)
