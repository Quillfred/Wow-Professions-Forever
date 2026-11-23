#!/usr/bin/env python3
"""Herb and ore nodes: the skill each needs and where they spawn, per zone.

Skill requirement: Forever's own Lock table (Type 2 = skill; index 2 Herbalism,
3 Mining). Node spawns and which pool they belong to: the cMaNGOS Classic
database (GPL v3). Zones come from the pool descriptions ("Peacebloom - Mulgore -
subzone 6", "Mineral nodes - Hillsbrad Foothills - ..."), matched against Forever's
zone names; spawns whose zone can't be named that way are left out rather than
guessed (zone rectangles overlap).

Usage: python3 -I tools/import_gather.py CLASSICDB.sql.gz WAGO_CACHE_DIR BUILD
Writes tools/gather.json: {"182"|"186": [{"n": node, "req": skill, "zones": {zone: expected nodes}}]}
(spawns weighted by their chance in shared spawn points)
"""
import csv, json, os, sys
from import_vendors import sql_rows, columns

LOCK_SKILL = "2"
KIND = {"2": 182, "3": 186}  # lock index -> Herbalism, Mining


def main():
    sqlgz, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")
    lock = {}
    for r in csv.DictReader(open(tbl("Lock"), encoding="utf-8")):
        if r["Type_0"] == LOCK_SKILL and r["_Index_0"] in KIND:
            lock[r["ID"]] = (KIND[r["_Index_0"]], int(r["Skill_0"]))
    zones = sorted({r["Name_lang"] for r in csv.DictReader(open(tbl("UiMap"), encoding="utf-8"))
                    if r["Type"] in ("3", "4") and r["Name_lang"]}, key=len, reverse=True)

    gc = columns(sqlgz, "gameobject_template")
    E, T, N, D0 = (gc.index(k) for k in ("entry", "type", "name", "data0"))
    nodes = {}
    for r in sql_rows(sqlgz, "gameobject_template"):
        if r[T] == "3" and r[D0] in lock:
            nodes[int(r[E])] = (r[N],) + lock[r[D0]]

    mother = {int(r[0]): int(r[1]) for r in sql_rows(sqlgz, "pool_pool")}
    pdesc = {int(r[0]): r[2] for r in sql_rows(sqlgz, "pool_template")}
    # A spawn point in a pool holds one of several nodes: its chance (cMaNGOS: an
    # explicit chance, else the rest of 100% shared equally). Weighting by it keeps
    # rare ores (Silver, Gold, Truesilver) from looking as common as Copper.
    pool_of, members = {}, {}
    for r in sql_rows(sqlgz, "pool_gameobject"):
        guid, pool, chance = int(r[0]), int(r[1]), float(r[2] or 0)
        pool_of[guid] = (pool, r[3])
        members.setdefault(pool, []).append((guid, chance))
    weight = {}
    for pool, ms in members.items():
        explicit = sum(c for _, c in ms if c > 0)
        zero = [g for g, c in ms if c <= 0]
        share = max(0.0, 100 - explicit) / len(zero) if zero else 0
        for g, c in ms:
            weight[g] = (c if c > 0 else share) / 100

    def zone_of(guid):
        texts = []
        if guid in pool_of:
            pool, d = pool_of[guid]
            texts.append(d)
            for _ in range(4):
                texts.append(pdesc.get(pool, ""))
                if pool not in mother:
                    break
                pool = mother[pool]
        for t in texts:
            for z in zones:  # longest name first: "Hillsbrad Foothills" before "Hillsbrad"
                if z and z in t:
                    return z
        return None

    out, kept, dropped = {}, 0, 0
    points = []  # (map, x, y, zone) of every placed node: reused to name mob zones
    for r in sql_rows(sqlgz, "gameobject"):
        guid, entry = int(r[0]), int(r[1])
        if entry not in nodes:
            continue
        name, line, req = nodes[entry]
        z = zone_of(guid)
        if not z:
            dropped += 1
            continue
        kept += 1
        points.append((int(r[2]), float(r[4]), float(r[5]), z))
        d = out.setdefault(str(line), {}).setdefault(name, {"n": name, "req": req, "zones": {}})
        d["zones"][z] = d["zones"].get(z, 0) + weight.get(guid, 1.0)
    for d in out.values():
        for nd in d.values():
            nd["zones"] = {z: round(c, 1) for z, c in nd["zones"].items() if c >= 0.5}
    res = {line: sorted((x for x in d.values() if x["zones"]), key=lambda x: (x["req"], x["n"]))
           for line, d in out.items()}
    # Fishing: each zone's fishing level (Classic skill_fishing_base_level), named with
    # Forever's AreaTable; only top-level zones on the two continents.
    area = {int(r["ID"]): r for r in csv.DictReader(open(tbl("AreaTable"), encoding="utf-8"))}
    fish = []
    for r in sql_rows(sqlgz, "skill_fishing_base_level"):
        a = area.get(int(r[0]))
        if a and a["ParentAreaID"] == "0" and a["ContinentID"] in ("0", "1") and a["AreaName_lang"]:
            fish.append([a["AreaName_lang"], int(r[1])])
    res["fishing"] = sorted(fish, key=lambda z: (z[1], z[0]))
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "zone_points.json"), "w") as f:
        json.dump([[m, round(x), round(y), z] for m, x, y, z in points], f, separators=(",", ":"))
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gather.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(res, f, separators=(",", ":"), sort_keys=True)
    print(f"{kept} node spawns placed in zones ({dropped} left out: no zone in their pool) -> {os.path.relpath(dst)}")
    for line, lst in res.items():
        if line == "fishing":
            print("  Fishing zones:", ", ".join(f"{z} {s}" for z, s in lst))
        else:
            print(" ", {"182": "Herbalism", "186": "Mining"}[line], ", ".join(f"{x['n']} {x['req']}" for x in lst))


if __name__ == "__main__":
    main()
