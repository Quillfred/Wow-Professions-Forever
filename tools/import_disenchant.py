#!/usr/bin/env python3
"""What crafted items disenchant into, and the Enchanting skill needed.

Forever's client table ItemDisenchantLoot says which items can be disenchanted: rows of
(item class, subclass or -1 = any, quality, item level range) with the skill needed.
What a row yields lives on the server, so the contents come from the cMaNGOS Classic
database (GPL v3): disenchant_loot_template, keyed by item_template.DisenchantID.
The two key spaces differ, so each Forever row is matched to the cMaNGOS loot entry
that the items it covers use most (items both databases have). Items new in Forever
then get their row from their own class, quality and level (ItemSparse + Item).

Usage: (cd tools && python3 import_disenchant.py CLASSICDB.sql.gz WAGO_CACHE_DIR BUILD)
Writes tools/disenchant.json:
  {"loot": {lootKey: [[item, chance%, min, max], ...]},   # expected per disenchant
   "rows": [[class, subclass, quality, minLvl, maxLvl, skill, lootKey], ...]}
"""
import csv, json, os, sys
from collections import Counter
from import_vendors import sql_rows, columns


def main():
    sqlgz, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    here = os.path.dirname(os.path.abspath(__file__))
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")

    rows = []  # Forever's disenchant brackets
    for r in csv.DictReader(open(tbl("ItemDisenchantLoot"), encoding="utf-8")):
        rows.append({"id": int(r["ID"]), "cls": int(r["Class"]), "sub": int(r["Subclass"]), "q": int(r["Quality"]),
                     "lo": int(r["MinLevel"]), "hi": int(r["MaxLevel"]), "skill": int(r["SkillRequired"])})

    def row_for(cls, sub, q, lvl):
        best = None
        for w in rows:
            if w["cls"] == cls and w["q"] == q and w["lo"] <= lvl <= w["hi"] and w["sub"] in (-1, sub):
                if best is None or w["sub"] != -1:  # an exact subclass beats "any"
                    best = w
        return best

    # cMaNGOS loot entries: groups where chance 0 = an equal share of what's left
    groups = {}
    for r in sql_rows(sqlgz, "disenchant_loot_template"):
        e, item, ch, grp, mn, mx = int(r[0]), int(r[1]), float(r[2] or 0), int(r[3] or 0), int(r[4] or 0), int(r[5] or 0)
        if mn < 0:
            continue  # references: not used by disenchant tables in this database
        groups.setdefault(e, {}).setdefault(grp, []).append((item, ch, mn, mx))
    loot = {}
    for e, gs in groups.items():
        out = []
        for grp, members in gs.items():
            explicit = sum(c for _, c, _, _ in members if c > 0)
            zero = [m for m in members if m[1] <= 0]
            share = max(0.0, 100 - explicit) / len(zero) if (grp and zero) else 0
            for item, ch, mn, mx in members:
                c = ch if ch > 0 else share
                if c > 0:
                    out.append([item, round(c, 2), mn, max(mn, mx)])
        loot[str(e)] = sorted(out, key=lambda x: -x[1])

    # match each Forever row to the cMaNGOS entry its items use
    ic = columns(sqlgz, "item_template")
    E, C, S, Q, L, D = (ic.index(k) for k in ("entry", "class", "subclass", "Quality", "ItemLevel", "DisenchantID"))
    votes = {}
    for r in sql_rows(sqlgz, "item_template"):
        d = int(r[D] or 0)
        if d and str(d) in loot:
            w = row_for(int(r[C]), int(r[S]), int(r[Q]), int(r[L]))
            if w:
                votes.setdefault(w["id"], Counter())[d] += 1
    out_rows, unmatched = [], 0
    for w in rows:
        v = votes.get(w["id"])
        if not v:
            unmatched += 1
            continue
        out_rows.append([w["cls"], w["sub"], w["q"], w["lo"], w["hi"], w["skill"], str(v.most_common(1)[0][0])])
    used = {r[6] for r in out_rows}
    res = {"loot": {k: v for k, v in loot.items() if k in used}, "rows": sorted(out_rows)}
    with open(os.path.join(here, "disenchant.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, separators=(",", ":"), sort_keys=True)
    print(f"{len(out_rows)} of {len(rows)} Forever disenchant brackets matched to Classic loot "
          f"({unmatched} with no shared items), {len(res['loot'])} loot tables -> disenchant.json")


if __name__ == "__main__":
    main()
