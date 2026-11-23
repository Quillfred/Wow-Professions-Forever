#!/usr/bin/env python3
"""Build SkillRoute/Data.lua from WoW Forever's client game tables (via wago.tools).

Usage: python3 -I tools/gen_data.py [BUILD] [CACHE_DIR]
  BUILD      client build, e.g. 1.60.1.71037 (default: newest "wowf" build on wago.tools)
  CACHE_DIR  where the CSV tables are downloaded (default: ./.db2cache)

Everything recipe-related comes from the client tables. Two things are NOT in the
client and are handled at runtime by the addon instead: the skill a trainer
recipe is learned at (read from the trainer window) and which recipes a trainer
actually teaches (until confirmed, assumed learnable at its yellow skill).
"""
import csv, json, os, sys, urllib.request, concurrent.futures as cf

PROFESSIONS = {171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering",
               165: "Leatherworking", 197: "Tailoring", 185: "Cooking", 129: "First Aid"}
TABLES = ["SkillLineAbility", "SpellReagents", "SpellName", "SpellEffect",
          "ItemSparse", "ItemEffect", "ItemXItemEffect", "SpellCooldowns",
          "SpellTotems", "TotemCategory", "Faction", "TaxiNodes", "TaxiPath", "TaxiPathNode"]
FLY_SPEED = 32      # yards/second on a flight path
FLY_OVERHEAD = 10   # seconds: take-off, landing
# Not trainer recipes even though no item teaches them (quest rewards etc.). Only
# used when the player knows them.
NOT_TRAINER = {22813, 22815, 19435,  # Gordok Ogre Suits (quest), Mooncloth Boots (quest)
               11452,                # Restorative Potion (quest)
               23486, 23489, 13240}  # Goblin/Gnomish specialization only
SOD_SPELLS = range(400000, 500000)
# Materials whose only source is a cooldown craft (scarce, priced accordingly).
# Checked against the client: these are made only by spells with a cooldown and not
# smelted or otherwise crafted. Elemental essences are left out: transmutes make
# them too, but they mostly drop from mobs.
COOLDOWN_MATS = {"Mooncloth", "Arcanite Bar", "Legionite Bar"}   # Season of Discovery recipes: never assumed trainer
# Reagents sold by trade-supply vendors. Used only as a price fallback; Auctionator's
# own vendor price wins when it has one. Matched by name, prices from the client.
VENDOR = {"Coarse Thread", "Fine Thread", "Silken Thread", "Heavy Silken Thread", "Rune Thread",
          "Red Dye", "Blue Dye", "Gray Dye", "Green Dye", "Yellow Dye", "Black Dye", "Orange Dye",
          "Purple Dye", "Bleach", "Salt", "Mild Spices", "Hot Spices", "Refreshing Spring Water",
          "Ice Cold Milk", "Simple Flour", "Empty Vial", "Leaded Vial", "Crystal Vial",
          "Imbued Vial", "Weak Flux", "Strong Flux", "Copper Rod", "Simple Wood",
          "Heavy Stock", "Wooden Stock", "Engineer's Ink",
          # tools sold by trade-supply vendors
          "Blacksmith Hammer", "Flint and Tinder", "Mining Pick", "Skinning Knife"}
MAX_SKILL = 300  # Forever's profession cap; recipes only usable above it are dropped
SPELL_EFFECT_CREATE_ITEM, SPELL_EFFECT_LEARN_SPELL, ITEM_TRIGGER_ON_LEARN = "24", "36", "6"


UA = {"User-Agent": "SkillRoute-datagen/1.0"}  # wago.tools refuses Python's default agent


def latest_build():
    with urllib.request.urlopen(urllib.request.Request("https://wago.tools/api/builds", headers=UA), timeout=30) as r:
        return json.load(r)["wowf"][0]["version"]


def fetch(build, cache):
    os.makedirs(cache, exist_ok=True)
    def one(t):
        path = os.path.join(cache, f"{t}-{build}.csv")
        if not os.path.exists(path):  # tables are immutable per build: never re-download
            url = f"https://wago.tools/db2/{t}/csv?build={build}"
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r, \
                    open(path + ".part", "wb") as f:
                f.write(r.read())
            os.replace(path + ".part", path)
        return t, path
    with cf.ThreadPoolExecutor(len(TABLES)) as ex:
        return dict(ex.map(one, TABLES))


def rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else latest_build()
    cache = sys.argv[2] if len(sys.argv) > 2 else ".db2cache"
    p = fetch(build, cache)
    # Optional: learn levels / sources / trainer costs from Wowhead (tools/import_wowhead.py).
    wowhead = {}
    whpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wowhead_forever.json")
    if os.path.exists(whpath):
        with open(whpath, encoding="utf-8") as f:
            wowhead = {int(k): {int(sp): v for sp, v in rec.items()}
                       for k, rec in json.load(f)["professions"].items()}

    # Optional: sources for recipes Wowhead's Recipes tab left blank (tools/import_sources.py).
    extra = {}
    xpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_sources.json")
    if os.path.exists(xpath):
        with open(xpath, encoding="utf-8") as f:
            extra = {int(k): v for k, v in json.load(f).items()}

    # Optional: which factions can buy each pattern from a vendor (tools/import_vendors.py).
    vendor_sides = {}
    vpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor_factions.json")
    if os.path.exists(vpath):
        with open(vpath, encoding="utf-8") as f:
            vendor_sides = {int(k): v for k, v in json.load(f).items()}

    # Optional: trainers / pattern vendors with zone + coordinates (tools/import_npcs.py).
    npcdata = {"npcs": {}, "trainers": {}, "vendors": {}}
    npath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npcs.json")
    if os.path.exists(npath):
        with open(npath, encoding="utf-8") as f:
            npcdata = json.load(f)

    abil = {}  # spell -> SkillLineAbility row (crafting recipes only)
    for r in rows(p["SkillLineAbility"]):
        sl = int(r["SkillLine"])
        if sl in PROFESSIONS and int(r["TrivialSkillLineRankHigh"]) > 0:
            abil[int(r["Spell"])] = r
    names = {int(r["ID"]): r["Name_lang"] for r in rows(p["SpellName"]) if int(r["ID"]) in abil}

    reagents = {}
    for r in rows(p["SpellReagents"]):
        s = int(r["SpellID"])
        if s in abil:
            lst = [(int(r[f"Reagent_{i}"]), int(r[f"ReagentCount_{i}"])) for i in range(8)]
            reagents[s] = [(i, c) for i, c in lst if i > 0 and c > 0]

    creates, learn_spell, rank1 = {}, {}, {}
    for r in rows(p["SpellEffect"]):
        s = int(r["SpellID"])
        # the Apprentice rank spell of each profession (effect 118, step 1): its name is
        # the profession's name in the player's language, for matching at runtime
        if r["Effect"] == "118" and float(r["EffectBasePointsF"] or 0) == 1:
            rank1.setdefault(int(r["EffectMiscValue_0"]), s)
        if r["Effect"] == SPELL_EFFECT_CREATE_ITEM and s in abil and int(r["EffectItemType"]) > 0:
            creates[s] = (int(r["EffectItemType"]), max(1, int(float(r["EffectBasePointsF"]))))
        elif r["Effect"] == SPELL_EFFECT_LEARN_SPELL and int(r["EffectTriggerSpell"]) in abil:
            learn_spell[s] = int(r["EffectTriggerSpell"])

    effect_items = {}
    for r in rows(p["ItemXItemEffect"]):
        effect_items.setdefault(int(r["ItemEffectID"]), []).append(int(r["ItemID"]))
    taught_by = {}  # recipe spell -> [pattern item ids]
    for r in rows(p["ItemEffect"]):
        s = int(r["SpellID"])
        target = s if (s in abil and r["TriggerType"] == ITEM_TRIGGER_ON_LEARN) else learn_spell.get(s)
        if target:
            for it in effect_items.get(int(r["ID"]), []):
                taught_by.setdefault(target, set()).add(it)

    cooldown = {}  # spell -> seconds (e.g. Mooncloth ~4 days): never grindable
    for r in rows(p["SpellCooldowns"]):
        s = int(r["SpellID"])
        if s in abil:
            ms = max(int(r["RecoveryTime"]), int(r["CategoryRecoveryTime"]))
            if ms > 0:
                cooldown[s] = ms // 1000

    items = {}
    for r in rows(p["ItemSparse"]):
        items[int(r["ID"])] = r

    # Tools: recipes that need an item in your bags (rods, hammers, spanners).
    # A tool category is satisfied by any item of the same type whose mask covers it
    # (a Runed Arcanite Rod counts as every lower rod). Key -ItemID = one exact item.
    cats = {int(r["ID"]): (int(r["TotemCategoryType"]), int(r["TotemCategoryMask"]), r["Name_lang"])
            for r in rows(p["TotemCategory"])}
    needs_tool = {}
    for r in rows(p["SpellTotems"]):
        s = int(r["SpellID"])
        if s in abil:
            t = [int(r[k]) for k in ("RequiredTotemCategoryID_0", "RequiredTotemCategoryID_1") if int(r[k])]
            t += [-int(r[k]) for k in ("Totem_0", "Totem_1") if int(r[k])]
            if t:
                needs_tool[s] = t
    def satisfying(cat):
        if cat < 0:
            return [-cat]
        typ, mask, _ = cats[cat]
        out = []
        for iid, r in items.items():
            c = int(r["TotemCategoryID"] or 0)
            if c and c in cats and cats[c][0] == typ and (cats[c][1] & mask) == mask:
                out.append(iid)
        return sorted(out)
    tool_items = {}

    used_items, vendor_patterns, used_factions = set(), set(), set()
    out = {sl: [] for sl in PROFESSIONS}
    for s, a in sorted(abil.items()):
        if s not in reagents or s not in names:
            continue  # not a craft (no reagents) -> nothing to plan
        y, g = int(a["TrivialSkillLineRankLow"]), int(a["TrivialSkillLineRankHigh"])
        pats = sorted(taught_by.get(s, ()))
        learn, cost, origin = None, None, None
        w = wowhead.get(int(a["SkillLine"]), {}).get(s)  # [learnedAt, [sources], trainingCost]
        x = extra.get(s, {})
        where = x.get("where")
        if where and x.get("classic"):
            where += " (Classic data)"
        if a["AcquireMethod"] == "1":
            src = "a"  # learned together with the profession
        elif w and "Trainer" in w[1]:
            src = "T"  # a trainer teaches it (Wowhead), learnable at w[0]
            learn, cost = (w[0] if w[0] is not None else y), w[2]
        elif pats:
            src = "p"
            ranks = [int(items[i]["RequiredSkillRank"]) for i in pats
                     if i in items and int(items[i]["RequiredSkill"]) == int(a["SkillLine"])]
            # when it starts giving skill-ups (Wowhead) beats the pattern item's own requirement
            learn = w[0] if (w and w[0] is not None) else (min(ranks) if ranks else None)
            origin = (w and w[1]) or x.get("src")
        elif (w is None and s < 100000 and s not in NOT_TRAINER) or \
                (x.get("likelyTrainer") and s not in NOT_TRAINER and s not in SOD_SPELLS):
            src = "t"  # probably a trainer recipe (no item teaches it): confirmed in game at the trainer
        else:
            src = "x"  # quest/special/no known source: only used if the character knows it
            origin = w and w[1]
        if (learn if learn is not None else y) >= MAX_SKILL:
            continue
        o = creates.get(s)
        used_items.update(i for i, _ in reagents[s])
        used_items.update(pats)
        if o:
            used_items.add(o[0])
        fields = [f"n={lua_str(names[s])}", f"y={y}", f"g={g}", f'src="{src}"']
        if learn is not None:
            fields.append(f"learn={learn}")
        if cost:
            fields.append(f"tc={cost}")
        if where:
            fields.append(f"where={lua_str(where)}")
        if origin:
            fields.append(f"from={lua_str('/'.join(origin))}")
            if "Vendor" in origin:
                vendor_patterns.update(pats)
        if o:
            fields.append(f"out={o[0]}")
            if o[1] != 1:
                fields.append(f"outN={o[1]}")
        fields.append("r={" + ",".join(f"{i},{c}" for i, c in reagents[s]) + "}")
        if pats:
            fields.append("pat={" + ",".join(map(str, pats)) + "}")
            # Pattern items that need faction reputation: {item, factionID, rank 0-7,...}
            # (rank: 4 Friendly, 5 Honored, 6 Revered, 7 Exalted)
            reps = []
            for i in pats:
                f = int(items.get(i, {}).get("MinFactionID", 0) or 0)
                if f:
                    reps += [i, f, int(items[i]["MinReputation"] or 0)]
                    used_factions.add(f)
            if reps:
                fields.append("rep={" + ",".join(map(str, reps)) + "}")
        if s in cooldown:
            fields.append(f"cd={cooldown[s]}")
        if s in needs_tool:
            fields.append("tool={" + ",".join(map(str, needs_tool[s])) + "}")
            for c in needs_tool[s]:
                if c not in tool_items:
                    tool_items[c] = satisfying(c)
                    used_items.update(tool_items[c])
        out[int(a["SkillLine"])].append(f"    [{s}]={{{','.join(fields)}}},")

    GATHER = {186: "Mining", 182: "Herbalism", 393: "Skinning"}
    lines = ["-- GENERATED by tools/gen_data.py from WoW Forever client build " + build
             + (" + Wowhead learn levels/sources" if wowhead else "") + ". Do not edit.",
             "SkillRouteData = {", f'  build = "{build}",', "  professions = {"]
    for sl, name in PROFESSIONS.items():
        sp = f", spell = {rank1[sl]}" if sl in rank1 else ""
        lines += [f'  [{sl}] = {{ name = {lua_str(name)}{sp}, recipes = {{'] + out[sl] + ["  }},"]
    for sl, name in GATHER.items():  # gathering: no recipes, a zone route instead
        sp = f", spell = {rank1[sl]}" if sl in rank1 else ""
        lines.append(f'  [{sl}] = {{ name = {lua_str(name)}{sp}, recipes = {{}}, gather = true }},')
    lines += ["  },", "  -- [itemID] = {name, vendorSellPrice, vendorBuyPrice-or-nil (trade-supply reagents)}",
              "  items = {"]
    for i in sorted(used_items):
        r = items.get(i)
        if not r:
            continue
        vendor = r["Display_lang"] in VENDOR or i in vendor_patterns
        buy = r["BuyPrice"] if vendor and int(r["BuyPrice"]) > 0 else "nil"
        lines.append(f"    [{i}]={{{lua_str(r['Display_lang'])},{r['SellPrice']},{buy}}},")
    lines += ["  },", "  -- [toolKey] = {name, itemIDs that satisfy it}; negative key = that exact item",
              "  tools = {"]
    tools_start = len(lines)
    for c in sorted(tool_items):
        name = cats[c][2] if c > 0 else items.get(-c, {}).get("Display_lang", str(-c))
        lines.append(f"    [{c}]={{{lua_str(name)},{{{','.join(map(str, tool_items[c]))}}}}},")
    lines += ["  },", "  -- reagents only made by cooldown crafts (Mooncloth...): avoided unless /sr cdmats on",
              "  cooldownMats = {"]
    for i in sorted(used_items):
        if items.get(i, {}).get("Display_lang") in COOLDOWN_MATS:
            lines.append(f"    [{i}]=true,")
    # Trainers, pattern vendors and their NPCs. AllTheThings' Forever data first
    # (tools/import_att.py: exact zone coordinates, the recipe tier each trainer
    # teaches, vendors' pattern lists); Classic data (tools/import_npcs.py) for NPCs
    # and patterns ATT doesn't list yet.
    att = {"npcs": {}, "trainers": {}, "vendors": {}, "recipeTier": {}}
    apath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "att_forever.json")
    if os.path.exists(apath):
        with open(apath, encoding="utf-8") as f:
            att = json.load(f)
    conts = npcdata.get("continents", {})

    def continent(mapid, x, y):
        c = conts.get(str(mapid))
        if c is None or x is None:
            return None
        x0, y0, x1, y1 = c["r"]
        u0, v0, u1, v1 = c["u"]
        return c["ui"], round((u0 + (u1 - u0) * (y1 - y) / (y1 - y0)) * 100, 2), round((v0 + (v1 - v0) * (x1 - x) / (x1 - x0)) * 100, 2)

    npc_rows = {}  # key -> (name, side, lua row)
    SIDE_K = {"A": 1, "H": 2, "AH": 3}

    def att_npc(k):
        n = att["npcs"][k]
        key = -(n["id"] * 10 + SIDE_K[n["side"]])  # negative: never collides with Classic IDs
        if key not in npc_rows:
            c = continent(n["map"], n["x"], n["y"])
            v = lambda val: "nil" if val is None else str(val)
            npc_rows[key] = (n["n"], n["side"],
                             f"{{{lua_str(n['n'])},\"{n['side']}\",{v(n['map'])},{v(n['x'])},{v(n['y'])},"
                             f"{v(c and c[0])},{v(c and c[1])},{v(c and c[2])},{lua_str(n['zone'] or '')},"
                             f"{n['zx']},{n['zy']},{n['ui']}}}")
        return key

    def classic_npc(e):
        n = npcdata["npcs"].get(str(e))
        if not n:
            return None
        if e not in npc_rows:
            zone = lua_str(n["zone"]) if n["zone"] else "nil"
            v = lambda k: "nil" if n.get(k) is None else str(n[k])
            npc_rows[e] = (n["n"], n["side"],
                           f"{{{lua_str(n['n'])},\"{n['side']}\",{n['map']},{n['x']},{n['y']},"
                           f"{v('cui')},{v('cx')},{v('cy')},{zone},{v('zx')},{v('zy')}}}")
        return e

    # trainers: [line] = {[npc] = bitmask of recipe tiers taught (1 Apprentice, 2 Journeyman,
    # 4 Expert, 8 Artisan); a tier holds its rank-up spell and its recipes
    tr_lines = []
    for line in sorted(set(PROFESSIONS) | set(GATHER)):
        entries = {}
        att_ids = set()
        for k, tiers in att["trainers"].get(str(line), {}).items():
            entries[att_npc(k)] = sum(1 << (t - 1) for t in tiers)
            att_ids.add(att["npcs"][k]["id"])
        for e, rank in npcdata["trainers"].get(str(line), {}).items():
            # Classic fallback: a trainer titled rank R teaches tier R-1 (ATT confirms:
            # Magar <Expert> teaches JOURNEYMAN, Josef <Artisan> EXPERT, Master ARTISAN)
            if int(e) not in att_ids and rank >= 2 and classic_npc(int(e)) is not None:
                entries[int(e)] = 1 << (min(rank, 5) - 2)
        if entries:
            tr_lines.append(f"    [{line}]={{" + ",".join(f"[{k}]={m}" for k, m in sorted(entries.items())) + "},")
    lines += ["  },", "  -- trainers: [skillLine] = {[npc] = tiers taught, bits 1 Apprentice 2 Journeyman 4 Expert 8 Artisan}",
              "  trainers = {"] + tr_lines
    # recipe tier (ATT): which trainer tier teaches each recipe / rank-up spell
    recipes_all = {int(r.split("]")[0].strip()[1:]) for l in out.values() for r in l}
    tier_lines = [f"[{sp}]={t}" for sp, t in sorted((int(k), v) for k, v in att["recipeTier"].items()) if sp in recipes_all]
    lines += ["  },", "  -- [recipe spell] = trainer tier that teaches it (1 Apprentice .. 4 Artisan), from ATT",
              "  recipeTier = {"]
    for i in range(0, len(tier_lines), 12):
        lines.append("    " + ",".join(tier_lines[i:i + 12]) + ",")
    # pattern vendors: ATT's where it lists the pattern, else Classic
    vend_lines, pv_lines = [], []
    for i in sorted(vendor_patterns):
        keys = [att_npc(k) for k, _ in att["vendors"].get(str(i), []) if k in att["npcs"]]
        if not keys:
            keys = [k for k in (classic_npc(e) for e in npcdata["vendors"].get(str(i), [])) if k is not None]
        if not keys:
            continue
        vend_lines.append(f"    [{i}]={{{','.join(map(str, keys))}}},")
        sides = "".join(sorted({c for k in keys for c in npc_rows[k][1]}))
        names_a = ", ".join(npc_rows[k][0] for k in keys if "A" in npc_rows[k][1])
        names_h = ", ".join(npc_rows[k][0] for k in keys if "H" in npc_rows[k][1])
        pv_lines.append(f"    [{i}]={{\"{sides}\",{lua_str(names_a)},{lua_str(names_h)}}},")
    lines += ["  },", "  -- [patternItem] = {who vendors sell it to \"A\"|\"H\"|\"AH\", Alliance vendors, Horde vendors}",
              "  patternVendors = {"] + pv_lines
    lines += ["  },", "  -- [patternItem] = {npc keys of vendors selling it}", "  vendorNpcs = {"] + vend_lines
    lines += ["  },", "  -- [npc] = {name, faction, map, worldX, worldY, continentUiMap, contX, contY, zone, zoneX, zoneY, zoneUiMap}",
              "  -- (zoneUiMap set = exact, from ATT; else Classic spawn, zone resolved by the game)",
              "  npcs = {"]
    for k in sorted(npc_rows):
        lines.append(f"    [{k}]={npc_rows[k][2]},")
    lines += ["  },", "  -- boats/zeppelins: {name, \"A\"|\"H\"|\"AH\", seconds per trip, {map, worldX, worldY}, ...}",
              "  transports = {"]
    for t in npcdata.get("transports", []):
        stops = ",".join("{%d,%d,%d}" % tuple(st) for st in t["stops"])
        lines.append(f"    {{{lua_str(t['name'])},\"{t['side']}\",{t['sec']},{stops}}},")
    lines += ["  },", "  -- continent maps: [map] = {uiMapID, worldX0, worldY0, worldX1, worldY1, uMin, vMin, uMax, vMax}",
              "  continents = {"]
    for m, c in sorted(npcdata.get("continents", {}).items()):
        lines.append(f"    [{m}]={{{c['ui']},{','.join(str(round(v, 3)) for v in c['r'] + c['u'])}}},")
    # Flight paths (Forever client): flight masters and the direct flights between
    # them; a flight's time = length of its route / FLY_SPEED. MountCreatureID_0 is the
    # Horde mount, _1 the Alliance one (a node without a mount for a side isn't theirs).
    taxi_nodes = {}
    for r in rows(p["TaxiNodes"]):
        cont = int(r["ContinentID"])
        side = ("A" if int(r["MountCreatureID_1"]) else "") + ("H" if int(r["MountCreatureID_0"]) else "")
        if cont in (0, 1) and side:
            taxi_nodes[int(r["ID"])] = (cont, float(r["Pos_0"]), float(r["Pos_1"]), side, r["Name_lang"])
    route = {}
    for r in rows(p["TaxiPathNode"]):
        route.setdefault(int(r["PathID"]), []).append((int(r["NodeIndex"]), int(r["ContinentID"]),
                                                        float(r["Loc_0"]), float(r["Loc_1"])))
    flights, used_taxi = [], set()
    for r in rows(p["TaxiPath"]):
        a, b, pid = int(r["FromTaxiNode"]), int(r["ToTaxiNode"]), int(r["ID"])
        pts = sorted(route.get(pid, []))
        if a not in taxi_nodes or b not in taxi_nodes or len(pts) < 2:
            continue
        length = sum(((p2[2] - p1[2]) ** 2 + (p2[3] - p1[3]) ** 2) ** 0.5
                     for p1, p2 in zip(pts, pts[1:]) if p1[1] == p2[1])
        flights.append((a, b, round(length / FLY_SPEED + FLY_OVERHEAD)))
        used_taxi.update((a, b))
    lines += ["  },", "  -- flight paths: nodes [id] = {map, worldX, worldY, \"A\"|\"H\"|\"AH\", name};",
              "  -- flights {from, to, seconds}. Only flight points the character knows are used.",
              "  taxi = { nodes = {"]
    for i in sorted(used_taxi):
        m, x, y, sd, nm = taxi_nodes[i]
        lines.append(f"    [{i}]={{{m},{round(x)},{round(y)},\"{sd}\",{lua_str(nm)}}},")
    lines += ["  }, flights = {"]
    for k in range(0, len(flights), 8):
        lines.append("    " + ",".join("{%d,%d,%d}" % f for f in flights[k:k + 8]) + ",")
    lines += ["  } },"]
    factions = {int(r["ID"]): r["Name_lang"] for r in rows(p["Faction"])}
    # gathering nodes (tools/import_gather.py): [skillLine] = {{node, skill, {zone, spawns, ...}}, ...}
    gpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gather.json")
    gather = json.load(open(gpath, encoding="utf-8")) if os.path.exists(gpath) else {}
    # rare variants that replace common ore at the same spots now and then: never a
    # planned step (the pool data gives them equal shares, overstating them)
    RARE_NODES = {"Silver Vein", "Gold Vein", "Truesilver Deposit"}
    lines += ["  -- gathering nodes: [skillLine] = {{node, skill needed, {zone, spawns, ...}, rare}, ...} (top zones)",
              "  gather = {"]
    for line, nodes in sorted(gather.items()):
        rows_ = []
        for nd in nodes:
            top = sorted(nd["zones"].items(), key=lambda kv: -kv[1])[:6]
            rows_.append("{%s,%d,{%s}%s}" % (lua_str(nd["n"]), nd["req"],
                                              ",".join(f"{lua_str(z)},{round(c)}" for z, c in top),
                                              ",true" if nd["n"] in RARE_NODES else ""))
        lines.append(f"    [{line}]={{" + ",".join(rows_) + "},")
    lines += ["  },", "  factions = {"]
    for f in sorted(used_factions):
        lines.append(f"    [{f}]={lua_str(factions.get(f, str(f)))},")
    lines += ["  },", "}", ""]
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SkillRoute", "Data.lua")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"build {build}: " + ", ".join(f"{PROFESSIONS[sl]} {len(v)}" for sl, v in out.items())
          + f"; {len(used_items)} items -> {os.path.relpath(dst)}")


if __name__ == "__main__":
    main()
