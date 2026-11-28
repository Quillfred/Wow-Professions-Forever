#!/usr/bin/env python3
"""Merchant's Favor patterns and vendors -> SkillRoute/Favor.lua.

Forever's profession vendors in the Barrens (Horde) and Redridge Mountains (Alliance)
sell patterns for Merchant's Favor (currency 3402) only, no gold. Some also need
reputation with your side's trade faction (Durotar Supply and Logistics 2587 /
Azeroth Commerce Authority 2586).

Sources:
- AllTheThings' Forever database (MIT licence, github.com/ATTWoWAddon/AllTheThings,
  .contrib/.db/forever/expansion features/trade logistics.lua): vendors, their NPC ids
  and zone coordinates, each pattern they sell and its Favor cost.
- tools/favor_rep.json (tools/fetch_favor_rep.py): the reputation rank each pattern
  needs, from Wowhead Forever's item tooltips.
- Forever's client map tables (wago.tools): zone coordinates -> world and continent
  positions, for travel times (same conversion as import_att.py).

Usage: python3 -I tools/import_favor.py ATT_FOREVER_DIR WAGO_CACHE_DIR BUILD
Writes SkillRoute/Favor.lua.
"""
import csv, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CURRENCY, FACTIONS = 3402, {"A": 2586, "H": 2587}
STANDING = {"Friendly": 4, "Honored": 5, "Revered": 6, "Exalted": 7}  # Core.Standing's scale
PROF = {"Tailor": 197, "Enchanter": 333, "Enchanting": 333, "Alchemist": 171, "Blacksmith": 164,
        "Leatherworker": 165, "Engineer": 202, "Opportunist Engineer": 202, "Chef": 185}
PATH = os.path.join("expansion features", "trade logistics.lua")
CRATES = os.path.join("expansion features", "waylaid crates.lua")
# Favor for handing in each Sealed Crate (Wowhead Forever quests 91899-91907): gathering
# ("white") crates 5/10/15/20, crafted ("green") 10/20/30/40, Apprentice..Artisan.
SEALED_FAVOR = {248765: 5, 248766: 10, 248767: 15, 248768: 20, 248770: 10, 248771: 20, 248772: 30, 248773: 40}
FIRST_CRATE = 50  # the one-time Shipping Label quest (98247/98248): +50 Favor, +2,000 reputation


def vendor_blocks(att):
    """[(npcID, name, title, side, mapConst, x, y, block text)] of the Favor vendors."""
    text = open(os.path.join(att, PATH), encoding="utf-8").read()
    body = text[text.index("n(VENDORS"):]
    parts = re.split(r"\n\t\t\t\tn\((\d+), \{\t-- ([^<\n]+?) <([^>\n]+)>\n", body)
    out = []
    for k in range(1, len(parts), 4):
        nid, name, title, block = int(parts[k]), parts[k + 1].strip(), parts[k + 2], parts[k + 3]
        c = re.search(r"coord = \{ ([\d.]+), ([\d.]+), MAP\.(\w+)", block)
        side = "A" if "ALLIANCE_ONLY" in block[:400] else "H" if "HORDE_ONLY" in block[:400] else None
        if c and side:
            out.append((nid, name, title, side, c.group(3), float(c.group(1)), float(c.group(2)), block))
    return out


def recipes_in(block):
    """{itemID: (name, favor)} of the patterns in one vendor's block. ATT writes the cost
    two ways: {{ "c", MERCHANTS_FAVOR, 30 }} and { { "c", 3402, 30 } } (the chefs), the
    latter sometimes after a minReputation line."""
    out = {}
    for m in re.finditer(r'i\((\d+), \{\t-- ([^\n]+?) \(RECIPE!\)\n((?:[^\n]*\n){1,3}?)\s*\}\)', block):
        c = re.search(r'cost = \{ ?\{ "c", (?:MERCHANTS_FAVOR|%d), (\d+) \} ?\}' % CURRENCY, m.group(3))
        if c:
            out[int(m.group(1))] = (m.group(2), int(c.group(1)))
    return out


def favor_items(att):
    items = {}
    for v in vendor_blocks(att):
        items.update(recipes_in(v[7]))
    return items


def main():
    att, cache, build = sys.argv[1], sys.argv[2], sys.argv[3]
    maps = {k: int(v) for k, v in re.findall(r"\b([A-Z_0-9]+)\s*=\s*(\d+)\s*;",
                                             open(os.path.join(att, ".config", "constants", "maps.lua"), encoding="utf-8").read())}
    tbl = lambda t: os.path.join(cache, f"{t}-{build}.csv")
    uimap = {int(r["ID"]): r for r in csv.DictReader(open(tbl("UiMap"), encoding="utf-8"))}
    assigns = {}
    for r in csv.DictReader(open(tbl("UiMapAssignment"), encoding="utf-8")):
        assigns.setdefault(int(r["UiMapID"]), []).append(r)

    def box(a):
        return ([float(a[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")],
                [float(a[f"Region_{i}"]) for i in (0, 1, 3, 4)])

    def to_world(ui, u, v):  # zone fraction -> (mapID, worldX, worldY)
        for a in assigns.get(ui, []):
            (u0, v0, u1, v1), (x0, y0, x1, y1) = box(a)
            if u0 <= u <= u1 and v0 <= v <= v1 and u1 > u0 and v1 > v0:
                return int(a["MapID"]), x1 - (v - v0) / (v1 - v0) * (x1 - x0), y1 - (u - u0) / (u1 - u0) * (y1 - y0)

    def continent(mapid, wx, wy):  # world -> (continent uiMap, x%, y%)
        for ui, rows in assigns.items():
            if uimap.get(ui, {}).get("Type") != "2":  # continent maps only
                continue
            for a in rows:
                if int(a["MapID"]) != mapid:
                    continue
                (u0, v0, u1, v1), (x0, y0, x1, y1) = box(a)
                if x0 <= wx <= x1 and y0 <= wy <= y1 and x1 > x0 and y1 > y0:
                    u = u0 + (y1 - wy) / (y1 - y0) * (u1 - u0)
                    v = v0 + (x1 - wx) / (x1 - x0) * (v1 - v0)
                    return ui, round(u * 100, 2), round(v * 100, 2)
        return None, None, None

    # NO_WOWHEAD=1: without Wowhead-derived data (reputation needs, crate contents)
    no_wowhead = os.environ.get("NO_WOWHEAD") == "1"
    rep = {} if no_wowhead else json.load(open(os.path.join(HERE, "favor_rep.json"), encoding="utf-8"))["rep"]
    npcs, patterns, sellers = [], {}, {}
    vendors = vendor_blocks(att)
    # The two sides' vendors of a profession sell the same Favor patterns (checked: same
    # lists and costs). Where ATT has one side's list and not the other's (Aza'bek, the
    # Horde chef, seen selling the Smoothies in game), use the other side's.
    by_title = {}
    for v in vendors:
        by_title.setdefault((v[2], v[3]), recipes_in(v[7]))
    for nid, name, title, side, mconst, zx, zy, block in vendors:
        rec = recipes_in(block)
        if not rec and PROF.get(title):
            rec = by_title.get((title, "A" if side == "H" else "H")) or {}
            if rec:
                print(f"note: {name} ({side}): no Favor list in ATT; using the other side's {title} list ({len(rec)})")
        if not rec:
            continue  # supply officers, mule handlers: no patterns
        ui = maps[mconst]
        w = to_world(ui, zx / 100, zy / 100)
        if not w:
            sys.exit(f"{name}: no world position for map {ui}")
        cui, cx, cy = continent(*w)
        zone = uimap[ui]["Name_lang"]
        npcs.append((nid, name, side, w[0], round(w[1], 1), round(w[2], 1), cui or 0, cx or 0, cy or 0, zone, zx, zy, ui))
        for iid, (pname, cost) in rec.items():
            old = patterns.get(iid)
            if old and old[0] != cost:
                print(f"note: {pname} costs {old[0]} and {cost} at different vendors; keeping {min(old[0], cost)}")
            patterns[iid] = (min(cost, old[0]) if old else cost, STANDING.get(rep.get(str(iid)), 0), pname)
            sellers.setdefault(iid, []).append(nid)

    # Waylaid Crates: what each accepts (tools/crates.json), what it pays, and who takes them
    crates = {} if no_wowhead else json.load(open(os.path.join(HERE, "crates.json"), encoding="utf-8"))["crates"]
    ctext = open(os.path.join(att, CRATES), encoding="utf-8").read()
    hand = {}
    for side, key in (("A", "aqd"), ("H", "hqd")):
        m = re.search(key + r" = \{\s*qg = (\d+),\s*-- ([^<\n]+?) <[^\n]*\n\s*coord = \{ ([\d.]+), ([\d.]+), MAP\.(\w+)", ctext)
        if not m:
            sys.exit(f"no {key} hand-in NPC in {CRATES}")
        nid, name, zx, zy, ui = int(m.group(1)), m.group(2).strip(), float(m.group(3)), float(m.group(4)), maps[m.group(5)]
        w = to_world(ui, zx / 100, zy / 100)
        cui, cx, cy = continent(*w)
        npcs.append((nid, name, side, w[0], round(w[1], 1), round(w[2], 1), cui or 0, cx or 0, cy or 0,
                     uimap[ui]["Name_lang"], zx, zy, ui))
        hand[side] = nid
    bundle_names = {}

    def lstr(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = ["-- Generated by tools/import_favor.py from AllTheThings' Forever database (MIT), Wowhead",
             "-- Forever item tooltips (reputation) and Forever's map tables. Do not edit.",
             "-- Merchant's Favor patterns: bought with Favor (currency 3402) only, never gold.",
             "local D = SkillRouteData",
             "if not D then return end",
             f"D.favor = {{ currency = {CURRENCY}, factions = {{ A = {FACTIONS['A']}, H = {FACTIONS['H']} }},",
             "  -- [pattern item] = { Favor, reputation needed (Core.Standing's scale: 4 Friendly, 5 Honored; 0 none) }",
             "  patterns = {"]
    for iid in sorted(patterns):
        cost, rank, pname = patterns[iid]
        lines.append(f"    [{iid}]={{{cost},{rank}}}, -- {pname}")
    lines += ["  },",
              f"  firstCrate = {FIRST_CRATE},",
              f"  handIn = {{ A = {hand['A']}, H = {hand['H']} }},",
              "  -- Waylaid Crates: [crate item] = { Favor paid (nil: unknown), level needed, sealed crate,",
              "  --   { bundle item, count, bundle item, count, ... } } (any ONE bundle fills it)",
              "  crates = {"]
    for cid in sorted(crates, key=int):
        c = crates[cid]
        fav = SEALED_FAVOR.get(c["sealed"])
        flat = ",".join(f"{b[0]},{b[1]}" for b in c["bundles"])
        for b in c["bundles"]:
            bundle_names[b[0]] = b[2]
        lines.append(f"    [{cid}]={{{fav if fav else 'nil'},{c['level'] or 0},{c['sealed']},{{{flat}}}}}, -- {c['name'][15:]}")
    lines += ["  },",
              "  -- names of bundle items (for ones SkillRoute's data doesn't otherwise have)",
              "  names = {"]
    for iid in sorted(bundle_names):
        lines.append(f"    [{iid}]={lstr(bundle_names[iid])},")
    lines += ["  },", "}",
              "-- the vendors, in Data.npcs' format",
              "local npcs = {"]
    for n in sorted(npcs):
        nid, name, side, mapid, wx, wy, cui, cx, cy, zone, zx, zy, ui = n
        lines.append(f"  [{nid}]={{{lstr(name)},{lstr(side)},{mapid},{wx},{wy},{cui},{cx},{cy},{lstr(zone)},{zx},{zy},{ui}}},")
    lines += ["}",
              "-- who sells each pattern",
              "local sellers = {"]
    for iid in sorted(sellers):
        lines.append(f"  [{iid}]={{{','.join(str(x) for x in sorted(set(sellers[iid])))}}},")
    lines += ["}",
              "D.npcs = D.npcs or {}",
              "D.vendorNpcs = D.vendorNpcs or {}",
              "for id, n in pairs(npcs) do D.npcs[id] = n end",
              "for item, ids in pairs(sellers) do",
              "  D.vendorNpcs[item] = ids",
              "  -- no gold price: the Classic data's vendor price doesn't apply (Favor only)",
              "  local it = D.items and D.items[item]",
              "  if it then it[3] = nil end",
              "  if D.patternVendors then D.patternVendors[item] = nil end",
              "end", ""]
    dst = os.path.join(HERE, "..", "SkillRoute", "Favor.lua")
    open(dst, "w", encoding="utf-8").write("\n".join(lines))
    gated = sum(1 for p in patterns.values() if p[1])
    print(f"{len(patterns)} Favor patterns ({gated} need reputation), {len(npcs) - 2} vendors, {len(crates)} crates, "
          f"2 crate hand-ins -> SkillRoute/Favor.lua")


if __name__ == "__main__":
    main()
