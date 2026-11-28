#!/usr/bin/env python3
"""What each Waylaid Crate accepts, from Wowhead Forever's crate tooltips ("Fill the crate
with any bundle from the following list: - 20 Dream Dust - 4 Greater Nether Essence ...")
and its level requirement. Bundle item names are matched to item ids with Forever's own
item table (ItemSparse, wago.tools).

AllTheThings (MIT) lists the crates and the Sealed Crate each becomes, but not what goes
in them. One request per crate, half a second apart (~30 crates).

Usage: python3 -I tools/fetch_crates.py ATT_FOREVER_DIR WAGO_CACHE_DIR BUILD
Writes tools/crates.json: {"crates": {"<crate item>": {"name", "sealed", "level",
"bundles": [[itemID, count, name], ...]}}}
"""
import csv, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join("expansion features", "waylaid crates.lua")
UA = {"User-Agent": "Mozilla/5.0"}
SAME_NAME = {"Dark Iron Ore": 11370}  # two items share the name; 11370 is the ore (11099: quest item)


def main():
    att, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    text = open(os.path.join(att, PATH), encoding="utf-8").read()
    crates = [(int(m.group(1)), m.group(2), int(m.group(3))) for m in re.finditer(
        r"i\((\d+), \{\t-- (Waylaid Crate: [^\n]+)\n\s*i\((\d+)\)", text)]
    items = os.path.join(cache, f"ItemSparse-{build}.csv")
    if not os.path.exists(items):
        urllib.request.urlretrieve(f"https://wago.tools/db2/ItemSparse/csv?build={build}", items)
    byname = {}
    for r in csv.DictReader(open(items, encoding="utf-8")):
        byname.setdefault(r["Display_lang"], []).append(int(r["ID"]))
    out = {}
    for iid, name, sealed in crates:
        url = f"https://nether.wowhead.com/forever/tooltip/item/{iid}"
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
            tip = re.sub("<[^>]+>", "\n", json.load(r).get("tooltip", ""))
        lvl = re.search(r"Requires Level\s*(\d+)", tip.replace("\n", " "))
        bundles = []
        for n, bname in re.findall(r"- (\d+) ([^\n]+)", tip):
            bname = bname.strip()
            ids = byname.get(bname, [])
            if bname in SAME_NAME:
                ids = [SAME_NAME[bname]]
            if len(ids) != 1:
                sys.exit(f"{name}: '{bname}' matches {len(ids)} items {ids[:5]}; add it to SAME_NAME")
            bundles.append([ids[0], int(n), bname])
        if not bundles:
            sys.exit(f"{name}: no bundles in its tooltip (nothing written)")
        out[str(iid)] = {"name": name, "sealed": sealed, "level": int(lvl.group(1)) if lvl else None, "bundles": bundles}
        time.sleep(0.5)
    dst = os.path.join(HERE, "crates.json")
    json.dump({"source": "Wowhead Forever crate tooltips; ATT (MIT) for the crate list", "crates": out},
              open(dst, "w"), indent=0, sort_keys=True)
    print(f"{len(out)} crates -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
