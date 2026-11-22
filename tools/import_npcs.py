#!/usr/bin/env python3
"""Profession trainers and pattern vendors: name, faction, zone and map coordinates.

NPC spawns, trainer lists and vendor lists are server-side, so they come from the
open-source cMaNGOS Classic database (github.com/cmangos/classic-db, GPL v3).
Everything else is Forever's own client data (wago.tools, same build): which
factions an NPC will deal with (FactionTemplate), which spell is which profession
rank (SpellEffect), and the zone maps used to turn a world position into the zone
name and the map coordinates you see in game (UiMapAssignment, UiMap).

Usage: python3 -I tools/import_npcs.py CLASSICDB.sql.gz WAGO_CACHE_DIR BUILD [NPC IDs to print]
Writes tools/npcs.json. Classic data: Forever may have moved, added or removed NPCs;
NPCs you visit in game override this.
"""
import csv, json, os, sys
from import_vendors import sql_rows, columns, ALLIANCE, HORDE, GROUP_PLAYER, GROUP_ALLIANCE, GROUP_HORDE

PROFESSIONS = {171, 164, 333, 202, 165, 197, 185, 129}
EFFECT_SKILL_STEP, EFFECT_LEARN = "118", "36"
UIMAP_ZONE, UIMAP_CONTINENT = "3", "2"


def rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def main():
    sqlgz, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")

    sides = {}
    for r in rows(tbl("FactionTemplate")):
        enemy = int(r["EnemyGroup"])
        enemies = {int(r[f"Enemies_{k}"]) for k in range(8)}
        ha = bool(enemy & (GROUP_PLAYER | GROUP_ALLIANCE)) or bool(enemies & ALLIANCE)
        hh = bool(enemy & (GROUP_PLAYER | GROUP_HORDE)) or bool(enemies & HORDE)
        sides[int(r["ID"])] = ("" if ha else "A") + ("" if hh else "H")

    # spell -> (skill line, rank step 1-4); learn spells ("Expert Tailoring") map to the
    # spell they teach.
    step, learn = {}, {}
    for r in rows(tbl("SpellEffect")):
        if r["Effect"] == EFFECT_SKILL_STEP and int(r["EffectMiscValue_0"]) in PROFESSIONS:
            step[int(r["SpellID"])] = (int(r["EffectMiscValue_0"]), int(float(r["EffectBasePointsF"])))
        elif r["Effect"] == EFFECT_LEARN:
            learn[int(r["SpellID"])] = int(r["EffectTriggerSpell"])
    for s, t in learn.items():
        if t in step and s not in step:
            step[s] = step[t]

    # zone maps
    uimap = {int(r["ID"]): r for r in rows(tbl("UiMap"))}
    all_assigns = list(rows(tbl("UiMapAssignment")))
    zone_assigns = [r for r in all_assigns
                    if int(r["UiMapID"]) in uimap and uimap[int(r["UiMapID"])]["Type"] == UIMAP_ZONE]
    # the continent map for each world map (Kalimdor, Eastern Kingdoms): full-width assignment
    continent = {}
    for r in all_assigns:
        m = int(r["UiMapID"])
        if m in uimap and uimap[m]["Type"] == UIMAP_CONTINENT and float(r["UiMin_0"]) == 0 and float(r["UiMax_0"]) == 1:
            continent.setdefault(int(r["MapID"]), r)

    def project(a, x, y):
        x0, y0, x1, y1 = (float(a[f"Region_{i}"]) for i in (0, 1, 3, 4))
        u0, v0, u1, v1 = (float(a[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
        # map left->right = world +Y -> -Y, top->bottom = world +X -> -X
        u = u0 + (u1 - u0) * (y1 - y) / (y1 - y0)
        v = v0 + (v1 - v0) * (x1 - x) / (x1 - x0)
        return round(u * 100, 2), round(v * 100, 2)

    def zone_of(mapid, x, y):
        """Zone name + coords, only when exactly one zone's rectangle contains the point
        (zone rectangles overlap; the game itself resolves the rest at runtime)."""
        hits = {}
        for a in zone_assigns:
            if int(a["MapID"]) != mapid:
                continue
            x0, y0, x1, y1 = (float(a[f"Region_{i}"]) for i in (0, 1, 3, 4))
            if x0 <= x <= x1 and y0 <= y <= y1:
                hits.setdefault(int(a["UiMapID"]), a)
        if len(hits) != 1:
            return None
        (mid, a), = hits.items()
        u, v = project(a, x, y)
        return uimap[mid]["Name_lang"], round(u, 1), round(v, 1)

    def continent_of(mapid, x, y):
        a = continent.get(mapid)
        if not a:
            return None
        u, v = project(a, x, y)
        return int(a["UiMapID"]), u, v

    cc = columns(sqlgz, "creature_template")
    E, N, F, VT, TT = (cc.index(k) for k in ("Entry", "Name", "Faction", "VendorTemplateId", "TrainerTemplateId"))
    tmpl = {int(r[E]): r for r in sql_rows(sqlgz, "creature_template")}

    teaches = {}
    for r in sql_rows(sqlgz, "npc_trainer"):
        teaches.setdefault(("npc", int(r[0])), set()).add(int(r[1]))
    for r in sql_rows(sqlgz, "npc_trainer_template"):
        teaches.setdefault(("tpl", int(r[0])), set()).add(int(r[1]))

    vendor_items = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor_factions.json")))
    sells = {}
    for r in sql_rows(sqlgz, "npc_vendor"):
        sells.setdefault(("npc", int(r[0])), set()).add(int(r[1]))
    for r in sql_rows(sqlgz, "npc_vendor_template"):
        sells.setdefault(("tpl", int(r[0])), set()).add(int(r[1]))

    trainers, vendors, wanted = {}, {}, set()
    for entry, t in tmpl.items():
        spells = teaches.get(("npc", entry), set()) | teaches.get(("tpl", int(t[TT] or 0)), set())
        for s in spells:
            if s in step:
                line, st = step[s]
                trainers.setdefault(str(line), {}).setdefault(str(entry), set()).add(st)
                wanted.add(entry)
        items = sells.get(("npc", entry), set()) | sells.get(("tpl", int(t[VT] or 0)), set())
        for it in items:
            if str(it) in vendor_items:
                vendors.setdefault(str(it), []).append(entry)
                wanted.add(entry)

    check = {int(a) for a in sys.argv[4:]}  # extra NPC IDs: print their zone/coords to verify
    npcs = {}
    for r in sql_rows(sqlgz, "creature"):
        if int(r[1]) in check:
            check.discard(int(r[1]))
            print("check", tmpl[int(r[1])][N], zone_of(int(r[2]), float(r[4]), float(r[5])),
                  continent_of(int(r[2]), float(r[4]), float(r[5])))
        entry = int(r[1])
        if entry in wanted and str(entry) not in npcs:
            mapid, x, y = int(r[2]), float(r[4]), float(r[5])
            t = tmpl[entry]
            side = sides.get(int(t[F]), "")
            if not side:
                continue  # hostile to both factions
            z, c = zone_of(mapid, x, y), continent_of(mapid, x, y)
            npcs[str(entry)] = {"n": t[N], "side": side, "map": mapid, "x": round(x, 1), "y": round(y, 1),
                                "cui": c[0] if c else None, "cx": c[1] if c else None, "cy": c[2] if c else None,
                                "zone": z[0] if z else None, "zx": z[1] if z else None, "zy": z[2] if z else None}
    out = {"npcs": npcs,
           "trainers": {line: {e: sorted(s) for e, s in d.items() if e in npcs} for line, d in trainers.items()},
           "vendors": {it: sorted({e for e in es if str(e) in npcs}) for it, es in vendors.items()}}
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npcs.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
    print(f"{len(npcs)} NPCs ({sum(len(d) for d in out['trainers'].values())} trainer entries, "
          f"{len(out['vendors'])} patterns with vendors) -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
