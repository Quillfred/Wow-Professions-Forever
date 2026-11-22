#!/usr/bin/env python3
"""Trim a Wowhead Forever recipe export (JSON from the profession pages' Recipes tab)
to what gen_data.py uses: {skillId: {spellId: [learnedAt, [sources], trainingCostCopper]}}.

Usage: python3 -I tools/import_wowhead.py EXPORT.json
Writes tools/wowhead_forever.json.
"""
import json, os, sys

src = json.load(open(sys.argv[1], encoding="utf-8"))
out = {"source": src.get("source"), "extracted": src.get("extracted"), "professions": {}}
for p in src["professions"]:
    rec = {}
    for r in p["recipes"]:
        learned = r.get("learnedAt")
        sources = sorted(set(r.get("source") or []))
        cost = r.get("trainingCostCopper")
        if not isinstance(learned, int): learned = None
        if not isinstance(cost, int): cost = None
        rec[str(int(r["spellId"]))] = [learned, sources, cost]
    out["professions"][str(int(p["skillId"]))] = rec
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wowhead_forever.json")
with open(dst, "w", encoding="utf-8") as f:
    json.dump(out, f, separators=(",", ":"), sort_keys=True)
print(f"{sum(len(v) for v in out['professions'].values())} recipes -> {os.path.relpath(dst)}")
