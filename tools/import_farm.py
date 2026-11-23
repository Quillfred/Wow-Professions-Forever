#!/usr/bin/env python3
"""Where to farm Cooking ingredients that aren't on the auction house.

Which ingredients: reagents of Forever's Cooking recipes (client SkillLineAbility +
SpellReagents) that no recipe makes. Sources, from the cMaNGOS Classic database:
- mob drops (creature_loot_template, following reference tables; chance 0 in a group
  = an equal share of what's left), mob names and levels, spawns;
- fishing loot per area (fishing_loot_template) with the zone's fishing level.
A mob's zone is the zone of the nearest herb/ore node (tools/zone_points.json from
import_gather.py: those zones come from pool descriptions), within 400 yards; mobs
farther from any node are left out rather than guessed.

Usage: (cd tools && python3 import_farm.py CLASSICDB.sql.gz WAGO_CACHE_DIR BUILD)
Writes tools/zone_sides.json ({zone: "A"|"H"}, contested zones left out) and
tools/farm.json: {item: {"mobs": [[name, zone, chance%, minLvl, maxLvl, spawns]],
                                "fish": [[zone, chance%, fishingLevel]]}}
"""
import csv, json, math, os, sys
from import_vendors import sql_rows, columns

COOKING = "185"
NEAR = 400.0  # yards to the nearest named node


def main():
    sqlgz, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    here = os.path.dirname(os.path.abspath(__file__))
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")

    spells = {r["Spell"] for r in csv.DictReader(open(tbl("SkillLineAbility"), encoding="utf-8"))
              if r["SkillLine"] == COOKING}
    made = {r["EffectItemType"] for r in csv.DictReader(open(tbl("SpellEffect"), encoding="utf-8"))
            if r["Effect"] == "24"}
    wanted = set()
    for r in csv.DictReader(open(tbl("SpellReagents"), encoding="utf-8")):
        if r["SpellID"] in spells:
            for i in range(8):
                it = r[f"Reagent_{i}"]
                if it != "0" and it not in made:
                    wanted.add(int(it))

    def chances(table):
        """loot entry -> {item: chance%}, resolving groups and reference tables"""
        rows = {}
        for r in sql_rows(sqlgz, table):
            rows.setdefault(int(r[0]), []).append((int(r[1]), float(r[2] or 0), int(r[3] or 0), int(r[4] or 0)))
        return rows
    ref = chances("reference_loot_template")

    def resolve(entries, scale=1.0, depth=0):
        out, groups = {}, {}
        for item, ch, grp, mc in entries:
            groups.setdefault(grp, []).append((item, ch, mc))
        for grp, members in groups.items():
            explicit = sum(c for _, c, _ in members if c > 0)
            zero = [m for m in members if m[1] <= 0]
            share = max(0.0, 100 - explicit) / len(zero) if (grp and zero) else 0
            for item, ch, mc in members:
                c = (ch if ch > 0 else share) * scale
                if mc < 0 and depth < 3:  # a reference: its items at this row's chance
                    for it2, c2 in resolve(ref.get(-mc, []), abs(ch) / 100 * scale if ch else scale, depth + 1).items():
                        out[it2] = out.get(it2, 0) + c2
                elif item in wanted and c > 0:
                    out[item] = out.get(item, 0) + c
        return out

    # mobs
    cl = chances("creature_loot_template")
    cc = columns(sqlgz, "creature_template")
    E, N, L, MIN, MAX = (cc.index(k) for k in ("Entry", "Name", "LootId", "MinLevel", "MaxLevel"))
    drops = {}  # creature -> {item: chance}
    info = {}
    for r in sql_rows(sqlgz, "creature_template"):
        lid = int(r[L] or 0)
        if lid and lid in cl:
            d = resolve(cl[lid])
            if d:
                drops[int(r[E])] = d
                info[int(r[E])] = (r[N], int(r[MIN]), int(r[MAX]))

    pts = json.load(open(os.path.join(here, "zone_points.json")))
    grid = {}
    for m, x, y, z in pts:
        grid.setdefault((m, int(x // NEAR), int(y // NEAR)), []).append((x, y, z))

    def zone_at(m, x, y):
        best, bd = None, NEAR * NEAR
        gx, gy = int(x // NEAR), int(y // NEAR)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for px, py, z in grid.get((m, gx + dx, gy + dy), []):
                    d = (px - x) ** 2 + (py - y) ** 2
                    if d < bd:
                        best, bd = z, d
        return best

    spawns = {}  # (creature, zone) -> count
    for r in sql_rows(sqlgz, "creature"):
        e = int(r[1])
        if e in drops:
            z = zone_at(int(r[2]), float(r[4]), float(r[5]))
            if z:
                spawns[(e, z)] = spawns.get((e, z), 0) + 1

    out = {}
    for (e, z), n in spawns.items():
        name, lo, hi = info[e]
        for item, ch in drops[e].items():
            out.setdefault(str(item), {"mobs": [], "fish": []})["mobs"].append([name, z, round(ch, 1), lo, hi, n])
    # Whose territory each zone is: Forever's AreaTable FactionGroupMask on the top-level
    # zone (2 Alliance, 4 Horde, 0 contested). Several rows can share a name; any one
    # tagged with a side decides it.
    area = {int(r["ID"]): r for r in csv.DictReader(open(tbl("AreaTable"), encoding="utf-8"))}
    side = {}
    for r in area.values():
        if r["ParentAreaID"] == "0" and r["ContinentID"] in ("0", "1") and r["AreaName_lang"]:
            m = int(r["FactionGroupMask"] or 0)
            s = "A" if m & 2 and not m & 4 else "H" if m & 4 and not m & 2 else None
            if s or r["AreaName_lang"] not in side:
                side[r["AreaName_lang"]] = s

    def best(rows, zone, key, n):
        # the n best for each faction (leaving out the other faction's land), merged:
        # a Horde player still gets Horde options when the top few are Alliance zones
        keep = []
        for me in ("A", "H"):
            ok = [x for x in sorted(rows, key=key) if side.get(zone(x)) in (None, me)]
            keep += [x for x in ok[:n] if x not in keep]
        for x in sorted(rows, key=key)[:n]:  # and the best overall, enemy land included
            if x not in keep:
                keep.append(x)
        return sorted(keep, key=key)

    for d in out.values():  # best: chance x spawns
        d["mobs"] = best(d["mobs"], lambda m: m[1], lambda m: -m[2] * m[5], 4)

    # fish

    def top_zone(a):
        for _ in range(5):
            r = area.get(a)
            if not r:
                return None
            if r["ParentAreaID"] == "0":
                return r["AreaName_lang"] if r["ContinentID"] in ("0", "1") else None
            a = int(r["ParentAreaID"])
    level = {}
    for r in sql_rows(sqlgz, "skill_fishing_base_level"):
        z = top_zone(int(r[0]))
        if z:
            level[z] = min(level.get(z, 999), int(r[1]))
    fl = chances("fishing_loot_template")
    for a, entries in fl.items():
        z = top_zone(a)
        if not z:
            continue
        for item, ch in resolve(entries).items():
            d = out.setdefault(str(item), {"mobs": [], "fish": []})
            if not any(f[0] == z for f in d["fish"]):
                d["fish"].append([z, round(ch, 1), level.get(z, 0)])
    for d in out.values():
        d["fish"] = best(d["fish"], lambda f: f[0], lambda f: (-f[1], f[2]), 3)
    with open(os.path.join(here, "zone_sides.json"), "w", encoding="utf-8") as f:  # farming, gathering, fishing
        json.dump({z: v for z, v in side.items() if v}, f, separators=(",", ":"), sort_keys=True)

    with open(os.path.join(here, "farm.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
    print(f"{len(wanted)} raw Cooking ingredients; farm sources for {len(out)} "
          f"({sum(1 for d in out.values() if d['mobs'])} from mobs, {sum(1 for d in out.values() if d['fish'])} from fishing)")


if __name__ == "__main__":
    main()
