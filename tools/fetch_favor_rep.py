#!/usr/bin/env python3
"""Reputation needed to buy each Merchant's Favor pattern, from Wowhead Forever's item
tooltips ("Requires Honored with this faction." - the vendor's trade faction).

The game's client tables don't carry it (it's set on the vendor, server-side), and
AllTheThings lists every pattern as Neutral, so this is the source. One request per
pattern, half a second apart (about 3 minutes for ~310 patterns).

Usage (from tools/, like the other importers that share code): python3 fetch_favor_rep.py ATT_FOREVER_DIR
Writes tools/favor_rep.json: {"rep": {"<itemID>": "Friendly" | "Honored" | ...}}
(patterns that need no reputation are left out).
"""
import json, os, re, sys, time, urllib.request

from import_favor import favor_items

UA = {"User-Agent": "Mozilla/5.0"}


def main():
    items = favor_items(sys.argv[1])
    rep, failed = {}, []
    for iid in sorted(items):
        url = f"https://nether.wowhead.com/forever/tooltip/item/{iid}"
        for attempt in range(3):
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
                    text = re.sub("<[^>]+>", " ", json.load(r).get("tooltip", ""))
                m = re.search(r"Requires (Friendly|Honored|Revered|Exalted) with", text)
                if m:
                    rep[str(iid)] = m.group(1)
                break
            except Exception:
                time.sleep(2 * (attempt + 1))
        else:
            failed.append(iid)
        time.sleep(0.5)
    if failed:
        sys.exit(f"no answer for {len(failed)} patterns: {failed[:10]}... (nothing written)")
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "favor_rep.json")
    json.dump({"source": "Wowhead Forever item tooltips (nether.wowhead.com), 'Requires <rank> with this faction.'",
               "rep": rep}, open(dst, "w"), indent=0, sort_keys=True)
    print(f"{len(items)} patterns read, {len(rep)} need reputation -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
