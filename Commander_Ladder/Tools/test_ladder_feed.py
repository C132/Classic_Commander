#!/usr/bin/env python3
"""Offline tests for ladder_feed.py: fixtures only, no network, no Keychain.

    python3 -I test_ladder_feed.py

Covers the payload parsers, realm names, the Lua writer (loaded back through luajit),
the sandboxed SavedVariables shim, carry-over between runs, the HTTP retry rules,
and that credentials never reach any output.
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


if __name__ == "__main__":
    unittest.main(verbosity=1)
