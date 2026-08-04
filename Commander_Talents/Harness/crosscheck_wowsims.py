#!/usr/bin/env python3
"""Cross-check Commander_Talents class data against wowsims/tbc talent configs.

Compares, per class and tree: talent roster (by normalized name, with cell
fallback), grid position, max rank, and prerequisite edges. wowsims is
DBC-derived and treated as truth for structure; names/text stay ours.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
SCRATCH = HERE
ADDON = HERE.parent

CLASSES = {
    "WARRIOR": "Warrior", "PALADIN": "Paladin", "HUNTER": "Hunter",
    "ROGUE": "Rogue", "PRIEST": "Priest", "SHAMAN": "Shaman",
    "MAGE": "Mage", "WARLOCK": "Warlock", "DRUID": "Druid",
}

def norm(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())

TS_TREE = re.compile(r"name: '([^']+)',\s*backgroundUrl")
TS_TALENT = re.compile(
    r"\{\s*(?:(?://)?fieldName: '([^']+)',\s*)?"
    r"location: \{\s*rowIdx: (\d+),\s*colIdx: (\d+),?\s*\},"
    r"(?:\s*prereqLocation: \{\s*rowIdx: (\d+),\s*colIdx: (\d+),?\s*\},)?"
    r"(?:\s*prereqOfLocation: \{[^}]*\},)?"
    r"\s*spellIds: \[[^\]]*\],\s*maxPoints: (\d+)",
    re.S)

def parse_ts(path: Path):
    text = path.read_text()
    trees = []  # [(name, start_offset)]
    for m in TS_TREE.finditer(text):
        trees.append((m.group(1), m.start()))
    out = []  # per tree: dict norm -> talent
    for i, (tname, start) in enumerate(trees):
        end = trees[i + 1][1] if i + 1 < len(trees) else len(text)
        seg = text[start:end]
        talents = {}
        by_cell = {}
        for tm in TS_TALENT.finditer(seg):
            field, r, c, pr, pc, mx = tm.groups()
            if field is None:
                field = f"cell{int(r) + 1}x{int(c) + 1}"
            t = {
                "name": field, "norm": norm(field),
                "row": int(r) + 1, "col": int(c) + 1,
                "max": int(mx),
                "prereq_cell": (int(pr) + 1, int(pc) + 1) if pr is not None else None,
            }
            talents[t["norm"]] = t
            by_cell[(t["row"], t["col"])] = t
        # resolve prereq cells to names
        for t in talents.values():
            if t["prereq_cell"]:
                target = by_cell.get(t["prereq_cell"])
                t["prereq"] = target["norm"] if target else f"?cell{t['prereq_cell']}"
            else:
                t["prereq"] = None
        out.append({"name": tname, "talents": talents, "by_cell": by_cell})
    return out

LUA_TREE = re.compile(r'name = "([^"]+)", bg = "([^"]+)"')
LUA_TALENT = re.compile(
    r'\{ name = "([^"]+)", icon = "([^"]*)", row = (\d+), col = (\d+), max = (\d+)'
    r'(?:, req = "([^"]+)")?,')

def parse_lua(path: Path):
    text = path.read_text()
    trees = []
    for m in LUA_TREE.finditer(text):
        trees.append((m.group(1), m.start()))
    out = []
    for i, (tname, start) in enumerate(trees):
        end = trees[i + 1][1] if i + 1 < len(trees) else len(text)
        seg = text[start:end]
        talents = {}
        by_cell = {}
        for tm in LUA_TALENT.finditer(seg):
            name, icon, r, c, mx, req = tm.groups()
            t = {"name": name, "norm": norm(name), "row": int(r), "col": int(c),
                 "max": int(mx), "prereq": norm(req) if req else None}
            talents[t["norm"]] = t
            by_cell[(t["row"], t["col"])] = t
        out.append({"name": tname, "talents": talents, "by_cell": by_cell})
    return out

total_issues = 0
for token, fname in CLASSES.items():
    ts = parse_ts(SCRATCH / "wowsims" / f"{fname.lower()}.ts")
    lua = parse_lua(ADDON / f"CommanderTalentsData_{fname}.lua")
    issues = []
    if len(ts) != 3 or len(lua) != 3:
        issues.append(f"tree count ts={len(ts)} lua={len(lua)}")
    for ti in range(min(len(ts), len(lua))):
        T, L = ts[ti], lua[ti]
        tname = L["name"]
        # pair by name first, then by cell for the leftovers
        matched = {}  # ts_norm -> lua talent
        lua_left = dict(L["talents"])
        for n, t in T["talents"].items():
            if n in lua_left:
                matched[n] = lua_left.pop(n)
        for n, t in list(T["talents"].items()):
            if n in matched:
                continue
            cellmate = None
            for ln, lt in lua_left.items():
                if (lt["row"], lt["col"]) == (t["row"], t["col"]):
                    cellmate = ln
                    break
            if cellmate:
                matched[n] = lua_left.pop(cellmate)
                # informational only: every observed case is a wowsims-side
                # typo/rename ('deterrance', 'improvedSayaad', anonymous cells)
                print(f"   (name-variance) [{tname}] ts:{t['name']} vs ours:'{matched[n]['name']}' at {t['row']},{t['col']}")
            else:
                issues.append(f"[{tname}] MISSING {t['name']} at {t['row']},{t['col']} max {t['max']}")
        for ln, lt in lua_left.items():
            issues.append(f"[{tname}] EXTRA '{lt['name']}' at {lt['row']},{lt['col']}")
        for n, lt in matched.items():
            t = T["talents"][n]
            if (t["row"], t["col"]) != (lt["row"], lt["col"]):
                issues.append(f"[{tname}] POS '{lt['name']}': ours {lt['row']},{lt['col']} -> dbc {t['row']},{t['col']}")
            if t["max"] != lt["max"]:
                issues.append(f"[{tname}] MAX '{lt['name']}': ours {lt['max']} -> dbc {t['max']}")
            # prereq compare (ts prereq norm may name a talent matched under a
            # different lua name; translate through the pairing when possible)
            tp = t["prereq"]
            if tp and tp in matched:
                tp_lua = matched[tp]["norm"]
            else:
                tp_lua = tp
            lp = lt["prereq"]
            if tp_lua != lp:
                issues.append(f"[{tname}] PREREQ '{lt['name']}': ours {lp or '-'} -> dbc {tp_lua or '-'}")
    if issues:
        total_issues += len(issues)
        print(f"== {token}: {len(issues)} issue(s)")
        for s in issues:
            print("   " + s)
    else:
        print(f"== {token}: clean")

print(f"\nTOTAL: {total_issues} issue(s)")
sys.exit(0 if total_issues == 0 else 1)
