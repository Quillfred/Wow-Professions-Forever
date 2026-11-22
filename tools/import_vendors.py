#!/usr/bin/env python3
"""Which factions can buy each pattern from a vendor.

Vendor lists are server-side, so they come from the open-source cMaNGOS Classic
database (github.com/cmangos/classic-db, Full_DB/*.sql.gz). Whether a vendor will
trade with Horde or Alliance players is decided with Forever's own FactionTemplate
table (wago.tools, same build as the rest of the data).

Usage: python3 -I tools/import_vendors.py CLASSICDB.sql.gz FactionTemplate.csv
Writes tools/vendor_factions.json:
  {patternItemID: {"A": bool, "H": bool, "v": [[vendor name, "A"|"H"|"AH"], ...]}}

Classic data: Forever may have moved or added vendors. In game, a vendor you visit
overrides this (see Core.ScanMerchant).
"""
import csv, gzip, json, os, re, sys

# Player factions (Faction IDs) of each side, for templates that name enemies one by one.
ALLIANCE = {72, 47, 69, 54, 469, 1094}       # Stormwind, Ironforge, Darnassus, Gnomeregan, Alliance
HORDE = {76, 81, 68, 530, 67, 1095}          # Orgrimmar, Thunder Bluff, Undercity, Darkspear, Horde
GROUP_PLAYER, GROUP_ALLIANCE, GROUP_HORDE = 1, 2, 4


def sql_rows(path, table):
    """Yield value tuples of `INSERT INTO `table` VALUES (...),(...);` lines."""
    head = f"INSERT INTO `{table}` VALUES "
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith(head):
                continue
            s, i, n = line, len(head), len(line)
            while i < n:
                if s[i] != "(":
                    i += 1
                    continue
                i += 1
                row, cur, quoted = [], [], False
                while i < n:
                    c = s[i]
                    if quoted:
                        if c == "\\":
                            cur.append(s[i + 1]); i += 2; continue
                        if c == "'":
                            quoted = False; i += 1; continue
                        cur.append(c); i += 1; continue
                    if c == "'":
                        quoted = True; i += 1; continue
                    if c == ",":
                        row.append("".join(cur)); cur = []; i += 1; continue
                    if c == ")":
                        row.append("".join(cur)); i += 1; break
                    cur.append(c); i += 1
                yield row


def columns(path, table):
    cols, inside = [], False
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith(f"CREATE TABLE `{table}`"):
                inside = True
                continue
            if inside:
                m = re.match(r"\s+`(\w+)`", line)
                if m:
                    cols.append(m.group(1))
                elif "KEY" in line or line.startswith(")"):
                    return cols
    return cols


def main():
    sqlgz, ftcsv = sys.argv[1], sys.argv[2]
    hostile = {}  # faction template -> (hostile to Alliance players, hostile to Horde players)
    with open(ftcsv, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            enemy = int(r["EnemyGroup"])
            enemies = {int(r[f"Enemies_{k}"]) for k in range(8) if f"Enemies_{k}" in r}
            hostile[int(r["ID"])] = (bool(enemy & (GROUP_PLAYER | GROUP_ALLIANCE)) or bool(enemies & ALLIANCE),
                                     bool(enemy & (GROUP_PLAYER | GROUP_HORDE)) or bool(enemies & HORDE))

    ic = columns(sqlgz, "item_template")
    recipes = {int(r[ic.index("entry")]) for r in sql_rows(sqlgz, "item_template")
               if r[ic.index("class")] == "9"}  # class 9 = Recipe

    cc = columns(sqlgz, "creature_template")
    E, N, F, VT = cc.index("Entry"), cc.index("Name"), cc.index("Faction"), cc.index("VendorTemplateId")
    npcs = {int(r[E]): (r[N], int(r[F]), int(r[VT])) for r in sql_rows(sqlgz, "creature_template")}

    sells = {}  # vendor entry or template id -> items
    for r in sql_rows(sqlgz, "npc_vendor"):
        sells.setdefault(("npc", int(r[0])), set()).add(int(r[1]))
    for r in sql_rows(sqlgz, "npc_vendor_template"):
        sells.setdefault(("tpl", int(r[0])), set()).add(int(r[1]))

    out = {}
    for entry, (name, faction, tpl) in npcs.items():
        items = sells.get(("npc", entry), set()) | (sells.get(("tpl", tpl), set()) if tpl else set())
        items &= recipes
        if not items:
            continue
        ha, hh = hostile.get(faction, (False, False))
        side = ("" if ha else "A") + ("" if hh else "H")
        if not side:
            continue  # hostile to everyone: nobody buys here
        for it in items:
            e = out.setdefault(str(it), {"A": False, "H": False, "v": []})
            e["A"] = e["A"] or "A" in side
            e["H"] = e["H"] or "H" in side
            e["v"].append([name, side])
    for e in out.values():
        e["v"].sort()
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor_factions.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
    one = sum(1 for e in out.values() if e["A"] != e["H"])
    print(f"{len(out)} patterns sold by vendors ({one} to one faction only) -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
