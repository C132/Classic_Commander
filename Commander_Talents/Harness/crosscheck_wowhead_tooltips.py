#!/usr/bin/env python3
"""Cross-check every talent RANK TOOLTIP against Wowhead's TBC Classic data.

crosscheck_wowsims.py covers the grid — roster, position, max rank, prereq
edges. This covers the text, which is where the drift was: the generated data
carried a lot of vanilla-era wording that TBC replaced outright (Paladin
Redoubt and Divine Purpose, Mage Improved Blink, Warrior Improved Rend...).

Ground truth is Wowhead's own talent-calculator dataset, which gives the exact
spell id for every rank of every talent, plus the tooltip endpoint that
renders that spell's description:

    https://nether.wowhead.com/data/talents-classic?dataEnv=5&locale=0
    https://nether.wowhead.com/tooltip/spell/<id>?dataEnv=5&locale=0

dataEnv=5 tracks the live 2.5.5 Anniversary client, not 2.4.3 — so it carries
the client's current names (Subjugate Demon, Succubus/Incubus). That is what
the game shows, so that is what we mirror.

Usage:
    python3 Harness/crosscheck_wowhead_tooltips.py            # report only
    python3 Harness/crosscheck_wowhead_tooltips.py --apply    # rewrite data
    python3 Harness/crosscheck_wowhead_tooltips.py --refresh  # re-fetch cache

The cache lives in Harness/wowhead/ and is reused between runs; --refresh
re-pulls all ~1700 rank tooltips (a few minutes).

KNOWN NON-ISSUES — Wowhead rendering artifacts, deliberately NOT adopted:
  * a bare "0" where the value scales with level (Rogue Serrated Blades); we
    keep the level-70 figure the game actually prints.
  * scaling-variant lists ("110 / Sinister Calling: 111 / ...", Hemorrhage).
  * the DBC "More effective than <Talent> (Rank N)." auxiliary sentence, which
    the talent frame does not show.
  * icons from the tooltip endpoint, which serves modern retail art; icons are
    checked against the talent-calculator payload instead.
"""
import argparse, difflib, html, json, os, re, subprocess, sys, time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
CACHE_DIR = os.path.join(HERE, "wowhead")
CALC = os.path.join(CACHE_DIR, "talents_calc.json")
TIPS = os.path.join(CACHE_DIR, "tooltips.json")
LUAJIT = os.environ.get("LUAJIT", "/opt/homebrew/bin/luajit")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

CLASSES = {
    "WARRIOR": "CommanderTalentsData_Warrior.lua", "PALADIN": "CommanderTalentsData_Paladin.lua",
    "HUNTER": "CommanderTalentsData_Hunter.lua", "ROGUE": "CommanderTalentsData_Rogue.lua",
    "PRIEST": "CommanderTalentsData_Priest.lua", "SHAMAN": "CommanderTalentsData_Shaman.lua",
    "MAGE": "CommanderTalentsData_Mage.lua", "WARLOCK": "CommanderTalentsData_Warlock.lua",
    "DRUID": "CommanderTalentsData_Druid.lua",
}

DUMPER = r'''
local file, token = ...
CommanderTalentsData = { Classes = {} }
function CommanderTalentsData.AddPvPBuilds() end
assert(loadfile(file))()
local class = CommanderTalentsData.Classes[token]
assert(class, "missing class " .. tostring(token))
for _, tree in ipairs(class.trees) do
    for _, t in ipairs(tree.talents) do
        for i = 1, #t.ranks do
            print(table.concat({ tree.bg, tree.name, t.name, t.icon,
                t.row, t.col, t.max, i, (t.ranks[i]:gsub("\n", "\\n")) }, "\t"))
        end
    end
end
'''

RANKLINE = re.compile(r'^(\s*)"((?:[^"\\]|\\.)*)",\s*$')
MORE_EFFECTIVE = re.compile(r"\s*More effective than [^.]+\(Rank \d+\)\.\s*$")
SCALING_VARIANT = re.compile(r"\d+(?:\.\d+)?\s*/\s*[A-Z][\w' ]+:\s*\d")


# ------------------------------------------------------------------ fetching
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def load_calc(refresh):
    os.makedirs(CACHE_DIR, exist_ok=True)
    if refresh or not os.path.exists(CALC):
        raw = get("https://nether.wowhead.com/data/talents-classic?dataEnv=5&locale=0")
        i = raw.index("{", raw.index("wow.talentCalcClassic.tbc.data"))
        data, _ = json.JSONDecoder().raw_decode(raw[i:])
        json.dump(data, open(CALC, "w"))
    return json.load(open(CALC))


def strip_html(t):
    t = re.sub(r"<br\s*/?>", "\n", t)
    return html.unescape(re.sub(r"<[^>]+>", "", t)).strip()


def load_tips(calc, refresh):
    ids = sorted({s for tree in calc["talents"].values()
                  for t in tree.values() for s in t["ranks"]})
    cache = {} if refresh or not os.path.exists(TIPS) else json.load(open(TIPS))
    todo = [i for i in ids if str(i) not in cache]
    if not todo:
        return cache

    def one(sid):
        for attempt in range(4):
            try:
                j = json.loads(get(f"https://nether.wowhead.com/tooltip/spell/{sid}"
                                   f"?dataEnv=5&locale=0"))
                body = re.findall(r'<div class="q">(.*?)</div>', j.get("tooltip", ""), re.S)
                return {"name": j.get("name", ""), "icon": j.get("icon", ""),
                        "desc": strip_html(body[-1]) if body else ""}
            except Exception as e:
                if attempt == 3:
                    return {"error": str(e)}
                time.sleep(1.5 * (attempt + 1))

    print(f"fetching {len(todo)} rank tooltips...", file=sys.stderr)
    with ThreadPoolExecutor(max_workers=8) as ex:
        for sid, res in zip(todo, ex.map(one, todo)):
            cache[str(sid)] = res
    json.dump(cache, open(TIPS, "w"))
    bad = [k for k, v in cache.items() if "error" in v]
    if bad:
        sys.exit(f"tooltip fetch failed for {len(bad)} spells, e.g. {bad[:5]}")
    return cache


# --------------------------------------------------------------- comparison
def tidy(s):
    return re.sub(r"[ \t]+", " ", s.replace(" ", " ")).strip()


def norm(s):
    s = s.replace(" ", " ").replace("’", "'").replace("\\n", " ")
    return re.sub(r"\s+", " ", s).strip().lower().rstrip(".")


def classify(ours, truth):
    """FIX (adopt Wowhead) or SKIP (Wowhead rendering artifact)."""
    if not truth:
        return "SKIP", "wowhead description empty"
    if SCALING_VARIANT.search(truth):
        return "SKIP", "wowhead scaling-variant list"
    stripped = MORE_EFFECTIVE.sub("", truth).strip()
    if norm(stripped) == norm(ours):
        return "SKIP", "auxiliary rank line / whitespace only"
    if re.search(r"\b0\b", truth) and not re.search(r"\b0\b", ours):
        mask = lambda s: re.sub(r"\b\d+\b", "#", norm(s))
        if mask(stripped) == mask(ours):
            return "SKIP", "wowhead level-scaling placeholder (0)"
    return "FIX", ""


def dump(token, fname, dumper_path):
    out = subprocess.run([LUAJIT, dumper_path, fname, token],
                         cwd=ADDON, capture_output=True, text=True)
    if out.returncode:
        sys.exit(f"{fname}: dump failed\n{out.stderr}")
    return [l.split("\t") for l in out.stdout.splitlines() if l.strip()]


def worddiff(a, b):
    sm = difflib.SequenceMatcher(None, a.split(), b.split())
    return [f"{tag}: {' '.join(a.split()[i1:i2])!r} -> {' '.join(b.split()[j1:j2])!r}"
            for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != "equal"]


def lua_escape(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    return s.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="rewrite the data files")
    ap.add_argument("--refresh", action="store_true", help="re-fetch the Wowhead cache")
    ap.add_argument("--verbose", action="store_true", help="show skipped artifacts too")
    args = ap.parse_args()

    calc = load_calc(args.refresh)
    tips = load_tips(calc, args.refresh)
    by_desc = {v["description"]: k for k, v in calc["trees"].items()}

    dumper_path = os.path.join(CACHE_DIR, "_dump.lua")
    open(dumper_path, "w").write(DUMPER)

    fixes = defaultdict(dict)          # file -> (tree, talent, rank) -> truth
    skipped, icons, issues = [], [], 0
    for token, fname in CLASSES.items():
        seen = set()
        for bg, treename, name, icon, row, col, mx, ri, text in dump(token, fname, dumper_path):
            tid = by_desc.get(bg)
            if tid is None:
                sys.exit(f"{token}: tree bg {bg!r} unknown to Wowhead")
            cell = (int(row) - 1, int(col) - 1)
            whT = next((t for t in calc["talents"][tid].values()
                        if (t["row"], t["col"]) == cell), None)
            if whT is None:
                print(f"  {token} {treename}/{name}: no Wowhead talent at r{row}c{col}")
                issues += 1
                continue
            if cell not in seen:
                seen.add(cell)
                if len(whT["ranks"]) != int(mx):
                    print(f"  {token} {treename}/{name}: max {mx}, Wowhead {len(whT['ranks'])}")
                    issues += 1
                want = whT["icon"]
                if want.lower() != icon.lower():
                    # Wowhead serves a few icons under a Classic-only asset
                    # name; the in-game texture is the unprefixed one.
                    if want.lower() == "classic_" + icon.lower():
                        skipped.append(f"{token} {treename}/{name}: classic_ icon alias")
                    else:
                        icons.append((fname, name, icon, want))
            i = int(ri) - 1
            if i >= len(whT["ranks"]):
                continue
            truth = tidy(tips.get(str(whT["ranks"][i]), {}).get("desc", ""))
            if norm(truth) == norm(text):
                continue
            action, reason = classify(text, truth)
            if action == "SKIP":
                skipped.append(f"{token} {treename}/{name} rank {ri}: {reason}")
                continue
            truth = MORE_EFFECTIVE.sub("", truth).strip()
            fixes[fname][(treename, name, int(ri))] = truth
            issues += 1
            print(f"  {token} {treename}/{name} rank {ri} (spell {whT['ranks'][i]})")
            for d in worddiff(text, truth):
                print(f"      {d}")

    for fname, name, ours, want in icons:
        print(f"  ICON {fname} {name}: {ours} -> {want}")
        issues += 1
    if args.apply and icons:
        for fname, name, ours, want in icons:
            path = os.path.join(ADDON, fname)
            src = open(path, encoding="utf-8").read()
            old = f'name = "{name}", icon = "{ours}"'
            if src.count(old) != 1:
                sys.exit(f"{fname}: {old!r} matched {src.count(old)} times — aborting")
            open(path, "w", encoding="utf-8").write(
                src.replace(old, f'name = "{name}", icon = "{want}"'))
            print(f"{fname}: {name} icon -> {want}")
    if args.verbose:
        for s in skipped:
            print(f"  (skipped) {s}")

    if args.apply and fixes:
        for token, fname in CLASSES.items():
            planned = fixes.get(fname)
            if not planned:
                continue
            rows = dump(token, fname, dumper_path)
            path = os.path.join(ADDON, fname)
            lines = open(path, encoding="utf-8").read().split("\n")
            slots, in_ranks = [], False
            for n, line in enumerate(lines):
                if "ranks = {" in line:
                    in_ranks = True
                elif in_ranks:
                    if RANKLINE.match(line):
                        slots.append(n)
                    else:
                        in_ranks = False
            if len(slots) != len(rows):
                sys.exit(f"{fname}: {len(slots)} rank lines vs {len(rows)} dumped — aborting")
            applied = 0
            for slot, (_bg, treename, name, _ic, _r, _c, _mx, ri, text) in zip(slots, rows):
                m = RANKLINE.match(lines[slot])
                if m.group(2).replace('\\"', '"') != text:
                    sys.exit(f"{fname}:{slot+1}: slot/dump disagree — aborting")
                truth = planned.get((treename, name, int(ri)))
                if truth is None:
                    continue
                lines[slot] = f'{m.group(1)}"{lua_escape(truth)}",'
                applied += 1
            if applied != len(planned):
                sys.exit(f"{fname}: {applied} of {len(planned)} slots matched — aborting")
            open(path, "w", encoding="utf-8").write("\n".join(lines))
            print(f"{fname}: rewrote {applied} rank string(s)")

    print(f"\nTOTAL: {issues} issue(s), {len(skipped)} known artifact(s) skipped"
          + ("" if not skipped or args.verbose else " (--verbose to list)"))
    return 1 if (issues and not args.apply) else 0


if __name__ == "__main__":
    sys.exit(main())
