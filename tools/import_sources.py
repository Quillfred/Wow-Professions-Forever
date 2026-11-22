#!/usr/bin/env python3
"""Trim the "blank source" research CSV (recipes Wowhead's Recipes tab gave no source
for) to what gen_data.py uses, in tools/forever_sources.json:
  {spellId: {"src": [Vendor|Drop|Quest|Container|Holiday], "where": text,
             "likelyTrainer": true, "classic": true}}

- "where" is shown in the addon (pattern suggestions, tooltips).
- "Vendor" only when the details name a seller ("Sold by: ...").
- "likelyTrainer": no pattern item teaches it, and Wowhead knows a learn level.
  gen_data.py treats these as UNCONFIRMED trainer recipes (usable from yellow,
  labelled "not confirmed" until seen at a trainer in game), minus known exceptions.
- "classic": the source info came from Classic data and may differ in Forever.

Usage: python3 -I tools/import_sources.py blank-source-recipes.csv
"""
import csv, json, os, sys

out = {}
with open(sys.argv[1], newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        spell = str(int(r["spell_id"]))
        cat, details, origin = r["category"], r["source_details"].strip(), r["data_from"]
        e = {}
        if cat.startswith("No pattern known"):
            learned = r["learned_at"].strip()
            if learned.isdigit() and int(learned) < 300:
                e["likelyTrainer"] = True
        elif not cat.startswith("Pattern exists"):
            src = []
            if "Sold by:" in details: src.append("Vendor")
            if "Drop" in cat: src.append("Drop")
            if "Quest" in cat: src.append("Quest")
            if "Container" in cat: src.append("Container")
            if "Holiday" in cat: src.append("Holiday")
            if src: e["src"] = src
            if details: e["where"] = details[:120]
            if origin.startswith("Classic"): e["classic"] = True
        if e:
            out[spell] = e
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_sources.json")
with open(dst, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=0, sort_keys=True)
print(f"{len(out)} recipes -> {os.path.relpath(dst)}")
