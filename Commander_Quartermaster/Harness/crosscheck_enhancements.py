#!/usr/bin/env python3
"""Cross-check the generated enhancement database against Wowhead.

The generator reads the client's DB2 tables and a private-server world DB.
Both are good, and neither is the thing a player sees. Wowhead's tooltip
endpoint renders the LIVE Anniversary dataset (dataEnv=5, the same 2.5.x data
this account's client runs), so it is an independent witness to the four
facts a wrong answer would show up in first:

    name, quality, required level, and the gate — reputation standing for a
    vendor item, profession and rank for anything a craft or a jeweller
    restricts.

It is a REPORT, never a rewrite. Where the two disagree the right move is to
look, because the disagreement is as likely to be Wowhead rendering a later
patch as it is to be us.

KNOWN NON-ISSUE, deliberately normalised rather than reported: a required
level of 1 is not a requirement, and Wowhead prints no line for it. Three
items carry it (Light Armor Kit, Rough Sharpening Stone, Rough Weightstone).

    python3 Harness/crosscheck_enhancements.py            # cached, then report
    python3 Harness/crosscheck_enhancements.py --refresh  # re-fetch everything
    python3 Harness/crosscheck_enhancements.py --limit 50 # a quick sample
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
CACHE = os.environ.get("QM_CACHE") or os.path.join(HERE, ".cache")
TIPS = os.path.join(CACHE, "wowhead_enhance_tips.json")
DATA = os.path.join(ADDON, "CommanderQuartermasterEnhanceData.lua")
LUAJIT = os.environ.get("LUAJIT", "/opt/homebrew/bin/luajit")
URL = "https://nether.wowhead.com/tooltip/%s/%d?dataEnv=5&locale=0"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

TAG = re.compile(r"<[^>]+>")


def plain(markup):
    """Tooltip HTML to flat text, one field per line."""
    text = TAG.sub("\n", markup or "")
    text = html.unescape(text)
    return [line.strip() for line in text.split("\n") if line.strip()]


# --- the addon's own data, read by Lua so the file is parsed by its parser --
DUMP = r'''
dofile(%s)
local d = CommanderQuartermasterEnhanceData
local out = {}
for _, e in ipairs(d.Entries) do
    local rep, standing = "", ""
    for _, s in ipairs(e.src or {}) do
        if s.faction and s.faction.name then
            rep, standing = s.faction.name, s.faction.standing or ""
            break
        end
    end
    out[#out + 1] = table.concat({
        e.item or 0, e.spell or 0, e.ench or 0, e.name or "",
        e.quality or -1, e.lvl or 0,
        e.reqSkill and e.reqSkill.skill or "", e.reqSkill and e.reqSkill.rank or 0,
        e.prof and e.prof.skill or "", e.prof and e.prof.rank or 0,
        rep, standing, e.unobtainable and 1 or 0,
    }, "\t")
end
io.write(table.concat(out, "\n"))
'''


def load_entries():
    script = DUMP % ("[[%s]]" % DATA)
    proc = subprocess.run([LUAJIT, "-e", script], capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("luajit failed: %s" % proc.stderr[:400])
    rows = []
    for line in proc.stdout.splitlines():
        f = line.split("\t")
        rows.append({
            "item": int(f[0]), "spell": int(f[1]), "ench": int(f[2]), "name": f[3],
            "quality": int(f[4]), "lvl": int(f[5]),
            "reqSkill": f[6], "reqRank": int(f[7]),
            "profSkill": f[8], "profRank": int(f[9]),
            "faction": f[10], "standing": f[11],
            "unobtainable": f[12] == "1",
        })
    return rows


# --- Wowhead ---------------------------------------------------------------
def fetch(kind, ident):
    req = urllib.request.Request(URL % (kind, ident), headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError, TimeoutError):
        return None


def load_cache():
    if os.path.exists(TIPS):
        with open(TIPS, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_cache(cache):
    os.makedirs(CACHE, exist_ok=True)
    with open(TIPS, "w", encoding="utf-8") as f:
        json.dump(cache, f)


def gather(entries, cache, refresh, limit):
    want = []
    for e in entries:
        if e["item"]:
            want.append(("item", e["item"]))
        elif e["spell"]:
            want.append(("spell", e["spell"]))
    seen, todo = set(), []
    for kind, ident in want:
        key = "%s:%d" % (kind, ident)
        if key in seen:
            continue
        seen.add(key)
        if refresh or key not in cache:
            todo.append((kind, ident, key))
    if limit:
        todo = todo[:limit]
    if todo:
        sys.stderr.write("fetching %d tooltips…\n" % len(todo))
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = pool.map(lambda t: (t[2], fetch(t[0], t[1])), todo)
            for i, (key, payload) in enumerate(results, 1):
                cache[key] = payload
                if i % 100 == 0:
                    sys.stderr.write("  %d/%d\n" % (i, len(todo)))
        save_cache(cache)
    return cache


# --- comparison ------------------------------------------------------------
REQ_LEVEL = re.compile(r"^Requires Level$")
REQ_SKILL = re.compile(r"^\((\d+)\)$")
STANDINGS = ("Hated", "Hostile", "Unfriendly", "Neutral", "Friendly",
             "Honored", "Revered", "Exalted")


def parse_tip(payload):
    """The four facts, off the rendered tooltip."""
    if not payload:
        return None
    lines = plain(payload.get("tooltip", ""))
    out = {"name": payload.get("name"), "quality": payload.get("quality"),
           "lvl": 0, "skill": None, "rank": 0, "faction": None, "standing": None}
    for i, line in enumerate(lines):
        if line == "Requires Level" and i + 1 < len(lines):
            try:
                out["lvl"] = int(lines[i + 1])
            except ValueError:
                pass
        elif line.startswith("Requires ") and i + 1 < len(lines):
            rest = line[len("Requires "):].strip()
            nxt = lines[i + 1]
            if nxt.startswith("- ") and nxt[2:] in STANDINGS:
                out["faction"], out["standing"] = rest, nxt[2:]
        elif line == "Requires" and i + 2 < len(lines):
            # "Requires | <Skill> | (350)"
            m = REQ_SKILL.match(lines[i + 2])
            if m:
                out["skill"], out["rank"] = lines[i + 1], int(m.group(1))
            elif lines[i + 2].startswith("- ") and lines[i + 2][2:] in STANDINGS:
                out["faction"], out["standing"] = lines[i + 1], lines[i + 2][2:]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    entries = load_entries()
    cache = gather(entries, load_cache(), args.refresh, args.limit)

    checked = 0
    issues = {"name": [], "quality": [], "lvl": [], "skill": [], "rank": [],
              "faction": [], "standing": [], "missing": []}
    for e in entries:
        kind, ident = ("item", e["item"]) if e["item"] else ("spell", e["spell"])
        if not ident:
            continue
        payload = cache.get("%s:%d" % (kind, ident))
        if payload is None:
            if "%s:%d" % (kind, ident) in cache:
                issues["missing"].append((ident, e["name"]))
            continue
        tip = parse_tip(payload)
        if not tip:
            continue
        checked += 1
        if tip["name"] and e["name"] and tip["name"] != e["name"]:
            issues["name"].append((ident, e["name"], tip["name"]))
        if kind == "item":
            if tip["quality"] is not None and e["quality"] >= 0 \
                    and tip["quality"] != e["quality"]:
                issues["quality"].append((ident, e["name"], e["quality"], tip["quality"]))
            # "Requires Level 1" is not a requirement, and Wowhead does not
            # print one. Light Armor Kit, Rough Sharpening Stone and Rough
            # Weightstone are the only items in the set that carry it.
            if tip["lvl"] != (e["lvl"] if e["lvl"] > 1 else 0):
                issues["lvl"].append((ident, e["name"], e["lvl"], tip["lvl"]))
            # The skill line on an item is "you must HAVE this to use it"
            if tip["skill"] and tip["skill"] != e["reqSkill"]:
                issues["skill"].append((ident, e["name"], e["reqSkill"], tip["skill"]))
            elif tip["skill"] and tip["rank"] != e["reqRank"]:
                issues["rank"].append((ident, e["name"], e["reqRank"], tip["rank"]))
            if tip["faction"]:
                if tip["faction"] != e["faction"]:
                    issues["faction"].append((ident, e["name"], e["faction"], tip["faction"]))
                elif tip["standing"] != e["standing"]:
                    issues["standing"].append((ident, e["name"], e["standing"], tip["standing"]))

    print("cross-checked %d of %d entries against Wowhead (dataEnv=5)" % (checked, len(entries)))
    total = 0
    for key in ("name", "quality", "lvl", "skill", "rank", "faction", "standing", "missing"):
        rows = issues[key]
        total += len(rows)
        print("  %-9s %4d" % (key, len(rows)))
        show = rows if args.verbose else rows[:8]
        for row in show:
            print("      " + " | ".join(str(x) for x in row))
        if not args.verbose and len(rows) > len(show):
            print("      …%d more (--verbose)" % (len(rows) - len(show)))
    print("total disagreements: %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
