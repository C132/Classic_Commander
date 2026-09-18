"""Read tables out of a CMaNGOS SQL dump without a database.

One pass over the file, keeping only the INSERT lines of the tables asked for,
then a small tokenizer for the VALUES tuples (quoted strings with backslash
escapes, NULL, numbers). Column names come from the CREATE TABLE statement so
rows come back as dicts.
"""
import re

def _columns(sql, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\) ENGINE" % re.escape(table), sql, re.S)
    if not m:
        raise KeyError(table)
    cols = []
    for line in m.group(1).split("\n"):
        line = line.strip()
        mm = re.match(r"`([^`]+)`", line)
        if mm and not line.startswith(("PRIMARY", "KEY", "UNIQUE", "INDEX", "CONSTRAINT")):
            cols.append(mm.group(1))
    return cols

_TOKEN = re.compile(r"'((?:[^'\\]|\\.)*)'|(NULL)|(-?\d+(?:\.\d+)?(?:e-?\d+)?)")

def _tuples(values):
    """Yield lists of Python values for each (...) tuple in a VALUES clause."""
    i, n = 0, len(values)
    while i < n:
        if values[i] != "(":
            i += 1
            continue
        i += 1
        row = []
        while True:
            m = _TOKEN.match(values, i)
            if not m:
                # skip separators
                if values[i] == ")":
                    i += 1
                    break
                i += 1
                continue
            if m.group(1) is not None:
                row.append(m.group(1).replace("\\'", "'").replace('\\"', '"').replace("\\\\", "\\"))
            elif m.group(2) is not None:
                row.append(None)
            else:
                v = m.group(3)
                row.append(float(v) if ("." in v or "e" in v) else int(v))
            i = m.end()
            # after a token: ',' or ')'
            while i < n and values[i] not in ",)":
                i += 1
            if i < n and values[i] == ")":
                i += 1
                break
            i += 1
        yield row

def read(path, tables):
    """Return {table: [row dicts]} for the named tables."""
    sql = open(path, encoding="utf8", errors="replace").read()
    out = {t: [] for t in tables}
    cols = {t: _columns(sql, t) for t in tables}
    prefixes = {("INSERT INTO `%s` VALUES " % t): t for t in tables}
    for line in sql.split("\n"):
        for prefix, t in prefixes.items():
            if line.startswith(prefix):
                body = line[len(prefix):]
                c = cols[t]
                for tup in _tuples(body):
                    if len(tup) == len(c):
                        out[t].append(dict(zip(c, tup)))
                    else:
                        out[t].append(dict(zip(c, tup + [None] * (len(c) - len(tup)))))
                break
    return out
