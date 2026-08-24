#!/usr/bin/env python3
"""Stage the CMaNGOS TBC world database into SQLite for the enhancement generator.

The enhancement database has to answer "where does this come from?" for every
source a TBC item can have — vendor (with extended-cost currencies), boss and
trash drops, reference loot, containers, quests, trainers, prospecting,
fishing, disenchanting, pickpocketing, skinning, mail. None of that lives in
the client's DB2 tables (it is server-side), and Wowhead's item pages are not
fetchable from a script. The CMaNGOS TBC world DB is, and it is the same data
the private-server ecosystem has been correcting for fifteen years.

    python3 Harness/tbcdb_to_sqlite.py --fetch      # download + build
    python3 Harness/tbcdb_to_sqlite.py              # rebuild from cache

Everything lands in the scratch cache directory (default Harness/.cache), which
is deliberately NOT committed — the generator's OUTPUT is what ships.
"""
import argparse
import gzip
import os
import re
import sqlite3
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.environ.get("QM_CACHE") or os.path.join(HERE, ".cache")
DUMP_URL = ("https://github.com/cmangos/tbc-db/raw/master/Full_DB/"
            "TBCDB_1.11.0_Vengeance_One_A_Cmangos_Story.sql.gz")
DUMP_GZ = os.path.join(CACHE, "tbcdb.sql.gz")
DB_PATH = os.path.join(CACHE, "tbcdb.sqlite")

# Only what the generator reads. Everything else in a 100 MB dump is ballast.
TABLES = [
    "item_template",
    "npc_vendor", "npc_vendor_template",
    "creature_template", "creature", "creature_zone",
    "gameobject_template", "gameobject",
    "creature_loot_template", "gameobject_loot_template", "item_loot_template",
    "reference_loot_template", "disenchant_loot_template", "fishing_loot_template",
    "pickpocketing_loot_template", "prospecting_loot_template", "skinning_loot_template",
    "mail_loot_template",
    "quest_template", "creature_questrelation", "creature_involvedrelation",
    "gameobject_questrelation", "gameobject_involvedrelation",
    "npc_trainer", "npc_trainer_template",
    "skill_extra_item_template",
]

CREATE_RE = re.compile(r"^CREATE TABLE `([a-z_0-9]+)`")
COLUMN_RE = re.compile(r"^\s*`([A-Za-z_0-9]+)`\s+([a-z]+)")
INSERT_RE = re.compile(r"^INSERT INTO `([a-z_0-9]+)` VALUES ")


def fetch(force=False):
    os.makedirs(CACHE, exist_ok=True)
    if os.path.exists(DUMP_GZ) and not force:
        return
    req = urllib.request.Request(DUMP_URL, headers={"User-Agent": "Mozilla/5.0"})
    sys.stderr.write("fetching %s\n" % DUMP_URL)
    with urllib.request.urlopen(req, timeout=900) as r, open(DUMP_GZ + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(DUMP_GZ + ".part", DUMP_GZ)


# mysql type -> sqlite affinity. Affinity is not cosmetic here: every value
# arrives from the dump as a python string, and only an INTEGER/REAL column
# converts it on insert. Leave it off and `WHERE entry = 29191` matches
# nothing, because the stored value is the text '29191'.
def affinity(mysql_type):
    t = mysql_type.lower()
    if t in ("tinyint", "smallint", "mediumint", "int", "bigint", "year"):
        return "INTEGER"
    if t in ("float", "double", "decimal", "numeric"):
        return "REAL"
    return "TEXT"


def read_schemas():
    """table -> [(column, affinity)], read from the dump's own CREATE TABLE blocks."""
    schemas, cur, cols = {}, None, []
    with gzip.open(DUMP_GZ, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if cur is None:
                m = CREATE_RE.match(line)
                if m and m.group(1) in TABLES:
                    cur, cols = m.group(1), []
                continue
            if line.startswith(")"):
                schemas[cur] = cols
                cur = None
                continue
            m = COLUMN_RE.match(line)
            if m and m.group(1).upper() not in ("PRIMARY", "KEY", "UNIQUE", "INDEX"):
                cols.append((m.group(1), affinity(m.group(2))))
    missing = [t for t in TABLES if t not in schemas]
    if missing:
        raise SystemExit("dump is missing tables: %s" % ", ".join(missing))
    return schemas


def split_tuples(payload):
    """Yield one list of python values per `(...)` tuple in a mysqldump VALUES body.

    Hand-rolled because the payload is a single multi-megabyte line and the
    values carry apostrophes, escaped quotes and embedded parentheses (creature
    names, quest text). State machine over the raw text, no regex backtracking.
    """
    i, n = 0, len(payload)
    while i < n:
        while i < n and payload[i] != "(":
            i += 1
        if i >= n:
            return
        i += 1
        row, field, in_str, esc = [], [], False, False
        while i < n:
            c = payload[i]
            if in_str:
                if esc:
                    field.append(c)
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == "'":
                    in_str = False
                else:
                    field.append(c)
            else:
                if c == "'":
                    in_str = True
                elif c == ",":
                    row.append("".join(field))
                    field = []
                elif c == ")":
                    row.append("".join(field))
                    i += 1
                    break
                else:
                    field.append(c)
            i += 1
        yield [None if v == "NULL" else v for v in row]


def build(schemas):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    con.execute("PRAGMA journal_mode=OFF")
    con.execute("PRAGMA synchronous=OFF")
    for table, cols in schemas.items():
        con.execute("CREATE TABLE %s (%s)" %
                    (table, ", ".join('"%s" %s' % (c, a) for c, a in cols)))
    counts = {t: 0 for t in schemas}
    with gzip.open(DUMP_GZ, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = INSERT_RE.match(line)
            if not m:
                continue
            table = m.group(1)
            cols = schemas.get(table)
            if not cols:
                continue
            stmt = "INSERT INTO %s VALUES (%s)" % (table, ", ".join("?" * len(cols)))
            rows = []
            for row in split_tuples(line[m.end():]):
                if len(row) != len(cols):
                    raise SystemExit("%s: expected %d columns, got %d" %
                                     (table, len(cols), len(row)))
                rows.append(row)
            con.executemany(stmt, rows)
            counts[table] += len(rows)
    for table in schemas:
        first = schemas[table][0][0]
        con.execute('CREATE INDEX idx_%s_1 ON %s ("%s")' % (table, table, first))
    # The lookups the generator actually leans on
    con.execute("CREATE INDEX idx_loot_item ON creature_loot_template (item)")
    con.execute("CREATE INDEX idx_goloot_item ON gameobject_loot_template (item)")
    con.execute("CREATE INDEX idx_itemloot_item ON item_loot_template (item)")
    con.execute("CREATE INDEX idx_refloot_item ON reference_loot_template (item)")
    con.execute("CREATE INDEX idx_vendor_item ON npc_vendor (item)")
    con.execute("CREATE INDEX idx_vendort_item ON npc_vendor_template (item)")
    con.execute("CREATE INDEX idx_creature_id ON creature (id)")
    con.commit()
    con.close()
    for table in sorted(counts):
        sys.stderr.write("  %-32s %8d rows\n" % (table, counts[table]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true", help="download the dump if absent")
    ap.add_argument("--refresh", action="store_true", help="re-download the dump")
    args = ap.parse_args()
    if args.fetch or args.refresh or not os.path.exists(DUMP_GZ):
        fetch(force=args.refresh)
    build(read_schemas())
    sys.stderr.write("wrote %s\n" % DB_PATH)


if __name__ == "__main__":
    main()
